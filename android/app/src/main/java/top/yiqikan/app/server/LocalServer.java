package top.yiqikan.app.server;

import android.content.Context;
import android.util.Log;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.BufferedInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.DatagramPacket;
import java.net.DatagramSocket;
import java.net.Inet4Address;
import java.net.HttpURLConnection;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.net.NetworkInterface;
import java.net.ServerSocket;
import java.net.Socket;
import java.net.URL;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Enumeration;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * 机内 HTTP/1.1 + WebSocket 服务。
 *
 * 端口固定 8080（libapp.so 里的 URL 已等长替换成 http://127.0.0.1:8080）。
 * 同时监听 0.0.0.0，方便同一局域网的朋友手机改指向本机 IP 后"一起看"。
 */
public final class LocalServer {

    public static final String TAG = "YiqikanLocal";
    public static final int PORT = Integer.getInteger("yiqikan.local.port", 8080);

    /** D25：局域网房间广播的 UDP 端口（只发不收，收的那一半在下一轮客户端做） */
    static final int LAN_PORT = 45231;

    // D27：本地规则版房间 Bot（不接 LLM）。只放内存，不写 rooms.json，重启即清（与 VOICE 一致）。
    /** room -> 配置 */
    static final java.util.Map<String, BotCfg> BOTS =
            new java.util.concurrent.ConcurrentHashMap<String, BotCfg>();
    /** room|alias -> elapsedRealtime（冷却用；不能用 currentTimeMillis，会被改表） */
    static final java.util.Map<String, Long> BOT_AT =
            new java.util.concurrent.ConcurrentHashMap<String, Long>();
    /** room|alias -> {hourIndex, count}（每小时配额） */
    static final java.util.Map<String, int[]> BOT_HOUR =
            new java.util.concurrent.ConcurrentHashMap<String, int[]>();

    static final class BotCfg {
        String memberId = "";
        String name = "小看";
        java.util.List<String> aliases = new java.util.ArrayList<String>();
        String reply = "我在";
        int cooldownSec = 10;
        int hourlyQuota = 30;
        boolean occupySlot = false; // 默认不占位，与 10 号 D28 一致
        boolean enabled = true;
    }


    private static LocalServer INSTANCE;

    public static synchronized LocalServer get(Context ctx) {
        if (INSTANCE == null) INSTANCE = new LocalServer(ctx.getApplicationContext());
        return INSTANCE;
    }

    private final Context ctx;
    private ServerSocket server;
    private ExecutorService pool;
    private volatile boolean running = false;
    private Thread acceptThread;
    /** D25：房间广播线程（null = 没起） */
    private UdpBeacon beacon;

    /** 活跃的 WebSocket 连接 */
    public final List<Ws> wsList = Collections.synchronizedList(new ArrayList<Ws>());

    private LocalServer(Context ctx) {
        this.ctx = ctx;
    }

    public boolean isRunning() {
        return running;
    }

    public synchronized void start() {
        if (running) return;
        boolean dual = false;
        try {
            // 先尝试双栈（:: 通配，同时收 IPv4-mapped 与 IPv6），异地 IPv6 直连必须靠它
            server = new ServerSocket();
            server.setReuseAddress(true);
            try {
                server.bind(new InetSocketAddress(java.net.InetAddress.getByName("::"), PORT), 64);
                dual = true;
            } catch (Throwable e6) {
                Log.w(TAG, "IPv6 wildcard bind failed, fallback to 0.0.0.0: " + e6);
                try {
                    server.close();
                } catch (Throwable ignored) {
                }
                server = new ServerSocket();
                server.setReuseAddress(true);
                server.bind(new InetSocketAddress("0.0.0.0", PORT), 64);
            }
            running = true;
        } catch (Throwable t) {
            Log.e(TAG, "bind " + PORT + " failed: " + t, t);
            running = false;
            return;
        }
        pool = Executors.newCachedThreadPool();
        acceptThread = new Thread(new Runnable() {
            @Override
            public void run() {
                acceptLoop();
            }
        }, "yiqikan-http");
        acceptThread.setDaemon(true);
        acceptThread.start();
        // D25：HTTP 起来之后再起广播线程；它自己吞异常，不影响 8080
        try {
            beacon = new UdpBeacon();
            beacon.start();
        } catch (Throwable t) {
            Log.w(TAG, "[YQK-LAN] beacon fail start " + t);
        }
        Log.i(TAG, "listening on " + (dual ? "[::] + 0.0.0.0" : "0.0.0.0") + ":" + PORT + "  lan=" + lanIp());
        // E7：DDNS 定时器挂在这个服务的生命周期上（不另起 Service）
        try {
            Ddns.get(ctx).start();
        } catch (Throwable t) {
            Log.w("YQK-DDNS", "[YQK-DDNS] start fail " + t);
        }
        // E9：有配置就顺手连一次中继；没配置 configure 里直接置 lastError="未配置中继"
        try {
            Store st0 = Store.get(ctx);
            Relay.get(ctx).configure(st0 == null ? "" : st0.relay,
                    st0 == null ? "" : st0.relayToken);
        } catch (Throwable t) {
            Log.w("YQK-RELAY", "[YQK-RELAY] boot fail " + t);
        }
    }

    public synchronized void stop() {
        running = false;
        // D25：先停广播线程，再关 HTTP
        if (beacon != null) {
            try {
                beacon.stop();
            } catch (Throwable ignored) {
            }
            beacon = null;
        }
        try {
            if (server != null) server.close();
        } catch (Throwable ignored) {
        }
        server = null;
        if (pool != null) pool.shutdownNow();
        pool = null;
        // E7/E9：服务和它们同生共死，别留后台线程
        try {
            Ddns.get(ctx).stop();
        } catch (Throwable ignored) {
        }
        try {
            Relay.get(ctx).stop();
        } catch (Throwable ignored) {
        }
    }

    private void acceptLoop() {
        while (running) {
            try {
                final Socket s = server.accept();
                s.setSoTimeout(30000);
                s.setTcpNoDelay(true);
                if (pool != null) {
                    pool.execute(new Runnable() {
                        @Override
                        public void run() {
                            handle(s);
                        }
                    });
                }
            } catch (Throwable t) {
                if (running) {
                    try {
                        Thread.sleep(50);
                    } catch (InterruptedException ignored) {
                    }
                }
            }
        }
    }

    // ================================================================ HTTP

    /** 请求 */
    public static final class Req {
        public String method = "GET";
        public String rawPath = "/";
        public String path = "/";
        public String query = "";
        public String version = "HTTP/1.1";
        public final Map<String, String> headers = new HashMap<String, String>();
        public String body = "";
        public JSONObject json = new JSONObject();
        public String remote = "";

        public String header(String k) {
            return headers.get(k.toLowerCase(Locale.US));
        }

        public String q(String k, String def) {
            String v = queryParam(query, k);
            return v == null ? def : v;
        }
    }

    /** 响应 */
    public static final class Res {
        public int code = 200;
        public String type = "application/json; charset=utf-8";
        public byte[] body = new byte[0];
        public final Map<String, String> headers = new HashMap<String, String>();

        public static Res json(JSONObject o) {
            Res r = new Res();
            r.body = o.toString().getBytes(Store.UTF8);
            return r;
        }

        public static Res text(String s, String type) {
            Res r = new Res();
            r.type = type;
            r.body = s.getBytes(Store.UTF8);
            return r;
        }

        /** 直出：rawJson 原样作为响应体，不再包一层 detail（与其余路由 {"ok":..,"data":..} 形状一致） */
        public static Res json(int code, String rawJson) {
            Res r = new Res();
            r.code = code;
            r.body = rawJson.getBytes(Store.UTF8);
            return r;
        }

        public static Res status(int code, String msg) {
            Res r = new Res();
            r.code = code;
            JSONObject o = new JSONObject();
            try {
                o.put("detail", msg);
            } catch (Throwable ignored) {
            }
            r.body = o.toString().getBytes(Store.UTF8);
            return r;
        }
    }

    private void handle(Socket s) {
        try {
            BufferedInputStream in = new BufferedInputStream(s.getInputStream());
            OutputStream out = s.getOutputStream();

            Req req = readRequest(in, s);
            if (req == null) {
                s.close();
                return;
            }

            // 客人侧：如果设了 peer（房主那台手机的地址），除 /local/* 外全部转发过去
            String peer = "";
            try {
                peer = Store.get(ctx).peer;
            } catch (Throwable ignored) {
            }
            final boolean proxied = peer != null && !peer.isEmpty()
                    && !req.path.startsWith("/local")
                    && !"/health".equals(req.path);

            // WebSocket 升级
            String upgrade = req.header("upgrade");
            if (upgrade != null && upgrade.toLowerCase(Locale.US).contains("websocket")) {
                if (!"/ws".equals(req.path) && !"/websocket".equals(req.path)
                        && !"/room".equals(req.path)
                        && !req.path.endsWith("/ws") && !req.path.endsWith("/room")) {
                    writeRes(out, req, Res.status(404, "no ws endpoint"), false);
                    s.close();
                    return;
                }
                if (proxied) {
                    proxyWs(s, in, out, req, peer);
                    return;
                }
                wsUpgrade(s, in, out, req);
                return;
            }

            // CORS 预检
            if ("OPTIONS".equals(req.method)) {
                Res r = new Res();
                r.code = 204;
                writeRes(out, req, r, true);
                s.close();
                return;
            }

            Res res;
            if (proxied) {
                proxyHttp(s, out, req, peer);
                return;
            }
            try {
                res = Api.handle(ctx, req);
            } catch (Throwable t) {
                Log.e(TAG, "api error " + req.method + " " + req.rawPath, t);
                JSONObject o = new JSONObject();
                try {
                    o.put("detail", "local server error: " + t);
                    o.put("success", false);
                } catch (Throwable ignored) {
                }
                res = Res.json(o);
                res.code = 500;
            }
            writeRes(out, req, res, true);
            s.close();
        } catch (Throwable t) {
            // 兜底：任何未预料的异常都要回一个 500 JSON，不许让客户端看到「连接被重置」
            Log.e(TAG, "handle error", t);
            try {
                byte[] body = Res.json(500, "{\"ok\":false,\"error\":\"internal\"}").body;
                java.io.BufferedOutputStream bo = new java.io.BufferedOutputStream(s.getOutputStream());
                bo.write(("HTTP/1.1 500 Internal Server Error\r\n"
                        + "Content-Type: application/json; charset=utf-8\r\n"
                        + "Access-Control-Allow-Origin: *\r\n"
                        + "Content-Length: " + body.length + "\r\nConnection: close\r\n\r\n").getBytes("UTF-8"));
                bo.write(body);
                bo.flush();
            } catch (Throwable ignored) {
            }
            try {
                s.close();
            } catch (Throwable ignored) {
            }
        }
    }

    /** 错误帧：必须带 type，客户端 switch 靠它分派；rid 让拒绝能关联到具体请求 */
    private static JSONObject errObj(String code, String rid, String msg) {
        JSONObject o = new JSONObject();
        try {
            o.put("type", "error");
            if (rid != null && !rid.isEmpty()) o.put("rid", rid);
            o.put("code", code);
            o.put("message", msg);
        } catch (Throwable ignored) {
        }
        return o;
    }
    private static JSONObject errObj(String msg) {
        JSONObject o = new JSONObject();
        try {
            o.put("success", false);
            o.put("detail", msg);
        } catch (Throwable ignored) {
        }
        return o;
    }

    /** peer 解析结果：支持 host:port、IPv6 方括号、http(s)/ws(s) 前缀、带路径 */
    static final class Target {
        String scheme = "http";
        String host = "127.0.0.1";
        int port = PORT;
        String basePath = "";

        boolean tls() {
            return "https".equals(scheme) || "wss".equals(scheme);
        }

        String hostForUrl() {
            return host.indexOf(':') >= 0 ? "[" + host + "]" : host;
        }

        String base() {
            return scheme + "://" + hostForUrl() + ":" + port + basePath;
        }

        String forLog() {
            return scheme + "://" + hostForUrl() + ":" + port + basePath;
        }
    }

    static Target parsePeer(String peer) {
        Target t = new Target();
        String s = peer == null ? "" : peer.trim();
        if (s.startsWith("https://")) {
            t.scheme = "https";
            t.port = 443;
            s = s.substring(8);
        } else if (s.startsWith("http://")) {
            t.scheme = "http";
            t.port = 80;
            s = s.substring(7);
        } else if (s.startsWith("wss://")) {
            t.scheme = "wss";
            t.port = 443;
            s = s.substring(6);
        } else if (s.startsWith("ws://")) {
            t.scheme = "ws";
            t.port = 80;
            s = s.substring(5);
        }
        int slash = s.indexOf('/');
        if (slash >= 0) {
            t.basePath = s.substring(slash);
            s = s.substring(0, slash);
        }
        if (s.startsWith("[")) {
            int close = s.indexOf(']');
            if (close > 0) {
                t.host = s.substring(1, close);
                String rest = s.substring(close + 1);
                if (rest.startsWith(":")) {
                    try {
                        t.port = Integer.parseInt(rest.substring(1).trim());
                    } catch (Throwable ignored) {
                    }
                }
                return t;
            }
        }
        int colon = s.lastIndexOf(':');
        if (colon > 0 && s.indexOf(':') == colon) {
            try {
                t.port = Integer.parseInt(s.substring(colon + 1).trim());
                s = s.substring(0, colon);
            } catch (Throwable ignored) {
            }
        }
        t.host = s;
        return t;
    }

