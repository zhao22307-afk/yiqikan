package top.yiqikan.app.server;

import android.content.Context;
import android.util.Log;

import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.net.URI;
import java.net.URL;
import java.security.SecureRandom;
import java.util.Base64;

/**
 * E9 relay 骨架：手机主动连公网中继的 WebSocket，把中继送来的请求打到本机
 * 127.0.0.1:8080，再把响应发回去（NAT 后面的机器不用开端口）。
 *
 * <p>本轮没有 VPS，所以：能编译、能配置、能给出「未配置 / 连不上」的明确状态，
 * 真联调等有中继节点再做。工程里没有 okhttp / Java-WebSocket，这里是手写的
 * RFC6455 客户端（握手 + 帧读写），不引入新依赖。
 *
 * <p>重连上限 3 次（1s/2s/4s 退避），超过就停 —— 不许无限重连把电池啃光。
 * 一切网络动作都在后台线程，configure() 立即返回。
 */
public final class Relay {

    private static final String TAG = "YQK-RELAY";
    private static final int MAX_ATTEMPTS = 3;
    private static final int CONNECT_TIMEOUT = 3000;

    private static volatile Relay INSTANCE;

    private final Context ctx;

    private volatile String url = "";
    private volatile String token = "";
    private volatile boolean connected;
    private volatile String lastError = "";
    private volatile int attempts;
    private volatile boolean wantRun;
    private volatile Thread worker;

    private Relay(Context ctx) {
        this.ctx = ctx.getApplicationContext();
    }

    public static Relay get(Context c) {
        if (INSTANCE == null) {
            synchronized (Relay.class) {
                if (INSTANCE == null) INSTANCE = new Relay(c);
            }
        }
        return INSTANCE;
    }

    // ------------------------------------------------------------ 配置

    /** 读 Store 里的配置并尝试连接（立即返回，连接在后台）。 */
    public void configure(String rawUrl, String rawToken) {
        this.url = rawUrl == null ? "" : rawUrl.trim();
        this.token = rawToken == null ? "" : rawToken.trim();
        this.lastError = "";
        this.attempts = 0;
        if (this.url.isEmpty()) {
            connected = false;
            lastError = "未配置中继";
            wantRun = false;
            Log.i(TAG, "[YQK-RELAY] configured=false");
            return;
        }
        Log.i(TAG, "[YQK-RELAY] configured url=" + this.url);
        start();
    }

    public boolean configured() {
        return url != null && !url.isEmpty();
    }

    public boolean connected() {
        return connected;
    }

    public String lastError() {
        return lastError == null ? "" : lastError;
    }

    public int attempts() {
        return attempts;
    }

    public String url() {
        return url == null ? "" : url;
    }

    public synchronized void stop() {
        wantRun = false;
        connected = false;
        Thread w = worker;
        worker = null;
        if (w != null) w.interrupt();
    }

    // ------------------------------------------------------------ 连接循环

    private synchronized void start() {
        wantRun = true;
        if (worker != null && worker.isAlive()) return;
        worker = new Thread(new Runnable() {
            @Override
            public void run() {
                loop();
            }
        }, "yqk-relay");
        worker.setDaemon(true);
        worker.start();
    }

    private void loop() {
        int a = 0;
        while (wantRun && a < MAX_ATTEMPTS) {
            a++;
            attempts = a;
            try {
                wsLoop();
                // wsLoop 只在断开时返回
            } catch (Throwable t) {
                lastError = shortMsg(t);
                connected = false;
                Log.w(TAG, "[YQK-RELAY] attempt=" + a + " fail " + lastError);
            }
            if (!wantRun) break;
            if (a < MAX_ATTEMPTS) {
                long backoff = 1000L << (a - 1); // 1s, 2s, 4s
                Log.i(TAG, "[YQK-RELAY] retry in " + backoff + "ms attempt=" + (a + 1));
                try {
                    Thread.sleep(backoff);
                } catch (InterruptedException e) {
                    break;
                }
            }
        }
        connected = false;
        if (a >= MAX_ATTEMPTS) {
            if (lastError.isEmpty()) lastError = "重连 " + MAX_ATTEMPTS + " 次仍未成功";
            Log.w(TAG, "[YQK-RELAY] give up attempts=" + a + " lastError=" + lastError);
        }
    }

