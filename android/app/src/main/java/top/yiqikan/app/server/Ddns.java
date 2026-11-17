package top.yiqikan.app.server;

import android.content.Context;
import android.os.Handler;
import android.os.HandlerThread;
import android.util.Log;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;

/**
 * E7 DDNS：把「本机公网 IP」写到一个固定域名上，让分享链接不随隧道 URL 变。
 *
 * <p>本轮只实现 duckdns 一种 provider（端点简单，不需要签名）：
 * {@code https://www.duckdns.org/update?domains=X&token=Y&ip=}。
 * cloudflare / dnspod / aliyun 需要各自的鉴权流程，留 TODO。
 *
 * <p>定时器挂在 {@link LocalServer#start()} 的生命周期上，5 分钟一次；
 * 公网 IP 没变就不发请求（和 18 号 §2.2 的 DdnsUpdater 口径一致）。
 * 全部在后台线程，绝不阻塞主线程。
 */
public final class Ddns {

    private static final String TAG = "YQK-DDNS";
    private static final long TICK_MS = 5L * 60L * 1000L;
    private static final int TIMEOUT = 5000;

    private static volatile Ddns INSTANCE;

    private final Context ctx;
    private HandlerThread thread;
    private Handler handler;
    private volatile boolean running;

    private Ddns(Context ctx) {
        this.ctx = ctx.getApplicationContext();
    }

    public static Ddns get(Context c) {
        if (INSTANCE == null) {
            synchronized (Ddns.class) {
                if (INSTANCE == null) INSTANCE = new Ddns(c);
            }
        }
        return INSTANCE;
    }

    /** 前台服务起来时调：起一条后台线程，先跑一次再每 5 分钟一次。 */
    public synchronized void start() {
        if (running) return;
        running = true;
        thread = new HandlerThread("yqk-ddns");
        thread.start();
        handler = new Handler(thread.getLooper());
        handler.postDelayed(new Runnable() {
            @Override
            public void run() {
                if (!running) return;
                try {
                    Store st = Store.get(ctx);
                    if (st != null && st.ddnsHost != null && !st.ddnsHost.trim().isEmpty()) {
                        updateNow(ctx, st);
                    }
                } catch (Throwable t) {
                    Log.w(TAG, "[YQK-DDNS] tick fail " + t);
                }
                synchronized (Ddns.this) {
                    if (running && handler != null) handler.postDelayed(this, TICK_MS);
                }
            }
        }, 8000L);
        Log.i(TAG, "[YQK-DDNS] scheduler start tick=" + (TICK_MS / 1000) + "s");
    }

    public synchronized void stop() {
        running = false;
        if (handler != null) {
            try {
                handler.removeCallbacksAndMessages(null);
            } catch (Throwable ignored) {
            }
            handler = null;
        }
        if (thread != null) {
            try {
                thread.quitSafely();
            } catch (Throwable ignored) {
            }
            thread = null;
        }
    }

    public synchronized boolean isRunning() {
        return running;
    }

    // ------------------------------------------------------------ 更新

    /**
     * 立刻更新一次（同步、会阻塞调用线程 —— 调用方负责放到后台线程）。
     *
     * @return ok / nochange / fail:...
     */
    public static String updateNow(Context ctx, Store st) {
        String host = st.ddnsHost == null ? "" : st.ddnsHost.trim();
        if (host.isEmpty()) {
            st.ddnsLastResult = "fail:no host";
            return st.ddnsLastResult;
        }
        String provider = st.ddnsProvider == null ? "" : st.ddnsProvider.trim();
        if (provider.isEmpty()) provider = "duckdns";
        if (!"duckdns".equals(provider)) {
            // TODO: noip（需 user:pass 的 Basic Auth）、custom（自己写 CNAME）
            st.ddnsLastResult = "fail:unsupported provider";
            Log.w(TAG, "[YQK-DDNS] provider unsupported provider=" + provider);
            return st.ddnsLastResult;
        }

        String ip = publicIp();
        if (ip.isEmpty()) {
            st.ddnsLastResult = "fail:no public ip";
            Log.w(TAG, "[YQK-DDNS] host=" + host + " result=" + st.ddnsLastResult);
            return st.ddnsLastResult;
        }
        boolean sameIp = ip.equals(st.ddnsLastIp);
        if (sameIp && "ok".equals(st.ddnsLastResult)) {
            st.ddnsLastAt = System.currentTimeMillis();
            return "nochange";
        }

        String domains = host;
        if (domains.endsWith(".duckdns.org")) {
            domains = domains.substring(0, domains.length() - ".duckdns.org".length());
        }
        String token = st.ddnsToken == null ? "" : st.ddnsToken.trim();
        String url = "https://www.duckdns.org/update?domains=" + enc(domains)
                + "&token=" + enc(token) + "&ip=" + enc(ip);
        String body = httpGet(url);
        String result;
        if (body == null) {
            result = "fail:request";
        } else if (body.trim().startsWith("OK")) {
            result = "ok";
        } else {
            result = "fail:" + body.trim();
        }
        st.ddnsLastIp = ip;
        st.ddnsLastAt = System.currentTimeMillis();
        st.ddnsLastResult = result;
        try {
            st.save();
        } catch (Throwable ignored) {
        }
        // token 不许进日志
        Log.i(TAG, "[YQK-DDNS] host=" + host + " ip=" + ip + " result=" + result);
        return result;
    }