    /** 把请求转发给房主那台手机（一起看） */
    private void proxyHttp(Socket s, OutputStream out, Req req, String peer) {
        HttpURLConnection c = null;
        Target tgt = parsePeer(peer);
        try {
            String path = req.rawPath.startsWith("/") ? req.rawPath : "/" + req.rawPath;
            String base = tgt.base();
            if (base.endsWith("/") && path.startsWith("/")) {
                base = base.substring(0, base.length() - 1);
            }
            URL url = new URL(base + path);
            c = (HttpURLConnection) url.openConnection();
            c.setRequestMethod(req.method);
            c.setConnectTimeout(5000);
            c.setReadTimeout(30000);
            c.setInstanceFollowRedirects(false);
            for (Map.Entry<String, String> e : req.headers.entrySet()) {
                String k = e.getKey().toLowerCase(Locale.US);
                if (k.equals("host") || k.equals("connection") || k.equals("content-length")
                        || k.equals("accept-encoding") || k.equals("transfer-encoding")) {
                    continue;
                }
                c.setRequestProperty(e.getKey(), e.getValue());
            }
            if (req.body != null && req.body.length() > 0 && !"GET".equals(req.method)) {
                byte[] b = req.body.getBytes(Store.UTF8);
                c.setDoOutput(true);
                c.setFixedLengthStreamingMode(b.length);
                OutputStream os = c.getOutputStream();
                os.write(b);
                os.flush();
                os.close();
            }
            int code = c.getResponseCode();
            InputStream is = code >= 400 ? c.getErrorStream() : c.getInputStream();
            ByteArrayOutputStream bo = new ByteArrayOutputStream();
            if (is != null) {
                byte[] buf = new byte[8192];
                int n;
                while ((n = is.read(buf)) > 0) bo.write(buf, 0, n);
                is.close();
            }
            Res res = new Res();
            res.code = code;
            String ct = c.getContentType();
            if (ct != null) res.type = ct;
            res.body = bo.toByteArray();
            res.headers.put("x-local-proxy", peer);
            writeRes(out, req, res, true);
            Log.i(TAG, "proxy " + req.method + " " + req.path + " -> " + peer + " " + code);
        } catch (Throwable t) {
            Res res = Res.json(errObj("peer unreachable: " + peer + " (" + t + ")"));
            res.headers.put("x-local-proxy", peer);
            try {
                writeRes(out, req, res, true);
            } catch (Throwable ignored) {
            }
        } finally {
            if (c != null) c.disconnect();
            try {
                s.close();
            } catch (Throwable ignored) {
            }
        }
    }

    /** WebSocket 双向转发（房间同步走它）；支持 https/wss 目标 */
    private void proxyWs(Socket s, InputStream in, OutputStream out, Req req, String peer) {
        Socket up = null;
        Target tgt = parsePeer(peer);
        try {
            Socket raw = new Socket();
            raw.connect(new InetSocketAddress(tgt.host, tgt.port), 8000);
            raw.setTcpNoDelay(true);
            if (tgt.tls()) {
                javax.net.ssl.SSLSocketFactory f = (javax.net.ssl.SSLSocketFactory)
                        javax.net.ssl.SSLSocketFactory.getDefault();
                javax.net.ssl.SSLSocket ssl = (javax.net.ssl.SSLSocket) f.createSocket(
                        raw, tgt.host, tgt.port, true);
                ssl.startHandshake();
                up = ssl;
            } else {
                up = raw;
            }
            final OutputStream uout = up.getOutputStream();
            final InputStream uin = up.getInputStream();

            String path = req.rawPath.startsWith("/") ? req.rawPath : "/" + req.rawPath;
            StringBuilder sb = new StringBuilder();
            sb.append(req.method).append(' ').append(tgt.basePath).append(path).append(" HTTP/1.1\r\n");
            for (Map.Entry<String, String> e : req.headers.entrySet()) {
                String k = e.getKey().toLowerCase(Locale.US);
                if (k.equals("host")) continue;
                sb.append(e.getKey()).append(": ").append(e.getValue()).append("\r\n");
            }
            sb.append("Host: ").append(tgt.hostForUrl())
                    .append(tgt.port == 80 || tgt.port == 443 ? "" : ":" + tgt.port).append("\r\n");
            sb.append("\r\n");
            uout.write(sb.toString().getBytes(Store.UTF8));
            uout.flush();

            byte[] hb = new byte[8192];
            int n = 0;
            while (n < hb.length) {
                int b = uin.read();
                if (b < 0) break;
                hb[n++] = (byte) b;
                if (n >= 4 && hb[n - 4] == '\r' && hb[n - 3] == '\n'
                        && hb[n - 2] == '\r' && hb[n - 1] == '\n') {
                    break;
                }
            }
            out.write(hb, 0, n);
            out.flush();
            Log.i(TAG, "ws proxy -> " + peer + " handshake " + n + "B");

            final Socket ups = up;
            final InputStream cin = in;
            final OutputStream cout = out;
            Thread t = new Thread(new Runnable() {
                public void run() {
                    byte[] buf = new byte[8192];
                    int k;
                    try {
                        while ((k = cin.read(buf)) > 0) {
                            uout.write(buf, 0, k);
                            uout.flush();
                        }
                    } catch (Throwable ignored) {
                    }
                    try {
                        ups.close();
                    } catch (Throwable ignored) {
                    }
                }
            }, "yiqikan-ws-up");
            t.setDaemon(true);
            t.start();

            byte[] buf2 = new byte[8192];
            int k2;
            while ((k2 = uin.read(buf2)) > 0) {
                cout.write(buf2, 0, k2);
                cout.flush();
            }
        } catch (Throwable t) {
            Log.w(TAG, "ws proxy failed: " + t);
        } finally {
            try {
                if (up != null) up.close();
            } catch (Throwable ignored) {
            }
            try {
                s.close();
            } catch (Throwable ignored) {
            }
        }
    }

    private Req readRequest(BufferedInputStream in, Socket s) throws IOException {
        String line = readLine(in);
        if (line == null || line.isEmpty()) return null;
        String[] parts = line.split(" ");
        if (parts.length < 2) return null;

        Req r = new Req();
        r.method = parts[0].toUpperCase(Locale.US);
        r.rawPath = parts[1];
        r.version = parts.length > 2 ? parts[2] : "HTTP/1.1";

        int q = r.rawPath.indexOf('?');
        if (q >= 0) {
            r.path = r.rawPath.substring(0, q);
            r.query = r.rawPath.substring(q + 1);
        } else {
            r.path = r.rawPath;
        }
        r.path = normalizePath(r.path);

        int len = 0;
        while (true) {
            String h = readLine(in);
            if (h == null || h.isEmpty()) break;
            int c = h.indexOf(':');
            if (c <= 0) continue;
            String k = h.substring(0, c).trim().toLowerCase(Locale.US);
            String v = h.substring(c + 1).trim();
            r.headers.put(k, v);
            if ("content-length".equals(k)) {
                try {
                    len = Integer.parseInt(v);
                } catch (Throwable ignored) {
                }
            }
        }

        if ("100-continue".equalsIgnoreCase(r.header("expect"))) {
            OutputStream o = s.getOutputStream();
            o.write("HTTP/1.1 100 Continue\r\n\r\n".getBytes(Store.UTF8));
            o.flush();
        }

        if (len > 0 && len < 32 * 1024 * 1024) {
            byte[] b = new byte[len];
            int off = 0;
            while (off < len) {
                int n = in.read(b, off, len - off);
                if (n < 0) break;
                off += n;
            }
            r.body = new String(b, 0, off, Store.UTF8);
            String ct = r.header("content-type");
            if (ct != null && ct.contains("json")) {
                try {
                    r.json = new JSONObject(r.body);
                } catch (Throwable ignored) {
                }
            } else if (r.body.startsWith("{")) {
                try {
                    r.json = new JSONObject(r.body);
                } catch (Throwable ignored) {
                }
            }
        }

        try {
            r.remote = s.getInetAddress() == null ? "" : s.getInetAddress().getHostAddress();
        } catch (Throwable ignored) {
        }
        return r;
    }

    /** 把 //api/xx 这种（等长替换产生的多余斜杠）归一化 */
    public static String normalizePath(String p) {
        if (p == null || p.isEmpty()) return "/";
        String out = p;
        while (out.contains("//")) {
            out = out.replace("//", "/");
        }
        if (!out.startsWith("/")) out = "/" + out;
        if (out.length() > 1 && out.endsWith("/")) {
            // 保留一个尾斜杠形式，路由里两种都注册
        }
        return out;
    }

    private void writeRes(OutputStream out, Req req, Res res, boolean close) throws IOException {
        StringBuilder sb = new StringBuilder();
        sb.append("HTTP/1.1 ").append(res.code).append(' ').append(reason(res.code)).append("\r\n");
        sb.append("Content-Type: ").append(res.type).append("\r\n");
        sb.append("Content-Length: ").append(res.body.length).append("\r\n");
        sb.append("Access-Control-Allow-Origin: *\r\n");
        sb.append("Access-Control-Allow-Headers: *\r\n");
        sb.append("Access-Control-Allow-Methods: GET,POST,PUT,DELETE,OPTIONS,PATCH\r\n");
        sb.append("Access-Control-Max-Age: 86400\r\n");
        sb.append("Cache-Control: no-store\r\n");
        for (Map.Entry<String, String> e : res.headers.entrySet()) {
            sb.append(e.getKey()).append(": ").append(e.getValue()).append("\r\n");
        }
        // 保留一部分客户端头，Dart 端可能读
        sb.append("X-Local-Server: yiqikan-embedded/1.0\r\n");
        sb.append("Connection: ").append(close ? "close" : "keep-alive").append("\r\n");
        sb.append("\r\n");
        out.write(sb.toString().getBytes(Store.UTF8));
        if (res.body.length > 0 && !"HEAD".equals(req.method)) {
            out.write(res.body);
        }
        out.flush();
    }

    private static String reason(int code) {
        switch (code) {
            case 200:
                return "OK";
            case 201:
                return "Created";
            case 204:
                return "No Content";
            case 400:
                return "Bad Request";
            case 401:
                return "Unauthorized";
            case 403:
                return "Forbidden";
            case 404:
                return "Not Found";
            case 405:
                return "Method Not Allowed";
            case 500:
                return "Internal Server Error";
            default:
                return "OK";
        }
    }

    private static String readLine(InputStream in) throws IOException {
        ByteArrayOutputStream b = new ByteArrayOutputStream();
        int c;
        int last = -1;
        while ((c = in.read()) >= 0) {
            if (c == '\n') {
                if (last == '\r') {
                    byte[] a = b.toByteArray();
                    return new String(a, 0, Math.max(0, a.length - 1), Store.UTF8);
                }
                return new String(b.toByteArray(), Store.UTF8);
            }
            b.write(c);
            last = c;
            if (b.size() > 65536) break;
        }
        return null;
    }

    // ================================================================ WebSocket

    /** 一条 WS 连接 */
    public static final class Ws {
        public final Socket socket;
        public final OutputStream out;
        public String token = "";
        public String room = "";
        public String user = "";
        /** 房间内成员身份（≠ user_id：同一个人可以多端进同一房，每端一个 memberId） */
        public String memberId = "";
        public String memberName = "";
        public String memberToken = "";
        public volatile boolean open = true;

        /** C2：未批准的连接不进广播集合（state/progress/chat 都收不到） */
        public volatile boolean approved = false;

        /** 禁言真相在 members[].muted，这里只做连接级镜像：说话类帧进来先看它 */
        public volatile boolean muted = false;

        Ws(Socket s, OutputStream o) {
            this.socket = s;
            this.out = o;
        }

        public synchronized void sendText(String s) {
            if (!open) {
                // 静默丢帧是最难查的一段：这里必须留痕，否则客户端只表现为
                // 「某类帧突然收不到」，服务端一个字都没有。
                Log.w(TAG, "sendText skip member=" + memberId + " len=" + s.length()
                        + " reason=closed");
                return;
            }
            try {
                writeFrame(out, 0x1, s.getBytes(Store.UTF8));
            } catch (Throwable t) {
                Log.w(TAG, "sendText failed member=" + memberId + " len=" + s.length()
                        + " err=" + t);
                open = false;
            }
        }

        /**
         * 带关闭码关闭（11 号 §1.4）。实现口径：4001 鉴权失败 / 4002 房主关房 /
         * 4003 越权（含串房、审批被拒）/ 4004 口令错 / 4005 已被踢 / 4006 重复连接 /
         * 4007 服务端内部错 / 4009 帧过大。
         */
        public synchronized void close(int code, String reason) {
            if (!open) return;
            open = false;
            try {
                byte[] r = reason == null ? new byte[0] : reason.getBytes(Store.UTF8);
                byte[] p = new byte[2 + r.length];
                p[0] = (byte) ((code >>> 8) & 0xFF);
                p[1] = (byte) (code & 0xFF);
                if (r.length > 0) System.arraycopy(r, 0, p, 2, r.length);
                writeFrame(out, 0x8, p);
            } catch (Throwable ignored) {
            }
            try {
                socket.close();
            } catch (Throwable ignored) {
            }
        }

        public synchronized void close() {
            if (!open) return;
            open = false;
            try {
                writeFrame(out, 0x8, new byte[0]);
            } catch (Throwable ignored) {
            }
            try {
                socket.close();
            } catch (Throwable ignored) {
            }
        }
    }

