package top.yiqikan.app.server;

import android.content.Context;
import android.util.Log;

import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.File;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.InetAddress;
import java.net.Socket;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Quick tunnel lifecycle: one cloudflared child process, one generation counter.
 *
 * States: OFF -> STARTING -> VERIFYING -> LIVE, or FAILED from any of them.
 * Every start()/stop() bumps generation; async work compares its own copy
 * against the current value and silently returns when it is stale.
 */
public class TunnelManager {

    private static final String TAG = "YQK-TUN";
    private static final String SO_NAME = "libcloudflared.so";
    private static final Pattern URL_PATTERN =
            Pattern.compile("https://[a-z0-9-]+\\.trycloudflare\\.com");

    public enum State { OFF, STARTING, VERIFYING, LIVE, FAILED }

    private static TunnelManager INSTANCE;

    private final Context app;

    private volatile State state = State.OFF;
    private volatile String tunnelUrl;
    private volatile String lastError;
    private volatile int generation = 0;
    private Process proc;

    private TunnelManager(Context ctx) {
        this.app = ctx.getApplicationContext();
    }

    public static synchronized TunnelManager get(Context ctx) {
        if (INSTANCE == null) {
            INSTANCE = new TunnelManager(ctx);
        }
        return INSTANCE;
    }

    public String state() {
        return state.name();
    }

    public String url() {
        return state == State.LIVE ? tunnelUrl : null;
    }

    public String lastError() {
        return state == State.FAILED ? lastError : null;
    }

    /** Starts the tunnel. Returns immediately; all work happens on a worker thread. */
    public void start(final int port) {
        final int myGen;
        synchronized (this) {
            myGen = ++generation;
            state = State.STARTING;
            lastError = null;
            tunnelUrl = null;
        }
        Log.i(TAG, "start gen=" + myGen + " port=" + port);

        Thread t = new Thread(new Runnable() {
            @Override
            public void run() {
                try {
                    runStart(myGen, port);
                } catch (Throwable e) {
                    fail(myGen, "crash " + e);
                }
            }
        }, "yiqikan-tunnel");
        t.setDaemon(true);
        t.start();
    }

    /** Kills the child process and clears every trace of the tunnel. Blocks up to 5s. */
    public void stop() {
        final int myGen;
        final Process p;
        synchronized (this) {
            myGen = ++generation;
            p = proc;
            proc = null;
            state = State.OFF;
            tunnelUrl = null;
            lastError = null;
        }
        Log.i(TAG, "stop gen=" + myGen);
        if (p != null) {
            try {
                p.destroy();
            } catch (Throwable ignored) {
            }
            long deadline = System.currentTimeMillis() + 5000;
            while (System.currentTimeMillis() < deadline) {
                try {
                    p.exitValue();
                    break;
                } catch (IllegalThreadStateException alive) {
                    try {
                        Thread.sleep(50);
                    } catch (InterruptedException ie) {
                        Thread.currentThread().interrupt();
                        break;
                    }
                }
            }
            try {
                p.destroyForcibly();
            } catch (Throwable ignored) {
            }
        }
        Store st = Store.get(app);
        if (st != null && st.tunnelUrl != null && st.tunnelUrl.length() > 0) {
            st.tunnelUrl = "";
            Log.i(TAG, "store tunnelUrl cleared");
        }
    }

    // ---------------------------------------------------------------- worker

    private void runStart(int myGen, int port) {
        File bin = new File(app.getApplicationInfo().nativeLibraryDir, SO_NAME);
        if (!bin.exists()) {
            fail(myGen, "binary missing " + bin.getAbsolutePath());
            return;
        }

        List<String> edges = resolveEdges(myGen);
        if (edges.isEmpty()) {
            fail(myGen, "no edges");
            return;
        }

        List<String> cmd = new ArrayList<String>();
        cmd.add(bin.getAbsolutePath());
        cmd.add("tunnel");
        cmd.add("--url");
        cmd.add("http://127.0.0.1:" + port);
        cmd.add("--protocol");
        cmd.add("http2");
        cmd.add("--edge-ip-version");
        cmd.add("4");
        cmd.add("--retries");
        cmd.add("12");
        cmd.add("--no-autoupdate");
        cmd.add("--grace-period");
        cmd.add("5s");
        for (String ip : edges) {
            cmd.add("--edge");
            cmd.add(ip + ":7844");
        }

        Process p;
        try {
            ProcessBuilder pb = new ProcessBuilder(cmd);
            pb.redirectErrorStream(true);
            p = pb.start();
        } catch (Throwable e) {
            fail(myGen, "spawn fail " + e);
            return;
        }

        synchronized (this) {
            if (myGen != generation) {
                try {
                    p.destroy();
                } catch (Throwable ignored) {
                }
                return;
            }
            proc = p;
        }
        Log.i(TAG, "pid=" + pidOf(p));

        long began = System.currentTimeMillis();
        String found = null;
        boolean verifyStarted = false;
        BufferedReader r = null;
        try {
            r = new BufferedReader(new InputStreamReader(p.getInputStream(), "UTF-8"));
            String line;
            while ((line = r.readLine()) != null) {
                if (myGen != generation) {
                    return;
                }
                Log.i(TAG, "out: " + line);
                if (found == null) {
                    Matcher m = URL_PATTERN.matcher(line);
                    if (m.find()) {
                        found = m.group();
                        Log.i(TAG, "url=" + found + " after=" + (System.currentTimeMillis() - began) + "ms");
                        // cloudflared 是常驻进程，读循环不会结束；命中 URL 就得马上并行去自检，
                        // 否则状态会永远停在 STARTING。主循环继续 drain stdout，避免把子进程管道堵死。
                        verifyStarted = true;
                        final String urlForVerify = found;
                        new Thread(new Runnable() {
                            @Override
                            public void run() {
                                goLive(myGen, port, urlForVerify);
                            }
                        }, "yiqikan-tunnel-verify").start();
                    }
                }
            }
        } catch (Throwable e) {
            if (myGen == generation) {
                Log.w(TAG, "reader fail " + e);
            }
        } finally {
            try {
                if (r != null) r.close();
            } catch (Throwable ignored) {
            }
        }

        if (myGen != generation) {
            return;
        }
        if (found == null) {
            fail(myGen, "no url");
            return;
        }
        if (!verifyStarted) {
            goLive(myGen, port, found);
        }
    }