    /** 一次完整的 WS 会话；断开（读不到帧）时返回或抛异常。 */
    private void wsLoop() throws Exception {
        URI u = URI.create(url);
        String scheme = u.getScheme() == null ? "ws" : u.getScheme();
        boolean tls = "wss".equalsIgnoreCase(scheme) || "https".equalsIgnoreCase(scheme);
        String host = u.getHost();
        int port = u.getPort() > 0 ? u.getPort() : (tls ? 443 : 80);
        String path = u.getRawPath() == null || u.getRawPath().isEmpty() ? "/" : u.getRawPath();
        if (u.getRawQuery() != null) path = path + "?" + u.getRawQuery();

        Socket s = tls ? javax.net.ssl.SSLSocketFactory.getDefault().createSocket() : new Socket();
        s.connect(new InetSocketAddress(host, port), CONNECT_TIMEOUT);
        s.setSoTimeout(0);
        InputStream in = s.getInputStream();
        OutputStream out = s.getOutputStream();

        byte[] nonce = new byte[16];
        new SecureRandom().nextBytes(nonce);
        String key = Base64.getEncoder().encodeToString(nonce);
        StringBuilder req = new StringBuilder();
        req.append("GET ").append(path).append(" HTTP/1.1\r\n");
        req.append("Host: ").append(host).append(':').append(port).append("\r\n");
        req.append("Upgrade: websocket\r\n");
        req.append("Connection: Upgrade\r\n");
        req.append("Sec-WebSocket-Key: ").append(key).append("\r\n");
        req.append("Sec-WebSocket-Version: 13\r\n");
        if (token != null && !token.isEmpty()) {
            req.append("Authorization: Bearer ").append(token).append("\r\n");
        }
        req.append("\r\n");
        out.write(req.toString().getBytes("UTF-8"));
        out.flush();

        String status = readLine(in);
        if (status == null || !status.contains("101")) {
            throw new IllegalStateException("握手失败: " + (status == null ? "无响应" : status.trim()));
        }
        String line;
        while ((line = readLine(in)) != null && !line.isEmpty()) {
            // 吃掉响应头
        }
        connected = true;
        lastError = "";
        Log.i(TAG, "[YQK-RELAY] connected url=" + url);
        // 骨架阶段先报个到：让中继端知道这头是哪个端口的本地服务
        String hello = "{\"type\":\"hello\",\"from\":\"yiqikan\",\"port\":"
                + LocalServer.PORT + "}";
        writeFrame(out, 0x1, hello.getBytes("UTF-8"));
        Log.i(TAG, "[YQK-RELAY] tx=" + hello);

        while (wantRun) {
            Frame f = readFrame(in);
            if (f == null) break;
            if (f.opcode == 0x8) break; // close
            if (f.opcode == 0x9) { // ping → pong
                writeFrame(out, 0xA, f.payload);
                continue;
            }
            if (f.opcode != 0x1 && f.opcode != 0x2) continue;
            String body = new String(f.payload, "UTF-8");
            Log.i(TAG, "[YQK-RELAY] rx=" + body);
            String reply = handle(body);
            writeFrame(out, 0x1, reply.getBytes("UTF-8"));
        }
        connected = false;
        try {
            s.close();
        } catch (Throwable ignored) {
        }
        Log.i(TAG, "[YQK-RELAY] disconnected url=" + url);
    }

    /** 中继发来的请求 → 打到本机 → 结构化响应。协议形状等有 VPS 再定。 */
    private String handle(String text) {
        JSONObject out = new JSONObject();
        try {
            JSONObject req = new JSONObject(text);
            String method = req.optString("method", "GET");
            String path = req.optString("path", "/");
            String body = req.optString("body", "");
            String base = "http://127.0.0.1:" + LocalServer.PORT;
            HttpURLConnection c = (HttpURLConnection) new URL(base + path).openConnection();
            c.setConnectTimeout(CONNECT_TIMEOUT);
            c.setReadTimeout(CONNECT_TIMEOUT);
            c.setRequestMethod(method);
            if (!body.isEmpty() && ("POST".equals(method) || "PUT".equals(method))) {
                c.setDoOutput(true);
                c.setRequestProperty("Content-Type", "application/json; charset=utf-8");
                OutputStream o = c.getOutputStream();
                o.write(body.getBytes("UTF-8"));
                o.flush();
                o.close();
            }
            int code = c.getResponseCode();
            InputStream in = code >= 400 ? c.getErrorStream() : c.getInputStream();
            String resp = in == null ? "" : slurp(in);
            out.put("id", req.optString("id", ""));
            out.put("status", code);
            out.put("body", resp);
        } catch (Throwable t) {
            try {
                out.put("id", "");
                out.put("status", 0);
                out.put("body", "");
                out.put("error", shortMsg(t));
            } catch (Throwable ignored) {
            }
        }
        return out.toString();
    }