    private void wsUpgrade(Socket s, InputStream in, OutputStream out, Req req) throws IOException {
        String key = req.header("sec-websocket-key");
        if (key == null) {
            writeRes(out, req, Res.status(400, "missing Sec-WebSocket-Key"), false);
            s.close();
            return;
        }
        // ── P0-2 鉴权必须在 101 之前完成：没房间号 / token 不对直接 HTTP 拒绝
        final Store st = Store.get(ctx);
        final String room = req.q("room", req.q("room_code", ""));
        final String token = req.q("token", req.q("access_token", ""));
        if (room.isEmpty()) {
            writeRes(out, req, Res.status(400, "missing room"), false);
            s.close();
            return;
        }
        final String expect = st.roomTokenFor(room);
        // 房间 token 是给「只知道房间码的人」设的门槛；客人是经 /join 拿到 memberToken 进来的，
        // 这时允许 token 为空、用 memberToken 证明身份（否则客人永远 401）。
        final boolean memberProof = token.isEmpty() && !req.q("member_token", "").isEmpty();
        if (!memberProof && (expect.isEmpty() || !expect.equals(token))) {
            Log.w(TAG, "ws reject bad token room=" + room);
            writeRes(out, req, Res.status(401, "bad token"), false);
            s.close();
            return;
        }
        final JSONObject roomObj = st.findRoom(room);
        if (roomObj == null) {
            writeRes(out, req, Res.status(404, "room not found"), false);
            s.close();
            return;
        }

        String accept = wsAccept(key);
        // 握手阶段的拒绝必须先于 101 发出：一旦回 101，协议已经切换，
        // 只能靠 close code 表达，而 Dart 侧拿到的是 1006（保留码，无原因），
        // 用户看到的就只是一句"连不上"。所以这里先判，再用 403 + body 说清原因。
        String resume = req.q("member_token", "");
        JSONObject resumeMember = null;
        if (!resume.isEmpty()) {
            resumeMember = st.memberByToken(roomObj, resume);
            if (resumeMember != null && resumeMember.optBoolean("kicked", false)) {
                Log.w(TAG, "ws reject kicked member=" + resumeMember.optString("id"));
                JSONObject kb = new JSONObject();
                try {
                    kb.put("ok", false);
                    kb.put("error", "kicked");
                    kb.put("close_code", 4005);
                } catch (Throwable ignored) {
                }
                writeRes(out, req, Res.json(403, kb.toString()), false);
                s.close();
                return;
            }
        }
        JSONObject freshMember = null;
        if (resumeMember == null) {
            // C4：容量只算「已批准 且 未踢出」的人；pending 不占名额。
            // 老成员带 member_token 重连走上一条分支，不受这里影响（否则满员时自己都回不来）。
            int live = Store.liveMembers(roomObj);
            int cap = Store.maxMembers(roomObj);
            if (live >= cap) {
                Log.w(TAG, "ws reject room_full room=" + room + " live=" + live + " cap=" + cap);
                JSONObject fb = new JSONObject();
                try {
                    fb.put("ok", false);
                    fb.put("error", "room_full");
                    fb.put("close_code", 4004);
                } catch (Throwable ignored) {
                }
                writeRes(out, req, Res.json(403, fb.toString()), false);
                s.close();
                return;
            }
            freshMember = st.addMember(roomObj, req.q("name", "guest"), false,
                    "1".equals(req.q("bot", "")) || "true".equalsIgnoreCase(req.q("bot", "")));
        }

        StringBuilder sb = new StringBuilder();
        sb.append("HTTP/1.1 101 Switching Protocols\r\n");
        sb.append("Upgrade: websocket\r\n");
        sb.append("Connection: Upgrade\r\n");
        sb.append("Sec-WebSocket-Accept: ").append(accept).append("\r\n");
        sb.append("\r\n");
        out.write(sb.toString().getBytes(Store.UTF8));
        out.flush();

        final Ws ws = new Ws(s, out);
        ws.token = token;
        ws.room = room;

        if (resumeMember != null) {
            ws.memberId = resumeMember.optString("id", "");
            ws.approved = resumeMember.optBoolean("approved", true);
            ws.muted = resumeMember.optBoolean("muted", false);
            ws.memberToken = resume;
        } else {
            ws.memberId = freshMember.optString("id", "");
            ws.approved = freshMember.optBoolean("approved", true);
            ws.muted = freshMember.optBoolean("muted", false);
            ws.memberToken = freshMember.optString("token", "");
        }
        // 同一 memberId 只允许一条连接：新连接踢旧连接（4006 重复连接）。
        //
        // 为什么选「踢旧」而不是「允许多条」：memberId 是投递与去重的唯一身份，
        // 两条同 id 连接同时在册时，relay 的 `t == from` 只能跳过对象本身，
        // 另一条会被当成「别人」照样收到帧；反过来关闭时也分不清该留哪条。
        // 实测踩过：用房主 token 连了第二条之后，App 那条从此收不到 danmaku，
        // 而 members（broadcastRoom 路径）照收，表现为「某一类帧突然没了」。
        if (ws.memberId != null && !ws.memberId.isEmpty()) {
            List<Ws> dupes = new ArrayList<Ws>(wsList);
            for (Ws old : dupes) {
                if (old == ws) continue;
                if (!old.open) continue;
                if (!room.equals(old.room)) continue;
                if (!ws.memberId.equals(old.memberId)) continue;
                Log.i(TAG, "ws dup member=" + ws.memberId + " room=" + room + " -> close old 4006");
                old.close(4006, "duplicate");
            }
        }
        wsList.add(ws);
        Log.i(TAG, "ws open room=" + room + " member=" + ws.memberId + " resume=" + (!resume.isEmpty()));

        JSONObject hello = new JSONObject();
        try {
            hello.put("type", "connected");
            hello.put("service", "yiqikan-local");
            hello.put("room", ws.room);
            hello.put("memberId", ws.memberId);
            hello.put("memberToken", ws.memberToken);
            hello.put("online", wsList.size());
        } catch (Throwable ignored) {
        }
        ws.sendText(hello.toString());

        s.setSoTimeout(0);
        java.io.ByteArrayOutputStream frag = null;
        int fragOpcode = 0;
        try {
            while (ws.open) {
                Frame f = readFrame(in);
                if (f == null) break;
                if (f.opcode == 0x8) {
                    int ccode = 1000;
                    if (f.payload != null && f.payload.length >= 2) {
                        ccode = ((f.payload[0] & 0xFF) << 8) | (f.payload[1] & 0xFF);
                    }
                    ws.close(ccode, "bye");
                    break;
                }
                if (f.opcode == 0x9) {
                    synchronized (ws) {
                        writeFrame(out, 0xA, f.payload);
                    }
                    continue;
                }
                if (f.opcode == 0xA) continue;
                if (f.opcode == 0x0) {
                    if (frag == null) {
                        ws.close(4009, "bad continuation");
                        break;
                    }
                    // 整条消息上限：先算总量再写，避免先分配再判
                    if ((long) frag.size() + f.payload.length > MAX_MESSAGE) {
                        frag = null;
                        fragOpcode = 0;
                        ws.close(4007, "message too large");
                        break;
                    }
                    frag.write(f.payload);
                    if (f.fin) {
                        byte[] all = frag.toByteArray();
                        int op = fragOpcode;
                        frag = null;
                        fragOpcode = 0;
                        dispatch(ws, op, all);
                    }
                    continue;
                }
                if (f.opcode == 0x1 || f.opcode == 0x2) {
                    if (!f.fin) {
                        frag = new java.io.ByteArrayOutputStream();
                        frag.write(f.payload);
                        fragOpcode = f.opcode;
                        continue;
                    }
                    dispatch(ws, f.opcode, f.payload);
                }
            }
        } catch (Throwable ignored) {
        } finally {
            wsList.remove(ws);
            try {
                // 人走了，他的进度也不留（否则快照里挂着一个不在线的旧位置）
                if (ws.room != null && !ws.room.isEmpty() && ws.memberId != null) {
                    Store.get(ctx).dropProgress(ws.room, ws.memberId);
                    // 发起者断开：把他人还没被处理的 claim 全部取消（否则 3 秒后还会广播 timeout）
                    try {
                        for (String rid : new ArrayList<String>(PENDING.keySet())) {
                            JSONObject pp = PENDING.get(rid);
                            if (pp == null) continue;
                            if (!ws.memberId.equals(pp.optString("from", ""))) continue;
                            PENDING.remove(rid);
                            java.util.Timer tm = PENDING_TIMERS.remove(rid);
                            if (tm != null) tm.cancel();
                            Log.i(TAG, "[YQK-WS] claim cancelled rid=" + rid + " (requester left)");
                        }
                        // D14：这个人的限流时间戳也一起清（否则重连后 300ms 窗口内会被旧记录误吞）
                        final String cPrefix = ws.memberId + ":";
                        CLAIM_AT.keySet().removeIf(k -> k.startsWith(cPrefix));
                    } catch (Throwable ignored) {
                    }
                }
            } catch (Throwable ignored) {
            }
            ws.close();
            // 走的人也要广播一次 members（可能是个未批准的断开，广播出去别人
            // 只会看到成员数没变，代价是一条帧）。集合按当前 wsList 重算：
            // 这条连接已经从 wsList 移除了，重算出来的就是「走后」的在线集合。
            if (ws.room != null && !ws.room.isEmpty()) {
                java.util.Set<String> onlineLeft = new java.util.HashSet<String>();
                for (Ws w : new ArrayList<Ws>(wsList)) {
                    if (w.open && ws.room.equals(w.room) && w.memberId != null) {
                        onlineLeft.add(w.memberId);
                    }
                }
                broadcastMembers(ws.room, onlineLeft);
                // 语音也要摘掉：进程被 kill / 被踢 / 断网都走这里，不能指望客户端发 leave。
                // voiceRemove 内部只在真的摘掉了成员时才广播，未入语音的人断开不产生噪声。
                voiceRemove(ws.room, ws.memberId);
                // D21：房间真的空了才丢弹幕历史（有人还在就保留，否则重连/换人进来就没回放）。
                if (onlineLeft.isEmpty()) {
                    DANMAKU_HIST.remove(ws.room);
                    // H11：房间空了就把回放录制一起丢掉（只活内存，不落盘）
                    REC.remove(ws.room);
                    REC_T0.remove(ws.room);
                    Log.i(TAG, "[YQK-WS] replay drop room=" + ws.room + "（房间已空）");
                    Log.i(TAG, "[YQK-WS] dm-hist drop room=" + ws.room + "（房间已空）");
                    // E3 / A1：本房间没人了。若别的房间也没人在线，隧道就没有存在的意义
                    // （cloudflared 是本地子进程，白养着只会多一条公网入口）。
                    boolean otherRoomAlive = false;
                    for (Ws w2 : new ArrayList<Ws>(wsList)) {
                        if (w2.open && w2.room != null && !w2.room.isEmpty()
                                && !ws.room.equals(w2.room) && w2.memberId != null) {
                            otherRoomAlive = true;
                            break;
                        }
                    }
                    if (!otherRoomAlive) {
                        String reason = "leave";
                        try {
                            JSONObject rmLeft = Store.get(ctx).findRoom(ws.room);
                            String hostId = rmLeft == null ? "" : Store.hostIdOf(rmLeft);
                            // 房主自己走 = 关房（客户端会直接回首页），房客走 = 退房
                            if (ws.memberId != null && !hostId.isEmpty()
                                    && hostId.equals(ws.memberId)) {
                                reason = "close";
                            }
                        } catch (Throwable ignored) {
                        }
                        Log.i(TAG, "[YQK-TUN] auto stop room=" + ws.room + " reason=" + reason);
                        try {
                            TunnelManager.get(ctx).stop();
                        } catch (Throwable t) {
                            Log.w(TAG, "[YQK-TUN] auto stop fail " + t);
                        }
                    }
                }
            }
            Log.i(TAG, "ws closed, remaining=" + wsList.size());
        }
    }

    /** 单帧上限（11 号 §1.3 规定 1MB，原来写的是 8MB） */
    static final int MAX_FRAME = 1024 * 1024;
    /** 整条消息上限（分片累积后）：防止「无限 FIN=0 续帧」把内存打满 */
    static final int MAX_MESSAGE = 4 * 1024 * 1024;

    /**
     * 强序帧（11 号 §4.2）：服务端统一编号，客户端按 seq 单调去重 + 检测跳号。
     *
     * 分两类是为了让「重连后不重放」有依据：只有业务事件需要严格顺序，
     * 而 progress/status 这类高频覆盖式帧带 seq 反而会淹没判据。
     */
    static final java.util.Set<String> SEQ_FRAMES = new java.util.HashSet<String>(java.util.Arrays.asList(
            "joined", "kicked", "muted", "members", "state", "sync", "control", "claim", "web",
            "select", "next", "ended", "rate", "quality", "settings", "setHost", "setMuted",
            "claim-result",
            "setNotice", "notice", "chat", "chat-recall", "danmaku", "danmaku-like",
            "danmaku-likes", "reaction", "media", "media-add", "vote", "vote-cast",
            "vote-result", "summon", "teleport", "screen", "voice", "voice-error",
            "voice-full", "voice-state", "ice", "offer", "sdp", "room-closed", "error"));

    /**
     * 语音成员表（M8 7a，2026-11-08）：只在内存里，进程重启就清空 —— 这是硬要求，
     * 语音状态不进 rooms.json，否则重启后「幽灵成员」会永远挂在成员条上。
     * key = 房间码，value = 已加入语音的 memberId（LinkedHashSet 保序，UI 按加入顺序排）。
     */
    static final java.util.Map<String, java.util.LinkedHashSet<String>> VOICE =
            new java.util.concurrent.ConcurrentHashMap<String, java.util.LinkedHashSet<String>>();
    /** 语音静音：房间码 → 被静音的 memberId。同样只在内存。 */
    static final java.util.Map<String, java.util.LinkedHashSet<String>> VOICE_MUTED =
            new java.util.concurrent.ConcurrentHashMap<String, java.util.LinkedHashSet<String>>();
    /** 语音上限。客户端 kVoiceMax 与它对齐，改了要两边一起改。 */
    static final int VOICE_MAX = 4;

    /**
     * D21「房间回放」：每个房间最近 N 条 danmaku 原始帧（JSON 字符串）。
     * 只在内存里 —— 不进 rooms.json、不做磁盘持久化，进程重启就清空，这是设计。
     * key = 房间码；房间没人时整键移除（见 onClose 的 onlineLeft 判空）。
     */
    static final int DANMAKU_HIST_MAX = 300;
    static final java.util.Map<String, java.util.Deque<String>> DANMAKU_HIST =
            new java.util.concurrent.ConcurrentHashMap<String, java.util.Deque<String>>();