    /** VERIFYING -> 轮询 /health -> LIVE 并写 Store.tunnelUrl；供读循环命中 URL 时并行调用。 */
    private void goLive(int myGen, int port, String url) {
        synchronized (this) {
            if (myGen != generation) {
                return;
            }
            tunnelUrl = url;
            state = State.VERIFYING;
        }

        String err = verify(myGen, port);
        if (myGen != generation) {
            return;
        }
        if (err != null) {
            fail(myGen, "verify " + err);
            return;
        }

        Store st = Store.get(app);
        synchronized (this) {
            if (myGen != generation) {
                return;
            }
            state = State.LIVE;
        }
        if (st != null) {
            st.tunnelUrl = url;
        }
        Log.i(TAG, "live url=" + url);
        Log.i(TAG, "store tunnelUrl set");
    }

    private List<String> resolveEdges(int myGen) {
        LinkedHashSet<String> out = new LinkedHashSet<String>();
        String[] hosts = new String[]{"region1.v2.argotunnel.com", "region2.v2.argotunnel.com"};
        for (String host : hosts) {
            try {
                InetAddress[] all = InetAddress.getAllByName(host);
                for (InetAddress a : all) {
                    String ip = a.getHostAddress();
                    if (ip == null) continue;
                    if (ip.chars().filter(ch -> ch == '.').count() != 3) continue;
                    out.add(ip);
                }
            } catch (Throwable e) {
                Log.w(TAG, "resolve " + host + " fail " + e);
            }
            if (myGen != generation) {
                return new ArrayList<String>();
            }
        }
        Log.i(TAG, "edges=" + out.size());
        return new ArrayList<String>(out);
    }

    /** Returns null when the local server answers 200 on /health, else the failure text. */
    private String verify(int myGen, int port) {
        String last = "no attempt";
        for (int i = 1; i <= 12; i++) {
            if (myGen != generation) {
                return "stale";
            }
            try {
                Thread.sleep(600);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                return "interrupted";
            }
            if (myGen != generation) {
                return "stale";
            }
            try {
                String code = probeHealth(port);
                if ("200".equals(code)) {
                    return null;
                }
                last = "http " + code;
            } catch (Throwable e) {
                last = String.valueOf(e.getMessage());
            }
            Log.i(TAG, "verify try=" + i + " fail=" + last);
        }
        return last;
    }

    private String probeHealth(int port) throws Exception {
        Socket s = new Socket("127.0.0.1", port);
        try {
            s.setSoTimeout(1500);
            OutputStream os = s.getOutputStream();
            os.write("GET /health HTTP/1.0\r\nHost: 127.0.0.1\r\n\r\n".getBytes("UTF-8"));
            os.flush();
            BufferedReader r = new BufferedReader(new InputStreamReader(s.getInputStream(), "UTF-8"));
            String line = r.readLine();
            if (line == null) return "empty";
            String[] parts = line.split(" ");
            return parts.length >= 2 ? parts[1] : line;
        } finally {
            try {
                s.close();
            } catch (Throwable ignored) {
            }
        }
    }

    private void fail(int myGen, String why) {
        synchronized (this) {
            if (myGen != generation) {
                return;
            }
            state = State.FAILED;
            lastError = why;
            tunnelUrl = null;
        }
        Log.w(TAG, "fail gen=" + myGen + " reason=" + why);
        Process p = proc;
        proc = null;
        if (p != null) {
            try {
                p.destroy();
            } catch (Throwable ignored) {
            }
        }
    }

    private static long pidOf(Process p) {
        try {
            java.lang.reflect.Field f = p.getClass().getDeclaredField("pid");
            f.setAccessible(true);
            Object v = f.get(p);
            if (v instanceof Integer) return ((Integer) v).longValue();
        } catch (Throwable ignored) {
        }
        return -1L;
    }

    /** Snapshot for /local/tunnel. */
    public JSONObject snapshot() {
        JSONObject o = new JSONObject();
        try {
            o.put("state", state());
            String u = url();
            o.put("url", u == null ? JSONObject.NULL : u);
            String e = lastError();
            o.put("lastError", e == null ? JSONObject.NULL : e);
        } catch (Throwable ignored) {
        }
        return o;
    }
}