    /** 取公网 IPv4 的候选源，按顺序试，任一成功即返回。 */
    private static final String[] IP_SOURCES = {
            "https://api.ipify.org?format=text",
            "https://ifconfig.me/ip",
            "https://ipinfo.io/ip",
            "https://myip.ipip.net",
    };

    private static final java.util.regex.Pattern IPV4 =
            java.util.regex.Pattern.compile("(\\d{1,3}\\.){3}\\d{1,3}");

    /**
     * 公网 IPv4，多源依次试（每个 3 秒超时）。
     * myip.ipip.net 回中文，用正则提第一个 IPv4；其余源取整段纯文本。
     *
     * @return 成功返回 IP 并打 {@code [YQK-DDNS] ip=... via=源}；全失败返回空串并打
     *         {@code [YQK-DDNS] ip=null tried=4}
     */
    static String publicIp() {
        for (String src : IP_SOURCES) {
            String body = httpGet(src);
            if (body == null) continue;
            String v = body.trim();
            if (v.isEmpty()) continue;
            String ip;
            // 四个源都按「取第一个 IPv4」处理：ipify/ifconfig/ipinfo 多数回纯 v4，
            // 但 ifconfig.me 在双栈网络下会回 IPv6，而 duckdns 的 ip= 只认 IPv4；
            // myip.ipip.net 回中文（当前 IP：1.2.3.4 来自于…），同样靠正则提。
            // 取不到 IPv4 就换下一个源，绝不把 v6 当公网地址写进 DDNS。
            java.util.regex.Matcher m = IPV4.matcher(v);
            ip = m.find() ? m.group() : "";
            if (ip.isEmpty()) continue;
            Log.i(TAG, "[YQK-DDNS] ip=" + ip + " via=" + src);
            return ip;
        }
        Log.w(TAG, "[YQK-DDNS] ip=null tried=" + IP_SOURCES.length);
        return "";
    }

    static String httpGet(String url) {
        HttpURLConnection c = null;
        try {
            c = (HttpURLConnection) new URL(url).openConnection();
            c.setConnectTimeout(TIMEOUT);
            c.setReadTimeout(TIMEOUT);
            c.setRequestMethod("GET");
            c.setRequestProperty("User-Agent", "yiqikan-ddns/1");
            int code = c.getResponseCode();
            InputStream in = code >= 400 ? c.getErrorStream() : c.getInputStream();
            if (in == null) return null;
            ByteArrayOutputStream bo = new ByteArrayOutputStream();
            byte[] buf = new byte[1024];
            int n;
            while ((n = in.read(buf)) > 0) {
                bo.write(buf, 0, n);
                if (bo.size() > 8192) break;
            }
            in.close();
            return new String(bo.toByteArray(), "UTF-8");
        } catch (Throwable t) {
            Log.w(TAG, "[YQK-DDNS] http fail " + t);
            return null;
        } finally {
            if (c != null) c.disconnect();
        }
    }

    static String enc(String s) {
        try {
            return java.net.URLEncoder.encode(s == null ? "" : s, "UTF-8");
        } catch (Throwable t) {
            return "";
        }
    }
}