    /**
     * H11 房间回放录制。只活在内存：房间空了整键移除，进程重启就没了。
     * key = 房间码；value = 按到达顺序的帧（已补 seq，含 t=房间相对秒）。
     */
    static final int REC_MAX = 2000;
    static final java.util.Set<String> REC_TYPES = new java.util.HashSet<String>(
            java.util.Arrays.asList("chat", "danmaku", "state", "control", "claim", "kick",
                    "muted", "transfer", "media"));
    static final java.util.Map<String, java.util.Deque<JSONObject>> REC =
            new java.util.concurrent.ConcurrentHashMap<String, java.util.Deque<JSONObject>>();
    /** key = 房间码，value = 第一条录制帧的墙钟（算相对时间 t 用） */
    static final java.util.Map<String, Long> REC_T0 =
            new java.util.concurrent.ConcurrentHashMap<String, Long>();

    /** 收一条回放帧（H11）。调用点：relay 转发之后。 */
    static void recordFrame(String room, String type, JSONObject frame) {
        if (room == null || room.isEmpty() || type == null) return;
        if (!REC_TYPES.contains(type)) return;
        try {
            long now = System.currentTimeMillis();
            Long t0 = REC_T0.putIfAbsent(room, now);
            java.util.Deque<JSONObject> dq = REC.get(room);
            if (dq == null) {
                dq = new java.util.ArrayDeque<JSONObject>();
                java.util.Deque<JSONObject> prev = REC.putIfAbsent(room, dq);
                if (prev != null) dq = prev;
            }
            JSONObject row = new JSONObject(frame.toString());
            row.put("t", (now - (t0 == null ? now : t0)) / 1000.0);
            synchronized (dq) {
                dq.addLast(row);
                while (dq.size() > REC_MAX) dq.removeFirst();
                Log.i(TAG, "[YQK-REC] add room=" + room + " type=" + type
                        + " n=" + dq.size() + " t=" + row.optDouble("t", 0));
            }
        } catch (Throwable ignored) {
        }
    }

    /** 房主权威模式下的控制请求：rid → {room, from, fromName, action, position, rate, timer} */
    static final java.util.Map<String, JSONObject> PENDING =
            new java.util.concurrent.ConcurrentHashMap<String, JSONObject>();
    /** rid → java.util.Timer，便于成员断开时取消 */
    static final java.util.Map<String, java.util.Timer> PENDING_TIMERS =
            new java.util.concurrent.ConcurrentHashMap<String, java.util.Timer>();
    /** D14：同一成员同一动作 300ms 内只受理一次。key = memberId + ":" + action */
    private static final java.util.concurrent.ConcurrentHashMap<String, Long> CLAIM_AT
            = new java.util.concurrent.ConcurrentHashMap<>();

    /** P1：文本→onWsText；二进制保 byte[] 直传（这轮只记日志，不当字符串解析） */
    private void dispatch(Ws ws, int opcode, byte[] payload) {
        if (opcode == 0x2) {
            Log.i(TAG, "ws binary from=" + ws.memberId + " bytes=" + payload.length + " (ignored)");
            return;
        }
        onWsText(ws, new String(payload, Store.UTF8));
    }