    // ------------------------------------------------------------ RFC6455 小工具

    private static final class Frame {
        int opcode;
        byte[] payload;
    }

    private static Frame readFrame(InputStream in) throws Exception {
        int b0 = in.read();
        if (b0 < 0) return null;
        int b1 = in.read();
        if (b1 < 0) return null;
        Frame f = new Frame();
        f.opcode = b0 & 0x0F;
        boolean masked = (b1 & 0x80) != 0;
        long len = b1 & 0x7F;
        if (len == 126) {
            len = ((in.read() & 0xFF) << 8) | (in.read() & 0xFF);
        } else if (len == 127) {
            len = 0;
            for (int i = 0; i < 8; i++) len = (len << 8) | (in.read() & 0xFF);
        }
        byte[] mask = null;
        if (masked) {
            mask = new byte[4];
            readFully(in, mask);
        }
        if (len > 4 * 1024 * 1024) throw new IllegalStateException("帧过大 " + len);
        byte[] data = new byte[(int) len];
        readFully(in, data);
        if (mask != null) {
            for (int i = 0; i < data.length; i++) data[i] ^= mask[i % 4];
        }
        f.payload = data;
        return f;
    }

    private static void writeFrame(OutputStream out, int opcode, byte[] payload) throws Exception {
        ByteArrayOutputStream bo = new ByteArrayOutputStream();
        bo.write(0x80 | (opcode & 0x0F));
        int len = payload == null ? 0 : payload.length;
        if (len < 126) {
            bo.write(0x80 | len);
        } else if (len < 65536) {
            bo.write(0x80 | 126);
            bo.write((len >> 8) & 0xFF);
            bo.write(len & 0xFF);
        } else {
            bo.write(0x80 | 127);
            for (int i = 7; i >= 0; i--) bo.write((int) (((long) len >> (8 * i)) & 0xFF));
        }
        byte[] mask = new byte[4];
        new SecureRandom().nextBytes(mask);
        bo.write(mask, 0, 4);
        for (int i = 0; i < len; i++) bo.write(payload[i] ^ mask[i % 4]);
        out.write(bo.toByteArray());
        out.flush();
    }

    private static void readFully(InputStream in, byte[] buf) throws Exception {
        int off = 0;
        while (off < buf.length) {
            int n = in.read(buf, off, buf.length - off);
            if (n < 0) throw new IllegalStateException("连接已断");
            off += n;
        }
    }

    private static String readLine(InputStream in) throws Exception {
        ByteArrayOutputStream bo = new ByteArrayOutputStream();
        int c;
        while ((c = in.read()) >= 0) {
            if (c == '\n') break;
            if (c != '\r') bo.write(c);
            if (bo.size() > 8192) break;
        }
        if (c < 0 && bo.size() == 0) return null;
        return new String(bo.toByteArray(), "UTF-8");
    }

    private static String slurp(InputStream in) throws Exception {
        ByteArrayOutputStream bo = new ByteArrayOutputStream();
        byte[] buf = new byte[2048];
        int n;
        while ((n = in.read(buf)) > 0) {
            bo.write(buf, 0, n);
            if (bo.size() > 65536) break;
        }
        in.close();
        return new String(bo.toByteArray(), "UTF-8");
    }

    private static String shortMsg(Throwable t) {
        String m = t.getMessage();
        if (m == null) m = t.getClass().getSimpleName();
        return m.length() > 160 ? m.substring(0, 160) : m;
    }
}
