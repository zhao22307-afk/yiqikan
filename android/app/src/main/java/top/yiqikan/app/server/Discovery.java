package top.yiqikan.app.server;

import org.json.JSONObject;

import android.util.Log;

import java.net.DatagramPacket;
import java.net.DatagramSocket;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.ScheduledFuture;
import java.util.concurrent.TimeUnit;

/**
 * 局域网房间发现（① 局域网 / ⑦ 组网）。
 *
 * <p>与本工程 {@code lib/sync/protocol.dart} 对齐：
 * UDP 广播 45231，报文 {@code {"kind":"advertise","room":{id,name,host,port,title,code}}}
 * 与 {@code {"kind":"probe"}}；房主每秒广播一次，收到 probe 立刻单播回一条。
 */
public final class Discovery {

    public static final int PORT = 45231;
    private static Discovery inst;

    public static synchronized Discovery get() {
        if (inst == null) inst = new Discovery();
        return inst;
    }

    private DatagramSocket sock;
    private Thread rx;
    private ScheduledExecutorService timer;
    private ScheduledFuture<?> advTask;
    private volatile boolean running;
    private volatile JSONObject self;

    /** 已发现的房间：roomId -> room json */
    public final Map<String, JSONObject> found =
            Collections.synchronizedMap(new LinkedHashMap<String, JSONObject>());

    public synchronized boolean start() {
        if (running) return true;
        try {
            DatagramSocket s = new DatagramSocket(null);
            s.setReuseAddress(true);
            s.setBroadcast(true);
            s.bind(new InetSocketAddress(PORT));
            sock = s;
        } catch (Throwable t) {
            sock = null;
            Log.w("YiqikanLocal", "Discovery bind " + PORT + " failed: " + t);
            return false;
        }
        running = true;
        rx = new Thread(new Runnable() {
            public void run() {
                rxLoop();
            }
        }, "yiqikan-discovery");
        rx.setDaemon(true);
        rx.start();
        timer = Executors.newSingleThreadScheduledExecutor();
        Log.i("YiqikanLocal", "Discovery listening on udp/" + PORT);
        return true;
    }

    public synchronized void stop() {
        running = false;
        stopAdvertise();
        try {
            if (sock != null) sock.close();
        } catch (Throwable ignored) {
        }
        sock = null;
        if (timer != null) {
            timer.shutdownNow();
            timer = null;
        }
    }

    public boolean isRunning() {
        return running;
    }

    /** 房主开始广播自己的房间 */
    public void advertise(JSONObject room) {
        if (!running) start();
        if (timer == null) return;
        self = room;
        stopAdvertise();
        advTask = timer.scheduleAtFixedRate(new Runnable() {
            public void run() {
                sendAdvertise(null);
            }
        }, 0, 1, TimeUnit.SECONDS);
    }

    public synchronized void stopAdvertise() {
        self = null;
        if (advTask != null) {
            advTask.cancel(false);
            advTask = null;
        }
    }

    /** 客人侧主动探测（开房/加入时调一次，房主会立刻回应，<200ms） */
    public void probe() {
        if (!running) start();
        send("\"kind\":\"probe\"", null);
    }

    private void sendAdvertise(InetSocketAddress to) {
        JSONObject room = self;
        if (room == null) return;
        send("\"kind\":\"advertise\",\"room\":" + room.toString(), to);
    }

    private void send(String body, InetSocketAddress to) {
        DatagramSocket s = sock;
        if (s == null || !running) return;
        try {
            byte[] payload = ("{" + body + "}").getBytes("UTF-8");
            InetSocketAddress dst = to != null
                    ? to
                    : new InetSocketAddress(InetAddress.getByName("255.255.255.255"), PORT);
            s.send(new DatagramPacket(payload, payload.length, dst));
        } catch (Throwable ignored) {
        }
    }

    private void rxLoop() {
        byte[] buf = new byte[4096];
        while (running) {
            DatagramSocket s = sock;
            if (s == null) break;
            try {
                DatagramPacket p = new DatagramPacket(buf, buf.length);
                s.receive(p);
                String text = new String(p.getData(), 0, p.getLength(), "UTF-8");
                JSONObject j = new JSONObject(text);
                String kind = j.optString("kind", "");
                if ("probe".equals(kind)) {
                    if (self != null) {
                        sendAdvertise(new InetSocketAddress(p.getAddress(), p.getPort()));
                    }
                } else if ("advertise".equals(kind)) {
                    JSONObject room = j.optJSONObject("room");
                    if (room == null) continue;
                    String id = room.optString("id", "");
                    if (id.isEmpty()) continue;
                    JSONObject mine = self;
                    if (mine != null && id.equals(mine.optString("id", ""))) continue;
                    room.put("seen_at", System.currentTimeMillis());
                    room.put("from", p.getAddress().getHostAddress());
                    found.put(id, room);
                }
            } catch (Throwable ignored) {
            }
        }
    }

    /** 供 HTTP 输出 */
    public String foundJson() {
        List<JSONObject> list;
        synchronized (found) {
            list = new ArrayList<JSONObject>(found.values());
        }
        StringBuilder b = new StringBuilder("[");
        long now = System.currentTimeMillis();
        boolean first = true;
        for (JSONObject r : list) {
            long seen = r.optLong("seen_at", 0);
            if (now - seen > 15000) continue;   // 15s 没更新视为离线
            if (!first) b.append(',');
            first = false;
            b.append(r.toString());
        }
        b.append(']');
        return b.toString();
    }
}