    /** 透传式房间广播：不解析业务协议，只按 room 分组转发 */
    private void onWsText(Ws from, String text) {
        final String room = from.room;
        final String origText = text;
        String type = "";
        int seqInFrame = -1;
        // D27：o 是 try 块里的局部变量，出了 try 就没了；转发之后还要判 Bot 别名，所以先把 chat 正文存到方法作用域。
        String botChatText = "";
        try {
            JSONObject o = new JSONObject(text);
            type = o.optString("type", "");
            if ("chat".equals(type)) botChatText = o.optString("text", "");
            // P0-1：房间号只在握手时定死。帧里带 room / room_code 且与连接不一致 → 拒绝并断开
            String claimed = o.optString("room", o.optString("room_code", ""));
            if (!claimed.isEmpty() && !claimed.equals(room)) {
                Log.w(TAG, "[YQK-WS] reject room-override from memberId=" + from.memberId
                        + " claimed=" + claimed + " actual=" + room);
                from.close(4003, "room override");
                return;
            }
            if ("ping".equals(type) || "heartbeat".equals(type)) {
                JSONObject p = new JSONObject();
                p.put("type", "pong");
                p.put("t", System.currentTimeMillis());
                from.sendText(p.toString());
                return;
            }
            if ("sync".equals(type) || "playback".equals(type) || "progress".equals(type)) {
                // memberId 一律服务端填（from.memberId），不信客户端传的 by（m09136）
                Api.applyPlayback(ctx, room, o, from.memberId);
                Log.i(TAG, "[YQK-WS] playback-in type=" + type + " memberId=" + from.memberId
                        + " position=" + o.optDouble("position", o.optDouble("progress", 0)));
                // 已经由 applyPlayback 广播过 state/progress，不要再把原始帧转发一遍
                return;
            }
            // hello：回一份服务端当前真实快照（11 号 §4.1），客户端不自己拼状态
            if ("hello".equals(type)) {
                int lastSeq = o.optInt("lastSeq", 0);
                from.memberName = o.optString("name", "");
                Store.get(ctx).renameMember(room, from.memberId, o.optString("name", ""));
                // I-81：hello 拿到真名之后再清幽灵成员。同名的那条如果此刻没有活连接，
                // 就是同一台设备上一次进房（force-stop 后重进）留下的记录 —— 不摘掉，
                // 成员条会一直多一个人（members=3 / online=2）。liveIds 里已有自己，不误删。
                java.util.Set<String> liveIds = new java.util.HashSet<String>();
                for (Ws each : wsList) {
                    if (each.memberId != null && !each.memberId.isEmpty()) liveIds.add(each.memberId);
                }
                int ghost = Store.get(ctx).dropOfflineGuestsNamed(
                        Store.get(ctx).rooms.get(room), o.optString("name", ""), liveIds);
                if (ghost > 0) {
                    Log.i(TAG, "[YQK-WS] drop ghost members=" + ghost + " room=" + room
                            + " name=" + o.optString("name", ""));
                    Store.get(ctx).save();
                }
                Log.i(TAG, "[YQK-WS] hello memberId=" + from.memberId + " lastSeq=" + lastSeq);
                if (lastSeq > 1) {
                    Log.i(TAG, "[YQK-WS] resume from seq=" + lastSeq + " room=" + room);
                }
                if (!from.approved) {
                    JSONObject pend = new JSONObject();
                    JSONObject mm2 = new JSONObject();
                    try {
                        pend.put("type", "pending");
                        pend.put("room", room);
                        mm2.put("id", from.memberId);
                        mm2.put("name", from.memberName == null ? "" : from.memberName);
                        pend.put("member", mm2);
                    } catch (Throwable ignored) {
                    }
                    from.sendText(pend.toString());
                    JSONObject toHost = new JSONObject();
                    try {
                        toHost.put("type", "pending");
                        toHost.put("room", room);
                        toHost.put("member", mm2);
                    } catch (Throwable ignored) {
                    }
                    sendToMember(room, Store.hostIdOf(Store.get(ctx).rooms.get(room)), toHost.toString());
                    final String waiting = from.memberId;
                    new java.util.Timer().schedule(new java.util.TimerTask() {
                        public void run() {
                            try {
                                Store st2 = Store.get(ctx);
                                JSONObject mb = st2.memberById(room, waiting);
                                if (mb == null || mb.optBoolean("approved", false)) return;
                                st2.markKicked(st2.rooms.get(room), waiting);
                                Log.w(TAG, "[YQK-WS] approval timeout memberId=" + waiting);
                                for (Ws w : new ArrayList<Ws>(wsList)) {
                                    if (w.open && room.equals(w.room) && waiting.equals(w.memberId)) {
                                        try { w.socket.close(); } catch (Throwable ignored) {}
                                        w.open = false;
                                    }
                                }
                            } catch (Throwable ignored) {
                            }
                        }
                    }, 30000L);
                    return;
                }
                java.util.Set<String> online = new java.util.HashSet<String>();
                for (Ws w : new ArrayList<Ws>(wsList)) {
                    if (w.open && room.equals(w.room) && w.memberId != null) online.add(w.memberId);
                }
                // D27：占位的 Bot 不算离线，否则客户端成员条会把它标灰
                BotCfg hiBot = BOTS.get(room);
                if (hiBot != null && hiBot.occupySlot && !hiBot.memberId.isEmpty()) {
                    online.add(hiBot.memberId);
                }
                JSONObject hi = new JSONObject();
                try {
                    hi.put("type", "hello");
                    hi.put("memberId", from.memberId);
                    hi.put("memberToken", from.memberToken);
                    hi.put("resumeFrom", lastSeq);
                    hi.put("online", online.size());
                    JSONObject snap = Store.get(ctx).roomSnapshot(room, online);
                    if (snap != null) hi.put("room", snap);
                    // D21 房间回放：把最近 N 条 danmaku 原样带给新入房的人。
                    // 没有历史就给空数组，绝不给 null（客户端按数组遍历）。
                    org.json.JSONArray dhist = new org.json.JSONArray();
                    java.util.Deque<String> dq = DANMAKU_HIST.get(room);
                    if (dq != null) {
                        synchronized (dq) {
                            for (String one : dq) {
                                try {
                                    dhist.put(new JSONObject(one));
                                } catch (Throwable ignored) {
                                }
                            }
                        }
                    }
                    hi.put("danmakus", dhist);
                    Log.i(TAG, "[YQK-WS] hello danmakus room=" + room
                            + " n=" + dhist.length() + " to=" + from.memberId);
                } catch (Throwable ignored) {
                }
                from.sendText(hi.toString());
                // 后进房的人也得知道「谁已经在语音里」，否则麦克风要等下一次 join/leave 才出现。
                // 单播、不带 seq：全房 seq 是给广播帧用的，别为一次快照让所有人在账本上跳号。
                JSONObject vs = buildVoiceStateFrame(room, false);
                if (vs != null) {
                    from.sendText(vs.toString());
                    JSONArray vits = vs.optJSONArray("items");
                    Log.i(TAG, "[YQK-VOICE] snapshot room=" + room + " to=" + from.memberId
                            + " n=" + (vits == null ? 0 : vits.length()));
                }
                // 成员进出要让房里所有人都知道：房主的「N 人在看」靠这条刷新，
                // 不能等他做别的动作才被动更新（2026-11-08 修）。
                if (from.approved) broadcastMembers(room, online);
                return;
            }
            // 禁言：只有房主能改别人的 muted（强序帧，seq 由下面 SEQ_FRAMES 统一补）
            if ("setMuted".equals(type)) {
                Store st = Store.get(ctx);
                JSONObject rm = st.rooms.get(room);
                String target = o.optString("memberId", "");
                boolean muted = o.optBoolean("muted", true);
                // 拒绝对端要能按 code 分辨原因（客户端 setMuted() 等的是 error 帧里的 code），
                // 所以这里统一走 errObj：不是房主 → not_host，跟 setHost 一侧同码。
                String mrid = o.optString("rid", "");
                String errCode = null;
                String errMsg = null;
                if (rm == null) {
                    errCode = "room_not_found";
                    errMsg = "房间不存在";
                } else if (!from.memberId.equals(Store.hostIdOf(rm))) {
                    errCode = "not_host";
                    errMsg = "只有房主能禁言";
                } else if (target.isEmpty()) {
                    errCode = "bad_request";
                    errMsg = "memberId 不能为空";
                }
                if (errCode != null) {
                    from.sendText(errObj(errCode, mrid, errMsg).toString());
                    Log.w(TAG, "[YQK-WS] setMuted rejected by=" + from.memberId + " target=" + target + " reason=" + errCode);
                    return;
                }
                Store.setMuted(rm, target, muted);
                // 连接级镜像同步（和 C3 的 approved 一样：不然它要重连才生效）
                for (Ws w : new ArrayList<Ws>(wsList)) {
                    if (w.open && room.equals(w.room) && target.equals(w.memberId)) {
                        w.muted = muted;
                    }
                }
                // 出站统一叫 muted（11 号 §4 的帧名），入站仍收 setMuted
                o.put("type", "muted");
                o.put("muted", muted);
                o.put("by", from.memberId);
                type = "muted";
                int mseq = st.nextRoomSeq(room);
                if (mseq > 0) o.put("seq", mseq);
                text = o.toString();
                Log.i(TAG, "[YQK-WS] setMuted by=" + from.memberId + " target=" + target + " muted=" + muted + " seq=" + mseq);
                // 再广播一份 members：全房间都能看到禁言状态变了（成员条角标靠它）
                java.util.Set<String> monline = new java.util.HashSet<String>();
                for (Ws w : new ArrayList<Ws>(wsList)) {
                    if (w.open && room.equals(w.room) && w.memberId != null) monline.add(w.memberId);
                }
                // D27：占位的 Bot 不算离线，否则成员条会把它标灰
                BotCfg mBot = BOTS.get(room);
                if (mBot != null && mBot.occupySlot && !mBot.memberId.isEmpty()) {
                    monline.add(mBot.memberId);
                }
                JSONObject msnap = st.roomSnapshot(room, monline);
                if (msnap != null) {
                    JSONObject mout = new JSONObject();
                    mout.put("type", "members");
                    mout.put("room", room);
                    JSONArray mm = msnap.optJSONArray("members");
                    mout.put("members", mm == null ? new JSONArray() : mm);
                    int ms2 = st.nextRoomSeq(room);
                    if (ms2 > 0) mout.put("seq", ms2);
                    broadcastRoom(room, mout.toString());
                }
            }
            // 移交房主：只有房主能发；改 role + room.host/room.host_id，然后广播 members
            if ("setHost".equals(type)) {
                Store st = Store.get(ctx);
                JSONObject rm = st.rooms.get(room);
                String rid = o.optString("rid", "");
                String target = o.optString("memberId", o.optString("id", ""));
                if (rm == null) {
                    from.sendText(errObj("room_not_found", rid, "房间不存在").toString());
                    return;
                }
                if (!from.memberId.equals(Store.hostIdOf(rm))) {
                    from.sendText(errObj("not_host", rid, "只有房主能移交").toString());
                    Log.w(TAG, "[YQK-WS] setHost rejected by=" + from.memberId + " reason=not_host");
                    return;
                }
                if (st.memberById(room, target) == null) {
                    from.sendText(errObj("member_not_found", rid, "成员不存在: " + target).toString());
                    Log.w(TAG, "[YQK-WS] setHost member_not_found target=" + target);
                    return;
                }
                st.setHost(room, target);
                Log.i(TAG, "[YQK-WS] setHost from=" + from.memberId + " to=" + target);
                java.util.Set<String> honline = new java.util.HashSet<String>();
                for (Ws w : new ArrayList<Ws>(wsList)) {
                    if (w.open && room.equals(w.room) && w.memberId != null) honline.add(w.memberId);
                }
                // D27：占位的 Bot 不算离线
                BotCfg hBot = BOTS.get(room);
                if (hBot != null && hBot.occupySlot && !hBot.memberId.isEmpty()) {
                    honline.add(hBot.memberId);
                }
                JSONObject hsnap = st.roomSnapshot(room, honline);
                JSONObject hout = new JSONObject();
                hout.put("type", "members");
                hout.put("room", room);
                hout.put("host", Store.hostIdOf(rm));
                JSONArray hmm = hsnap == null ? null : hsnap.optJSONArray("members");
                hout.put("members", hmm == null ? new JSONArray() : hmm);
                int hseq = st.nextRoomSeq(room);
                if (hseq > 0) hout.put("seq", hseq);
                broadcastRoom(room, hout.toString());
                return;
            }
            // C3：进房审批的 approve / reject（只有房主能发；错误帧带 type + rid）
            if ("approve".equals(type) || "reject".equals(type)) {
                Store st = Store.get(ctx);
                JSONObject rm = st.rooms.get(room);
                String rid = o.optString("rid", "");
                String target = o.optString("id", o.optString("memberId", ""));
                if (rm == null) {
                    from.sendText(errObj("room_not_found", rid, "房间不存在").toString());
                    return;
                }
                if (!from.memberId.equals(Store.hostIdOf(rm))) {
                    from.sendText(errObj("not_host", rid, "只有房主能审批").toString());
                    Log.w(TAG, "[YQK-WS] " + type + " rejected by=" + from.memberId
                            + " target=" + target + " reason=not_host");
                    return;
                }
                JSONObject mb = st.memberById(room, target);
                if (mb == null) {
                    from.sendText(errObj("member_not_found", rid, "成员不存在: " + target).toString());
                    Log.w(TAG, "[YQK-WS] " + type + " member_not_found target=" + target);
                    return;
                }
                if ("approve".equals(type)) {
                    st.setApproved(room, target, true);
                    // 连接上的 approved 也要同步，否则它要等重连才进广播集合
                    for (Ws w : new ArrayList<Ws>(wsList)) {
                        if (w.open && room.equals(w.room) && target.equals(w.memberId)) {
                            w.approved = true;
                        }
                    }
                    java.util.Set<String> online = new java.util.HashSet<String>();
                    for (Ws w : new ArrayList<Ws>(wsList)) {
                        if (w.open && room.equals(w.room) && w.memberId != null) online.add(w.memberId);
                    }
                    int aseq = st.nextRoomSeq(room);
                    JSONObject jf = new JSONObject();
                    jf.put("type", "joined");
                    jf.put("room", room);
                    JSONObject one = new JSONObject();
                    one.put("id", target);
                    one.put("name", mb.optString("name", mb.optString("nickname", "")));
                    one.put("role", "guest");
                    one.put("approved", true);
                    jf.put("member", one);
                    if (aseq > 0) jf.put("seq", aseq);
                    broadcastRoom(room, jf.toString());
                    // 补一次跟 hello 同样的快照，让它一进来就有当前播放位置
                    JSONObject hi = new JSONObject();
                    hi.put("type", "hello");
                    hi.put("memberId", target);
                    hi.put("memberToken", mb.optString("token", ""));
                    hi.put("resumeFrom", 0);
                    hi.put("online", online.size());
                    JSONObject snap = st.roomSnapshot(room, online);
                    if (snap != null) hi.put("room", snap);
                    sendToMember(room, target, hi.toString());
                    // 审批通过的那条 hello 也补一份语音成员快照（同样单播、不带 seq）
                    JSONObject vs2 = buildVoiceStateFrame(room, false);
                    if (vs2 != null) sendToMember(room, target, vs2.toString());
                    Log.i(TAG, "[YQK-WS] approve target=" + target + " by=" + from.memberId
                            + " seq=" + aseq + " online=" + online.size());
                } else {
                    st.markKicked(rm, target);
                    int rseq = st.nextRoomSeq(room);
                    for (Ws w : new ArrayList<Ws>(wsList)) {
                        if (w.open && room.equals(w.room) && target.equals(w.memberId)) {
                            w.close(4005, "rejected");
                            w.open = false;
                        }
                    }
                    java.util.Set<String> online = new java.util.HashSet<String>();
                    for (Ws w : new ArrayList<Ws>(wsList)) {
                        if (w.open && room.equals(w.room) && w.memberId != null) online.add(w.memberId);
                    }
                    JSONObject snap = st.roomSnapshot(room, online);
                    JSONObject out = new JSONObject();
                    out.put("type", "members");
                    out.put("room", room);
                    JSONArray mem = snap == null ? null : snap.optJSONArray("members");
                    out.put("members", mem == null ? new JSONArray() : mem);
                    if (rseq > 0) out.put("seq", rseq);
                    broadcastRoom(room, out.toString());
                    Log.i(TAG, "[YQK-WS] reject target=" + target + " by=" + from.memberId + " seq=" + rseq);
                }
                return;
            }
            // 切控制模式：只有房主能改；出站复用 settings 帧（不新造帧名）
            if ("settings".equals(type)) {
                Store st = Store.get(ctx);
                JSONObject rm = st.rooms.get(room);
                String want = o.optString("control_mode", "");
                if (rm == null) return;
                if (!from.memberId.equals(Store.hostIdOf(rm))) {
                    JSONObject e = new JSONObject();
                    e.put("type", "error");
                    e.put("code", 403);
                    e.put("error", "只有房主能改控制模式");
                    e.put("detail", "只有房主能改控制模式");
                    from.sendText(e.toString());
                    Log.w(TAG, "[YQK-WS] settings rejected by=" + from.memberId + " reason=not-host");
                    return;
                }
                if ("free".equals(want) || "host".equals(want)) {
                    rm.put("control_mode", want);
                    st.save();
                    JSONObject out = new JSONObject();
                    out.put("type", "settings");
                    out.put("room", room);
                    out.put("control_mode", want);
                    out.put("by", from.memberId);
                    int cseq = st.nextRoomSeq(room);
                    if (cseq > 0) out.put("seq", cseq);
                    broadcastRoom(room, out.toString());
                    Log.i(TAG, "[YQK-WS] control_mode=" + want + " by=" + from.memberId + " seq=" + cseq);
                }
                return;
            }

            // 非房主在房主权威模式下请求控制：pending → approve/reject/timeout(3s)
            if ("claim".equals(type)) {
                Store st = Store.get(ctx);
                JSONObject rm = st.rooms.get(room);
                if (rm == null) return;
                String hostId = Store.hostIdOf(rm);
                String action = o.optString("action", "play");
                // D14：同人同动作 300ms 内只受理一次（丢弃，不合并）。必须在读到 action 之后判，
                // key 里带动作名，否则「暂停 + 拖动」这种连招会互相吞。
                // 用 elapsedRealtime：currentTimeMillis 会被改表/自动校时拽着跳。
                final String cKey = from.memberId + ":" + action;
                final long cNow = android.os.SystemClock.elapsedRealtime();
                final Long cLast = CLAIM_AT.get(cKey);
                if (cLast != null && cNow - cLast < 300L) {
                    Log.i(TAG, "[YQK-WS] claim throttled from=" + from.memberId
                            + " action=" + action + " dt=" + (cNow - cLast) + "ms");
                    return;
                }
                CLAIM_AT.put(cKey, cNow);
                String rid = Store.randId(8);
                JSONObject pending = new JSONObject();
                Log.i(TAG, "[YQK-WS] claim in from=" + from.memberId + " action=" + action + " hasPos=" + o.has("position") + " hasRate=" + o.has("rate"));
                pending.put("rid", rid);
                pending.put("room", room);
                pending.put("from", from.memberId);
                pending.put("fromName", from.memberName == null ? "" : from.memberName);
                pending.put("action", action);
                // 缺失就是缺失：seek 到 0 秒合法，不能用默认值把它藏起来
                if (o.has("position")) pending.put("position", o.optDouble("position", 0));
                if (o.has("rate")) pending.put("rate", o.optDouble("rate", 1));

                PENDING.put(rid, pending);

                JSONObject toHost = new JSONObject();
                // 帧名仍叫 claim：pending/approve/reject 三个名字留给「进房审批」
                toHost.put("type", "claim");
                toHost.put("room", room);
                toHost.put("rid", rid);
                toHost.put("from", from.memberId);
                toHost.put("fromName", pending.optString("fromName", ""));
                toHost.put("action", action);
                if (pending.has("position")) toHost.put("position", pending.optDouble("position", 0));
                if (pending.has("rate")) toHost.put("rate", pending.optDouble("rate", 1));
                toHost.put("ttl", 8000);
                sendToMember(room, hostId, toHost.toString());

                Log.i(TAG, "[YQK-WS] claim from=" + from.memberId + " action=" + action + " rid=" + rid + " → pending to host");

                java.util.Timer t = new java.util.Timer();
                t.schedule(new java.util.TimerTask() {
                    @Override
                    public void run() {
                        JSONObject pp = PENDING.remove(rid);
                        PENDING_TIMERS.remove(rid);
                        if (pp == null) return;
                        JSONObject rej = new JSONObject();
                        try {
                            rej.put("type", "claim-result");
                            rej.put("room", room);
                            rej.put("rid", rid);
                            rej.put("ok", false);
                            rej.put("reason", "timeout");
                            sendToMember(room, pp.optString("from", ""), rej.toString());
                        } catch (Throwable ignored) {
                        }
                        Log.i(TAG, "[YQK-WS] claim timeout rid=" + rid);
                    }
                }, 8000L);
                PENDING_TIMERS.put(rid, t);
                return;
            }

            // 房主拒绝：房主直接发 claim-result{ok:false,reason:host}，这里转给发起者
            if ("claim-result".equals(type)) {
                String rid = o.optString("rid", o.optString("requestId", ""));
                JSONObject pp = PENDING.remove(rid);
                java.util.Timer t = PENDING_TIMERS.remove(rid);
                if (t != null) t.cancel();
                if (pp == null) return;
                Store st = Store.get(ctx);
                JSONObject rm = st.rooms.get(room);
                if (rm == null) return;
                if (!from.memberId.equals(Store.hostIdOf(rm))) return;
                JSONObject out = new JSONObject();
                out.put("type", "claim-result");
                out.put("room", room);
                out.put("rid", rid);
                out.put("ok", o.optBoolean("ok", false));
                if (!o.optBoolean("ok", false)) out.put("reason", o.optString("reason", "host"));
                sendToMember(room, pp.optString("from", ""), out.toString());
                Log.i(TAG, "[YQK-WS] claim-result rid=" + rid + " ok=false reason=" + o.optString("reason", "host"));
                return;
            }

            // 房主批准：发 control 带 rid（不另造 approve 帧）
            if ("control".equals(type) && o.has("rid")) {
                Store st = Store.get(ctx);
                JSONObject rm = st.rooms.get(room);
                if (rm == null) return;
                String rid = o.optString("rid", "");
                JSONObject pp = PENDING.remove(rid);
                java.util.Timer tm = PENDING_TIMERS.remove(rid);
                if (tm != null) tm.cancel();
                if (pp == null) return;
                if (!from.memberId.equals(Store.hostIdOf(rm))) return;
                JSONObject apply = new JSONObject();
                String action = pp.optString("action", "play");
                if ("rate".equals(action)) {
                    // 只改倍速：不带 position，否则所有人被拉到发起者的位置
                    if (!pp.has("rate")) {
                        Log.w(TAG, "[YQK-WS] claim reject rid=" + rid + " reason=missing rate");
                        sendToMember(room, pp.optString("from", ""), errObj("claim_missing_rate", rid, "claim 缺少 rate").toString());
                        return;
                    }
                    apply.put("speed", pp.optDouble("rate", 1));
                } else if ("seek".equals(action)) {
                    // seek 到 0 秒是合法操作：没带 position 必须拒绝，不许默认成 0
                    if (!pp.has("position")) {
                        Log.w(TAG, "[YQK-WS] claim reject rid=" + rid + " reason=missing position");
                        sendToMember(room, pp.optString("from", ""), errObj("claim_missing_position", rid, "claim 缺少 position").toString());
                        return;
                    }
                    apply.put("position", pp.optDouble("position", 0));
                    apply.put("playing", true);
                } else {
                    apply.put("playing", "play".equals(action));
                    // 不带 position/speed/rate：保住原位置与原倍速
                }
                Api.applyPlayback(ctx, room, apply, pp.optString("from", ""), true);
                JSONObject ok = new JSONObject();
                ok.put("type", "claim-result");
                ok.put("room", room);
                ok.put("rid", rid);
                ok.put("ok", true);
                sendToMember(room, pp.optString("from", ""), ok.toString());
                Log.i(TAG, "[YQK-WS] claim approved rid=" + rid + " from=" + pp.optString("from", ""));
                return;
            }

            // 禁言只拦「说话」三类：progress / claim / state 一律不拦（禁言的是嘴，不是眼睛）
            if (from.muted && ("chat".equals(type) || "danmaku".equals(type) || "reaction".equals(type))) {
                from.sendText(errObj("muted", o.optString("rid", ""), "你被禁言了").toString());
                Log.w(TAG, "[YQK-WS] drop " + type + " from=" + from.memberId + " reason=muted");
                return;
            }
            // 语音信令（M8 7a）：只维护成员表与状态，不建连接、不碰麦克风。
            // 放在转发段之前并 return，避免 voice 帧被下面原样 relay 出去。
            if ("voice".equals(type)) {
                handleVoice(from, o);
                return;
            }
            // D27：Bot 配置（只有房主能配）。放在转发段之前并 return，别让配置帧被 relay 出去。
            if ("bot-config".equals(type)) {
                handleBotConfig(from, o);
                return;
            }
            // I-44：移出成员（只有房主能踢）。同样放在转发段之前并 return ——
            // 以前没有这条分支，kick 被当成普通帧 relay 出去，谁也没被踢。
            if ("kick".equals(type)) {
                handleKick(from, o);
                return;
            }
            // I-47：web 帧只允许房主发。不 return —— 校验通过后继续走下面的 relay，
            // seq 由 SEQ_FRAMES 统一补。客户端能被绕过，所以门槛只能放在这里。
            if ("web".equals(type)) {
                String wroom = from.room == null ? "" : from.room;
                if (!isHostOf(wroom, from.memberId)) {
                    Log.i(TAG, "[YQK-WEB] reject not-host by=" + from.memberId
                            + " action=" + o.optString("action", ""));
                    return;
                }
                // by 由服务端盖章，客户端传什么都覆盖掉。
                // 这一行必须在 :1719「text 变了才重新序列化」之前把 text 也换掉，
                // 否则 o 改了但 text 还是旧串，by 会被原样转发丢掉。
                try {
                    o.put("by", from.memberId);
                } catch (Throwable ignored) {
                }
                text = o.toString();
            }
            // 点对点帧（7b 才会真的产生 SDP/ICE；本轮只保证路由通）：
            // 一律按 "to" 单发给目标，目标不在线就回发起者 peer-offline，绝不广播。
            if ("offer".equals(type) || "sdp".equals(type) || "ice".equals(type)) {
                String to = o.optString("to", "");
                // D20：屏幕共享帧（screen==true）不走语音，房间里有 PC 就能推；
                // 语音信令仍然要求在语音里。
                boolean screenFrame = o.optBoolean("screen", false);
                if (!screenFrame && !inVoice(room, from.memberId)) {
                    from.sendText(voiceErrorFrame("not-in-voice", to, "你不在语音里").toString());
                    Log.w(TAG, "[YQK-VOICE] drop " + type + " from=" + from.memberId + " reason=not-in-voice");
                    return;
                }
                if (!isMemberOnline(room, to)) {
                    from.sendText(voiceErrorFrame("peer-offline", to, "对方不在线").toString());
                    Log.w(TAG, "[YQK-WS] drop " + type + " to=" + to + " reason=peer-offline");
                    return;
                }
                o.put("from", from.memberId);
                sendToMember(room, to, o.toString());
                Log.i(TAG, "[YQK-WS] p2p type=" + type + " from=" + from.memberId + " to=" + to);
                return;
            }
            // E：chat / danmaku 的最小校验（转发前判，判完再转发）
            // 目的只有一个：别让一条脏数据把所有客户端的历史列表撑爆。
            if ("chat".equals(type) || "danmaku".equals(type)) {
                String txt = o.optString("text", "");
                int max = "chat".equals(type) ? 500 : 100;
                if (txt.length() > max) {
                    String rid0 = o.optString("rid", "");
                    from.sendText(errObj("text_too_long", rid0,
                            type + " text " + txt.length() + " > " + max).toString());
                    Log.w(TAG, "[YQK-WS] drop " + type + " from=" + from.memberId
                            + " len=" + txt.length() + " max=" + max);
                    return;
                }
                // 服务端补身份与时间（11 号 §7.6 / §8.1：客户端传的 from 不算数）
                o.put("from", from.memberId);
                if (o.optString("name", "").isEmpty() && from.memberName != null) {
                    o.put("name", from.memberName);
                }
                if (!o.has("at")) o.put("at", System.currentTimeMillis());
                if (o.optString("id", "").isEmpty()) {
                    o.put("id", ("chat".equals(type) ? "ch_" : "dm_") + Store.randId(8));
                }
                text = o.toString();
            }
            // reaction（11 号 §7.4）：id 就是发送者 memberId，客户端传的一律覆盖，
            // 否则客户端只能看到一个空 id 的表情，飘不出「谁发的」。
            if ("reaction".equals(type)) {
                o.put("from", from.memberId);
                o.put("id", from.memberId);
                if (o.optString("name", "").isEmpty() && from.memberName != null) {
                    o.put("name", from.memberName);
                }
                if (!o.has("at")) o.put("at", System.currentTimeMillis());
                text = o.toString();
            }
            // danmaku-like 必须指向一条具体弹幕，否则点赞计数没有落点
            if ("danmaku-like".equals(type) && o.optString("id", "").isEmpty()) {
                from.sendText(errObj("missing_danmaku_id", o.optString("rid", ""),
                        "danmaku-like 缺少 id").toString());
                return;
            }
            // 点赞累加 + 增量广播（M8 点赞，2026-11-08）：
            // 累加放 Store.bumpDanmakuLike（同一把锁里改 + 落盘），这里只负责广播；
            // 下面原有的转发逻辑一字不动 —— 别人仍要收到 danmaku-like 本身。
            if ("danmaku-like".equals(type)) {
                final String likeId = o.optString("id", "");
                int likeN = Store.get(ctx).bumpDanmakuLike(room, likeId);
                Log.i(TAG, "[YQK-WS] danmaku-like id=" + likeId + " n=" + likeN
                        + " by=" + from.memberId);
                if (likeN > 0) {
                    JSONObject inc = new JSONObject();
                    JSONObject items = new JSONObject();
                    try {
                        items.put(likeId, likeN);
                        inc.put("type", "danmaku-likes");
                        inc.put("room", room);
                        inc.put("items", items);
                    } catch (Throwable ignored) {
                    }
                    // 只带这一条，不广播全表：全表在重进房的 hello 快照里
                    broadcastRoom(room, inc.toString());
                }
            }

            // I-55：state 只有房主能发。任何成员一帧 state{pos=100.5} 就能把全房拖走，
            // 所以门槛放在服务端；客户端判断绕得过，不算数。
            // 必须在这里 return —— 在下面拼 seq 之前丢，避免白跳一个号。
            if ("state".equals(type) && !isHostOf(room, from.memberId)) {
                Log.w(TAG, "[YQK-WS] drop state from non-host who=" + from.memberId
                        + " room=" + room);
                return;
            }

            // 强序帧：服务端统一编号（客户端只读不写）
            if (SEQ_FRAMES.contains(type) && !o.has("seq")) {
                int seq = Store.get(ctx).nextRoomSeq(room);
                if (seq > 0) {
                    o.put("seq", seq);
                    text = o.toString();
                }
            }
            seqInFrame = o.optInt("seq", -1);
            // 改写过的帧（补了 seq / 归一了字段）要重新序列化再转发
            if (!text.equals(origText)) text = o.toString();
        } catch (Throwable ignored) {
        }

        if (!room.isEmpty()) {
            Log.i(TAG, "[YQK-WS] relay type=" + type + " from=" + from.memberId
                    + " seq=" + seqInFrame + " len=" + text.length());
        }
        List<Ws> targets = new ArrayList<Ws>(wsList);
        for (Ws t : targets) {
            // I-46：chat/danmaku 回显给发送者，让它收到自己那两条的 seq，
            // 否则 _lastSeq 永远落后 2，每条消息都触发一次 sync。
            // 只对这两类帧生效；state / members / control / claim / ice / offer / sdp 一律不回显。
            if (t == from && ("chat".equals(type) || "danmaku".equals(type))) {
                t.sendText(text);
                continue;
            }
            if (t == from) {
                Log.i(TAG, "relay skip self t=" + t.memberId);
                continue;
            }
            if (!t.open) {
                Log.i(TAG, "relay skip closed t=" + t.memberId);
                continue;
            }
            if (!room.isEmpty() && !room.equals(t.room)) {
                Log.i(TAG, "relay skip room t=" + t.memberId
                        + " want=" + room + " got=" + t.room);
                continue;
            }
            Log.i(TAG, "relay send t=" + t.memberId + " room=" + t.room);
            t.sendText(text);
        }
        if (!room.isEmpty()) {
            Log.i(TAG, "ws relay type=" + type + " room=" + room + " targets=" + targets.size());
        }
        // D21 房间回放：danmaku 转发成功后留一份原始帧（含服务端补的 seq），
        // 后进房的人靠 hello 里的 danmakus 数组重放。只留内存，不做磁盘。
        if ("danmaku".equals(type) && !room.isEmpty()) {
            java.util.Deque<String> hist = DANMAKU_HIST.get(room);
            if (hist == null) {
                hist = new java.util.ArrayDeque<String>();
                java.util.Deque<String> prev =
                        DANMAKU_HIST.putIfAbsent(room, hist);
                if (prev != null) hist = prev;
            }
            synchronized (hist) {
                hist.addLast(text);
                while (hist.size() > DANMAKU_HIST_MAX) hist.removeFirst();
                Log.i(TAG, "[YQK-WS] dm-hist room=" + room + " n=" + hist.size());
            }
        }
        // H11：房间回放录制。放在转发之后、Bot 之前 —— Bot 自己发的 chat 也会走一遍
        // relay 再录进来，顺序与客户端看到的完全一致。
        // 用重新解析的 text（o 只在上面那个 try 作用域里），这样录到的是客户端实际收到的那份。
        if (!room.isEmpty()) {
            try {
                recordFrame(room, type, new JSONObject(text));
            } catch (Throwable ignored) {
            }
        }
        // D27：Bot 触发放在转发之后，保证「用户消息先到、Bot 回复后到」。
        // 放在补 seq 之前会变成 Bot 先说话，客户端看到回复早于提问。
        if ("chat".equals(type) && !room.isEmpty()) {
            maybeBotReply(room, from.memberId, botChatText);
        }
    }

    /** 广播给房间里的所有连接（HTTP 端点也可调用） */
    /** 只发给房里某个 member（用于把 claim 的 pending 递给房主） */
    public void sendToMember(String room, String memberId, String json) {
        if (memberId == null || memberId.isEmpty()) return;
        List<Ws> targets = new ArrayList<Ws>(wsList);
        for (Ws t : targets) {
            if (!t.open) continue;
            if (room != null && !room.isEmpty() && !room.equals(t.room)) continue;
            if (!memberId.equals(t.memberId)) continue;
            t.sendText(json);
            return;
        }
    }

    public void broadcastRoom(String room, String json) {
        List<Ws> targets = new ArrayList<Ws>(wsList);
        int n = 0;
        for (Ws t : targets) {
            if (!t.open) continue;
            if (!t.approved) continue;
            if (room != null && !room.isEmpty() && !room.equals(t.room)) continue;
            t.sendText(json);
            n++;
        }
        Log.i(TAG, "broadcast room=" + room + " -> " + n);
    }

    // ───────── D27：房间 Bot（本地规则版，不接 LLM） ─────────

    /** 房主判断复用服务端既有口径：room.host 存的是 memberId。 */
    private boolean isHostOf(String room, String memberId) {
        if (room == null || room.isEmpty() || memberId == null) return false;
        JSONObject rm = Store.get(ctx).rooms.get(room);
        if (rm == null) return false;
        return memberId.equals(Store.hostIdOf(rm));
    }

    /** 房主下发 Bot 配置：落内存 → 建/复用 Bot 成员 → 广播 bot-state（客户端只读）。 */
    private void handleBotConfig(Ws from, JSONObject o) {
        String room = from.room == null ? "" : from.room;
        if (room.isEmpty()) return;
        if (!isHostOf(room, from.memberId)) {
            from.sendText(errObj("not_host", o.optString("rid", ""), "只有房主能配 Bot").toString());
            Log.i(TAG, "[YQK-BOT] config reject not-host by=" + from.memberId);
            return;
        }
        BotCfg c = BOTS.get(room);
        if (c == null) {
            c = new BotCfg();
            BOTS.put(room, c);
        }
        c.enabled = o.optBoolean("enabled", true);
        c.name = o.optString("name", c.name);
        c.reply = o.optString("reply", c.reply);
        c.cooldownSec = Math.max(0, o.optInt("cooldownSec", c.cooldownSec));
        c.hourlyQuota = Math.max(0, o.optInt("hourlyQuota", c.hourlyQuota));
        c.occupySlot = o.optBoolean("occupySlot", c.occupySlot);
        // aliases 用 [,，\n] 分割（原包规则，20 号 §2.2）
        String raw = o.optString("aliases", "");
        c.aliases.clear();
        for (String a : raw.split("[,，\\n]")) {
            String t = a.trim();
            if (!t.isEmpty()) c.aliases.add(t);
        }
        if (c.aliases.isEmpty()) c.aliases.add(c.name);
        // Bot 成员：第一次建，之后复用同一条记录
        if (c.memberId.isEmpty()) {
            JSONObject roomObj = Store.get(ctx).rooms.get(room);
            if (roomObj != null) {
                JSONObject bm = Store.get(ctx).addMember(roomObj, c.name, false, true);
                c.memberId = bm == null ? "" : bm.optString("id", "");
            }
        }
        Log.i(TAG, "[YQK-BOT] config room=" + room + " name=" + c.name
                + " alias=" + c.aliases + " cd=" + c.cooldownSec + " quota=" + c.hourlyQuota
                + " slot=" + c.occupySlot + " on=" + c.enabled + " mid=" + c.memberId);
        JSONObject st = new JSONObject();
        try {
            st.put("type", "bot-state");
            st.put("room", room);
            st.put("enabled", c.enabled);
            st.put("name", c.name);
            st.put("aliases", new JSONArray(c.aliases));
            st.put("cooldownSec", c.cooldownSec);
            st.put("hourlyQuota", c.hourlyQuota);
            st.put("occupySlot", c.occupySlot);
            st.put("memberId", c.memberId);
            st.put("seq", Store.get(ctx).nextRoomSeq(room));
        } catch (Throwable ignored) {
        }
        broadcastRoom(room, st.toString());

        // I-43：配置保存后要立刻刷新成员条，否则 Bot 的 🤖 要等有人进出才出现
        java.util.Set<String> on = new java.util.HashSet<String>();
        for (Ws w : new ArrayList<Ws>(wsList)) {
            if (w.open && room.equals(w.room) && w.memberId != null) on.add(w.memberId);
        }
        if (c.occupySlot && !c.memberId.isEmpty()) on.add(c.memberId);
        broadcastMembers(room, on);
    }

    /** 收到 chat 后判别名 → 冷却 → 配额 → 以 Bot 身份广播一条 chat。 */
    private void maybeBotReply(String room, String fromMemberId, String text) {
        BotCfg c = BOTS.get(room);
        if (c == null || !c.enabled || text.isEmpty()) return;
        if (!c.memberId.isEmpty() && c.memberId.equals(fromMemberId)) return; // 防自激
        String hit = null;
        for (String a : c.aliases) {
            if (text.contains(a)) {
                hit = a;
                break;
            }
        }
        if (hit == null) return;
        String key = room + "|" + hit;
        long now = android.os.SystemClock.elapsedRealtime();
        Long last = BOT_AT.get(key);
        if (last != null && now - last < c.cooldownSec * 1000L) {
            Log.i(TAG, "[YQK-BOT] skip cooldown room=" + room + " alias=" + hit
                    + " dt=" + (now - last) + "ms");
            return;
        }
        int hour = (int) (System.currentTimeMillis() / 3600000L);
        int[] bucket = BOT_HOUR.get(key);
        if (bucket == null || bucket[0] != hour) {
            bucket = new int[]{hour, 0};
            BOT_HOUR.put(key, bucket);
        }
        if (bucket[1] >= c.hourlyQuota) {
            Log.i(TAG, "[YQK-BOT] skip quota room=" + room + " alias=" + hit
                    + " n=" + bucket[1] + "/" + c.hourlyQuota);
            return;
        }
        int n = Store.get(ctx).nextRoomSeq(room);
        JSONObject f = new JSONObject();
        try {
            f.put("type", "chat");
            f.put("room", room);
            f.put("id", "ch_" + Store.randId(8));
            f.put("from", c.memberId);
            f.put("name", c.name);
            f.put("text", c.reply);
            f.put("bot", true);
            if (n > 0) f.put("seq", n);
        } catch (Throwable ignored) {
            return;
        }
        BOT_AT.put(key, now);
        bucket[1]++;
        broadcastRoom(room, f.toString());
        Log.i(TAG, "[YQK-BOT] reply room=" + room + " alias=" + hit
                + " quota=" + bucket[1] + "/" + c.hourlyQuota + " len=" + c.reply.length());
    }

    /**
     * I-44：房主移出成员。真正关连接（4005），不是只广播一条没人处理的帧。
     *
     * 顺序有讲究：先 markKicked（重连带旧 token 会被 4005 拒）→ 再 close(4005)
     * → 再广播 kicked（给房里其他人）→ 最后 broadcastMembers 把人数刷掉。
     * kicked 帧里带 seq，走的是强序通道，客户端那边只用来提示/清理。
     */
    private void handleKick(Ws from, JSONObject o) {
        String room = from.room == null ? "" : from.room;
        String target = o.optString("member", o.optString("memberId", o.optString("id", "")));
        if (room.isEmpty() || target.isEmpty()) return;
        if (!isHostOf(room, from.memberId)) {
            from.sendText(errObj("not_host", o.optString("rid", ""), "只有房主能移出成员").toString());
            Log.i(TAG, "[YQK-KICK] reject not-host by=" + from.memberId + " target=" + target);
            return;
        }
        if (target.equals(from.memberId)) {
            Log.i(TAG, "[YQK-KICK] ignore self-kick by=" + from.memberId);
            return;
        }
        Store st = Store.get(ctx);
        JSONObject rm = st.rooms.get(room);
        if (rm == null) return;
        JSONObject tm = st.memberById(room, target);
        if (tm == null) {
            Log.i(TAG, "[YQK-KICK] target not found room=" + room + " id=" + target);
            return;
        }
        st.markKicked(rm, target);
        int closed = 0;
        for (Ws w : new ArrayList<Ws>(wsList)) {
            if (w.open && room.equals(w.room) && target.equals(w.memberId)) {
                w.close(4005, "kicked");
                closed++;
            }
        }
        JSONObject k = new JSONObject();
        try {
            k.put("type", "kicked");
            k.put("room", room);
            k.put("id", target);
            k.put("by", from.memberId);
            k.put("seq", Store.get(ctx).nextRoomSeq(room));
        } catch (Throwable ignored) {
        }
        broadcastRoom(room, k.toString());
        java.util.Set<String> on = new java.util.HashSet<String>();
        for (Ws w : new ArrayList<Ws>(wsList)) {
            if (w.open && room.equals(w.room) && w.memberId != null) on.add(w.memberId);
        }
        BotCfg bc = BOTS.get(room);
        if (bc != null && bc.occupySlot && !bc.memberId.isEmpty()) on.add(bc.memberId);
        broadcastMembers(room, on);
        Log.i(TAG, "[YQK-KICK] room=" + room + " target=" + target
                + " by=" + from.memberId + " closed=" + closed);
    }

    /**
     * 成员进出广播（2026-11-08）：进房 hello、连接断开两处调用。     *
     * online 必须由调用方传进来（进房时用 hello 分支里那份，断开时用移除后重算的那份），
     * 不能在这里再扫一次 wsList —— 否则快照里的 online 标记和「N 人在看」会打架。
     * 未批准成员不进 broadcastRoom（那里已经有 approved 过滤）。
     */
    private void broadcastMembers(String room, java.util.Set<String> online) {
        if (room == null || room.isEmpty()) return;
        try {
            Store st = Store.get(ctx);
            JSONObject snap = st.roomSnapshot(room, online);
            if (snap == null) return;
            JSONObject out = new JSONObject();
            out.put("type", "members");
            out.put("room", room);
            JSONArray mem = snap.optJSONArray("members");
            out.put("members", mem == null ? new JSONArray() : mem);
            int seq = st.nextRoomSeq(room);
            if (seq > 0) out.put("seq", seq);
            broadcastRoom(room, out.toString());
            Log.i(TAG, "[YQK-WS] members broadcast room=" + room
                    + " online=" + (online == null ? -1 : online.size()));
        } catch (Throwable ignored) {
        }
    }

    /**
     * 构造语音成员全量帧。形状固定：{"type":"voice-state","items":[{id,name,muted,speaking}]}。
     *
     * 为什么是全量而不是 11 号 §6.6 写的增量 {id,on}：这一轮客户端的 UI 要画成员条上的 🎤，
     * 增量帧一旦丢一条就永远对不上，全量最多落后一帧、下一帧自愈。帧名仍然用 §6.6 / SEQ_FRAMES
     * 里的 voice-state，只是字段换成 items（这是本轮任务书指定的形状）。兼容读取见 handleVoice。
     *
     * withSeq=false 用于「只发给某一个人的快照」（hello / 审批后的 hello）：seq 是全房单调量，
     * 单播帧占号会让所有其他人看到一次跳号、白补一轮 sync，所以单播一律不带 seq。
     */
    private JSONObject buildVoiceStateFrame(String room, boolean withSeq) {
        if (room == null || room.isEmpty()) return null;
        try {
            JSONArray items = new JSONArray();
            java.util.LinkedHashSet<String> set = VOICE.get(room);
            java.util.LinkedHashSet<String> mutedSet = VOICE_MUTED.get(room);
            if (set != null) {
                synchronized (set) {
                    for (String mid : set) {
                        JSONObject one = new JSONObject();
                        one.put("id", mid);
                        one.put("name", voiceNameOf(room, mid));
                        one.put("muted", mutedSet != null && mutedSet.contains(mid));
                        one.put("speaking", false); // 7a 不做音量检测，恒 false
                        items.put(one);
                    }
                }
            }
            JSONObject out = new JSONObject();
            out.put("type", "voice-state");
            out.put("room", room);
            out.put("items", items);
            if (withSeq) {
                try {
                    int seq = Store.get(ctx).nextRoomSeq(room);
                    if (seq > 0) out.put("seq", seq);
                } catch (Throwable ignored) {
                }
            }
            return out;
        } catch (Throwable t) {
            Log.w(TAG, "[YQK-VOICE] state 构造失败 " + t);
            return null;
        }
    }

    private void broadcastVoiceState(String room) {
        if (room == null || room.isEmpty()) return;
        try {
            JSONObject out = buildVoiceStateFrame(room, true);
            if (out == null) return;
            broadcastRoom(room, out.toString());
            JSONArray its = out.optJSONArray("items");
            Log.i(TAG, "[YQK-VOICE] state room=" + room + " n=" + (its == null ? 0 : its.length()));
        } catch (Throwable t) {
            Log.w(TAG, "[YQK-VOICE] state 广播失败 " + t);
        }
    }

    /** 从房间成员表里取显示名；取不到就空串（UI 自己兜「成员」）。 */
    private String voiceNameOf(String room, String mid) {
        try {
            JSONObject rm = Store.get(ctx).rooms.get(room);
            if (rm == null) return "";
            JSONArray arr = rm.optJSONArray("members");
            if (arr == null) return "";
            for (int i = 0; i < arr.length(); i++) {
                JSONObject m = arr.optJSONObject(i);
                if (m == null) continue;
                if (mid.equals(m.optString("id", ""))) {
                    return m.optString("name", m.optString("nickname", ""));
                }
            }
        } catch (Throwable ignored) {
        }
        return "";
    }

    /**
     * 把某个成员从语音里摘掉并广播。断线、被踢、房间关闭都走这里 ——
     * 不许依赖客户端发 leave（进程被 kill 时它一帧都发不出来）。
     */
    private void voiceRemove(String room, String memberId) {
        if (room == null || room.isEmpty() || memberId == null || memberId.isEmpty()) return;
        java.util.LinkedHashSet<String> set = VOICE.get(room);
        boolean changed = false;
        if (set != null) {
            synchronized (set) {
                changed = set.remove(memberId);
                if (set.isEmpty()) VOICE.remove(room);
            }
        }
        java.util.LinkedHashSet<String> mutedSet = VOICE_MUTED.get(room);
        if (mutedSet != null) {
            synchronized (mutedSet) {
                mutedSet.remove(memberId);
                if (mutedSet.isEmpty()) VOICE_MUTED.remove(room);
            }
        }
        if (changed) {
            Log.i(TAG, "[YQK-VOICE] leave room=" + room + " member=" + memberId + " reason=cleanup");
            broadcastVoiceState(room);
        }
    }

    private JSONObject voiceErrorFrame(String code, String to, String msg) {
        JSONObject e = new JSONObject();
        try {
            e.put("type", "voice-error");
            e.put("code", code);
            if (to != null && !to.isEmpty()) e.put("to", to);
            if (msg != null && !msg.isEmpty()) e.put("message", msg);
        } catch (Throwable ignored) {
        }
        return e;
    }

    /** 这个成员当前是否在语音里（SDP 只允许语音成员互发，否则「看不见的人」也在收 SDP）。 */
    private boolean inVoice(String room, String mid) {
        java.util.LinkedHashSet<String> set = VOICE.get(room);
        if (set == null || mid == null || mid.isEmpty()) return false;
        synchronized (set) {
            return set.contains(mid);
        }
    }

    /** 这个成员是否真的在房间成员表里且已通过审批（没走过 claim 的连接不许进语音）。 */
    private boolean isRoomMember(String room, String mid) {
        try {
            JSONObject rm = Store.get(ctx).rooms.get(room);
            if (rm == null) return false;
            JSONArray arr = rm.optJSONArray("members");
            if (arr == null) return false;
            for (int i = 0; i < arr.length(); i++) {
                JSONObject m = arr.optJSONObject(i);
                if (m != null && mid != null && mid.equals(m.optString("id", ""))
                        && m.optBoolean("approved", true)) return true;
            }
        } catch (Throwable ignored) {
        }
        return false;
    }

    private boolean isMemberOnline(String room, String memberId) {
        if (room == null || memberId == null || memberId.isEmpty()) return false;
        for (Ws w : new ArrayList<Ws>(wsList)) {
            if (w.open && room.equals(w.room) && memberId.equals(w.memberId)) return true;
        }
        return false;
    }

    /**
     * 语音上行指令。帧名只有一个 voice，动作靠 action 区分（join / leave / mute），
     * 不许自创 voice-join 这类名字：11 号 §6.6 与服务端 SEQ_FRAMES 都只有 voice 一个。
     */
    private void handleVoice(Ws from, JSONObject o) {
        try {
        String room = from.room == null ? "" : from.room;
        String mid = from.memberId == null ? "" : from.memberId;
        if (room.isEmpty() || mid.isEmpty()) {
            from.sendText(voiceErrorFrame("no-room", "", "还没进房间").toString());
            Log.w(TAG, "[YQK-VOICE] drop voice from=" + mid + " reason=no-room");
            return;
        }
        String action = o.optString("action", "");
        // 兼容 11 号 §6.6 的老形状 {"type":"voice","on":true}：本轮客户端不发，但探针/旧版本会发
        if (action.isEmpty() && o.has("on")) {
            action = o.optBoolean("on", false) ? "join" : "leave";
        }
        java.util.LinkedHashSet<String> set = VOICE.get(room);
        if (set == null) {
            set = new java.util.LinkedHashSet<String>();
            VOICE.put(room, set);
        }
        if ("join".equals(action)) {
            if (!isRoomMember(room, mid)) {
                from.sendText(voiceErrorFrame("not-member", "", "先加入房间").toString());
                Log.w(TAG, "[YQK-VOICE] drop join member=" + mid + " reason=not-member");
                return;
            }
            boolean full = false;
            boolean disabled = false;
            synchronized (set) {
                if (set.contains(mid)) {
                    // 幂等：重复 join 直接回一条全量，不报错、不计数
                    broadcastVoiceState(room);
                    Log.i(TAG, "[YQK-VOICE] join 幂等 member=" + mid);
                    return;
                }
                // 全局语音开关：放在幂等之后（关开关不会把已在线的人踢出）、满员之前（两种错误不混报）
                if (!Store.get(ctx).voiceEnabled) {
                    disabled = true;
                } else {
                    full = set.size() >= VOICE_MAX;
                    if (!full) set.add(mid);
                }
            }
            if (disabled) {
                from.sendText(voiceErrorFrame("voice-disabled", mid, "语音已关闭").toString());
                Log.w(TAG, "[YQK-VOICE] drop join member=" + mid + " reason=voice-disabled");
                return;
            }
            if (full) {
                int n;
                synchronized (set) {
                    n = set.size();
                }
                JSONObject fe = new JSONObject();
                fe.put("type", "voice-full");
                fe.put("max", VOICE_MAX);
                fe.put("room", room);
                // voice-full 只发给发起者，不带 seq：seq 是全房单调量，单播帧占号会让所有人跳号补 sync。
                from.sendText(fe.toString());
                Log.i(TAG, "[YQK-VOICE] full 拒绝加入 room=" + room + " n=" + n);
                return;
            }
            Log.i(TAG, "[YQK-VOICE] join ok room=" + room + " member=" + mid);
            broadcastVoiceState(room);
            return;
        }
        if ("leave".equals(action)) {
            boolean removed = false;
            synchronized (set) {
                removed = set.remove(mid);
                if (set.isEmpty()) VOICE.remove(room);
            }
            java.util.LinkedHashSet<String> ms = VOICE_MUTED.get(room);
            if (ms != null) {
                synchronized (ms) {
                    ms.remove(mid);
                    if (ms.isEmpty()) VOICE_MUTED.remove(room);
                }
            }
            Log.i(TAG, "[YQK-VOICE] leave room=" + room + " member=" + mid + " hit=" + removed);
            broadcastVoiceState(room);
            return;
        }
        if ("mute".equals(action)) {
            boolean want = o.optBoolean("muted", true);
            java.util.LinkedHashSet<String> ms = VOICE_MUTED.get(room);
            if (ms == null) {
                ms = new java.util.LinkedHashSet<String>();
                VOICE_MUTED.put(room, ms);
            }
            synchronized (ms) {
                if (want) ms.add(mid); else ms.remove(mid);
            }
            Log.i(TAG, "[YQK-VOICE] mute room=" + room + " member=" + mid + " muted=" + want);
            broadcastVoiceState(room);
            return;
        }
        from.sendText(voiceErrorFrame("bad-action", "", "未知 action=" + action).toString());
        Log.w(TAG, "[YQK-VOICE] drop voice action=" + action);
        } catch (Throwable t) {
            Log.w(TAG, "[YQK-VOICE] 处理失败 " + t);
        }
    }

    private static String wsAccept(String key) {
        try {
            MessageDigest md = MessageDigest.getInstance("SHA-1");
            byte[] d = md.digest((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").getBytes(Store.UTF8));
            return android.util.Base64.encodeToString(d, android.util.Base64.NO_WRAP);
        } catch (Throwable t) {
            return "";
        }
    }

    static final class Frame {
        int opcode;
        boolean fin;
        byte[] payload;
    }

    static Frame readFrame(InputStream in) throws IOException {
        int b0 = in.read();
        if (b0 < 0) return null;
        int b1 = in.read();
        if (b1 < 0) return null;
        Frame f = new Frame();
        f.opcode = b0 & 0x0F;
        f.fin = (b0 & 0x80) != 0;
        boolean masked = (b1 & 0x80) != 0;
        long len = b1 & 0x7F;
        if (len == 126) {
            int a = in.read();
            int b = in.read();
            if (a < 0 || b < 0) return null;
            len = ((a & 0xFF) << 8) | (b & 0xFF);
        } else if (len == 127) {
            len = 0;
            for (int i = 0; i < 8; i++) {
                int c = in.read();
                if (c < 0) return null;
                len = (len << 8) | (c & 0xFF);
            }
        }
        byte[] mask = new byte[4];
        if (masked) {
            for (int i = 0; i < 4; i++) {
                int c = in.read();
                if (c < 0) return null;
                mask[i] = (byte) c;
            }
        }
        if (len > 8 * 1024 * 1024) return null;
        byte[] p = new byte[(int) len];
        int off = 0;
        while (off < p.length) {
            int n = in.read(p, off, p.length - off);
            if (n < 0) return null;
            off += n;
        }
        if (masked) {
            for (int i = 0; i < p.length; i++) {
                p[i] = (byte) (p[i] ^ mask[i & 3]);
            }
        }
        f.payload = p;
        return f;
    }

    static void writeFrame(OutputStream out, int opcode, byte[] payload) throws IOException {
        ByteArrayOutputStream b = new ByteArrayOutputStream();
        b.write(0x80 | opcode);
        int len = payload.length;
        if (len < 126) {
            b.write(len);
        } else if (len < 65536) {
            b.write(126);
            b.write((len >>> 8) & 0xFF);
            b.write(len & 0xFF);
        } else {
            b.write(127);
            for (int i = 7; i >= 0; i--) {
                b.write((int) ((((long) len) >>> (8 * i)) & 0xFF));
            }
        }
        b.write(payload);
        out.write(b.toByteArray());
        out.flush();
    }

    // ================================================================ 工具

    public static String queryParam(String query, String key) {
        if (query == null || query.isEmpty()) return null;
        String[] parts = query.split("&");
        for (String p : parts) {
            int e = p.indexOf('=');
            String k = e >= 0 ? p.substring(0, e) : p;
            if (!k.equals(key)) continue;
            if (e < 0) return "";
            String v = p.substring(e + 1);
            try {
                return java.net.URLDecoder.decode(v, "UTF-8");
            } catch (Throwable t) {
                return v;
            }
        }
        return null;
    }

    /** 本机局域网 IPv4，供"一起看"手填 */
    public static String lanIp() {
        try {
            Enumeration<NetworkInterface> ifs = NetworkInterface.getNetworkInterfaces();
            while (ifs != null && ifs.hasMoreElements()) {
                NetworkInterface ni = ifs.nextElement();
                if (!ni.isUp() || ni.isLoopback()) continue;
                String name = ni.getName() == null ? "" : ni.getName();
                if (name.startsWith("dummy") || name.startsWith("rmnet")) continue;
                Enumeration<InetAddress> addrs = ni.getInetAddresses();
                while (addrs.hasMoreElements()) {
                    InetAddress a = addrs.nextElement();
                    if (a instanceof Inet4Address && !a.isLoopbackAddress()) {
                        String h = a.getHostAddress();
                        if (h != null && !h.startsWith("127.")) return h;
                    }
                }
            }
        } catch (Throwable ignored) {
        }
        return "127.0.0.1";
    }

    /**
     * D26：本机所有可用的局域网 IPv4（每张网卡一个），给客户端的通道列表用。
     *
     * <p>跳过 loopback / 未启用 / rmnet(蜂窝) / dummy 这些"不是同一 Wi-Fi"的地址；
     * 只收 Inet4Address。任何异常都吞掉并返回已收集到的部分 —— 通道枚举失败
     * 不能让房间分享直接 500。
     */
    public static org.json.JSONArray lanAddrs(int port) {
        org.json.JSONArray a = new org.json.JSONArray();
        try {
            Enumeration<NetworkInterface> ifs = NetworkInterface.getNetworkInterfaces();
            while (ifs != null && ifs.hasMoreElements()) {
                NetworkInterface ni = ifs.nextElement();
                if (!ni.isUp() || ni.isLoopback()) continue;
                String nm = ni.getName() == null ? "" : ni.getName();
                if (nm.startsWith("dummy") || nm.startsWith("rmnet")) continue;
                java.util.List<java.net.InterfaceAddress> ias = ni.getInterfaceAddresses();
                if (ias == null) continue;
                for (java.net.InterfaceAddress ia : ias) {
                    InetAddress ip = ia == null ? null : ia.getAddress();
                    if (ip == null || ip.isLoopbackAddress() || !(ip instanceof Inet4Address)) continue;
                    org.json.JSONObject o = new org.json.JSONObject();
                    o.put("id", "lan");
                    o.put("name", ni.getDisplayName());
                    o.put("host", ip.getHostAddress());
                    o.put("port", port);
                    a.put(o);
                }
            }
        } catch (Throwable t) {
            Log.w(TAG, "[YQK-CH] lan enum fail " + t);
        }
        return a;
    }

    // ============================================================ D25 局域网广播

    /**
     * D25：每 2 秒把「active 且有人」的房间用 UDP 广播到 LAN_PORT，让同一 Wi-Fi 下的
     * 另一台设备/PC 能看见这个房间。
     *
     * <p>只发不收 —— 收的那一半（附近房间列表 UI）在下一轮，所以这里不许出现 receive。
     * 任何异常只打日志：一次网络抖动不能让广播线程永久死掉。
     */
    private final class UdpBeacon {
        private Thread thread;
        private DatagramSocket socket;
        private volatile boolean running = false;

        void start() {
            running = true;
            try {
                socket = new DatagramSocket();
                socket.setBroadcast(true);
            } catch (Throwable t) {
                Log.w(TAG, "[YQK-LAN] beacon fail socket " + t);
            }
            thread = new Thread(new Runnable() {
                @Override
                public void run() {
                    loop();
                }
            }, "yiqikan-lan");
            thread.setDaemon(true);
            thread.start();
        }

        void stop() {
            running = false;
            if (thread != null) thread.interrupt();
            thread = null;
            if (socket != null) {
                try {
                    socket.close();
                } catch (Throwable ignored) {
                }
            }
            socket = null;
        }

        private void loop() {
            while (running) {
                try {
                    emitOnce();
                } catch (Throwable t) {
                    Log.w(TAG, "[YQK-LAN] beacon fail " + t);
                }
                try {
                    Thread.sleep(2000L);
                } catch (InterruptedException e) {
                    if (!running) return;
                }
            }
        }

        private void emitOnce() {
            final DatagramSocket s = socket;
            if (s == null || s.isClosed()) return;
            List<JSONObject> all;
            try {
                all = Store.get(ctx).allRooms();
            } catch (Throwable t) {
                Log.w(TAG, "[YQK-LAN] beacon fail rooms " + t);
                return;
            }
            for (JSONObject room : all) {
                if (room == null) continue;
                // 建房间目前不写 status；缺省按 active 处理，显式写别的值就跳过
                if (!"active".equals(room.optString("status", "active"))) continue;
                JSONArray ms = room.optJSONArray("members");
                if (ms == null || ms.length() < 1) continue;
                // 「有人在看」：rooms.json 里的成员离房后仍留着，只按成员数判会把
                // 已经退到房间列表页的房间继续广播出去，所以要有一个在线连接
                if (!anyOnline(room.optString("code", ""))) continue;
                final String code = room.optString("code", "");
                if (code.isEmpty()) continue;
                byte[] body;
                try {
                    // 字段表固定六个：v / code / name / host / port / ts，不许加
                    JSONObject p = new JSONObject();
                    p.put("v", 1);
                    p.put("code", code);
                    p.put("name", room.optString("name", ""));
                    p.put("host", hostNameOf(room));
                    p.put("port", PORT);
                    p.put("ts", System.currentTimeMillis());
                    body = p.toString().getBytes(java.nio.charset.Charset.forName("UTF-8"));
                } catch (Throwable t) {
                    continue;
                }
                try {
                    s.send(new DatagramPacket(body, body.length,
                            InetAddress.getByName("255.255.255.255"), LAN_PORT));
                    Log.i(TAG, "[YQK-LAN] beacon code=" + code + " port=" + PORT + " bytes=" + body.length);
                } catch (IOException e) {
                    Log.w(TAG, "[YQK-LAN] beacon fail " + e);
                } catch (Throwable t) {
                    Log.w(TAG, "[YQK-LAN] beacon fail " + t);
                }
            }
        }

        /** 这个房间当前有没有活着的 WS 连接（有人真的在里面看） */
        private boolean anyOnline(String code) {
            if (code.isEmpty()) return false;
            synchronized (wsList) {
                for (Ws w : wsList) {
                    if (w != null && w.open && code.equals(w.room)) return true;
                }
            }
            return false;
        }

        /** 房主昵称：room.host 是 memberId，名字在 members[].nickname */        private String hostNameOf(JSONObject room) {
            try {
                String hid = room.optString("host", "");
                JSONArray ms = room.optJSONArray("members");
                if (ms != null) {
                    for (int i = 0; i < ms.length(); i++) {
                        JSONObject m = ms.optJSONObject(i);
                        if (m == null) continue;
                        if (hid.equals(m.optString("id", ""))) {
                            String n = m.optString("nickname", "");
                            return n.isEmpty() ? m.optString("name", "") : n;
                        }
                    }
                }
            } catch (Throwable ignored) {
            }
            return "";
        }
    }
}
