package top.yiqikan.app.server;

import android.content.Context;
import android.util.Log;

import org.json.JSONArray;
import org.json.JSONObject;

import java.net.DatagramPacket;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.net.MulticastSocket;
import java.net.NetworkInterface;
import java.util.Enumeration;
import java.util.UUID;

/**
 * 最小 MediaRenderer（10 号 M10 的 C 组 / 15 号 H9）。
 *
 * <p>三件事：
 * <ol>
 *   <li>SSDP：监听 239.255.255.250:1900，收到 M-SEARCH 且 ST 匹配时单播回 200；</li>
 *   <li>描述：{@code /dlna/desc.xml} + {@code /dlna/avt.xml}（AVTransport 的 SCPD）；</li>
 *   <li>控制：{@code /dlna/control} 收 SOAP，把命令压进队列，由 Flutter 侧
 *       {@code /dlna/pending} 轮询取走并作用到播放器。</li>
 * </ol>
 *
 * <p>为什么要排队而不是直接控制播放器：播放器在 Dart 里（mpv/fvp 都在 Flutter 侧），
 * Java 服务端拿不到控制器。队列 + 轮询是最小侵入的做法（不改 /ws、不改帧协议）。
 *
 * <p>只在「房间内且是房主」时由 Dart 侧调 {@code /local/dlna/renderer?on=1} 打开，
 * 退房 {@code on=0} 关掉（避免和房主自己的播放器打架，见 15 号 H9 的坑）。
 */
public final class DlnaRenderer {

    private static final String TAG = LocalServer.TAG;
    private static final String SSDP_ADDR = "239.255.255.250";
    private static final int SSDP_PORT = 1900;
    private static final String ST_RENDERER = "urn:schemas-upnp-org:device:MediaRenderer:1";
    private static final String DEVICE_TYPE = ST_RENDERER;

    private static DlnaRenderer INSTANCE;

    public static synchronized DlnaRenderer get(Context ctx) {
        if (INSTANCE == null) INSTANCE = new DlnaRenderer(ctx.getApplicationContext());
        return INSTANCE;
    }

    private final Context ctx;
    private final String uuid = UUID.randomUUID().toString();
    private final JSONArray pending = new JSONArray();
    private volatile boolean running;
    private volatile String friendlyName = "一起看";
    private volatile String lastUri = "";
    private Thread ssdpThread;
    private MulticastSocket ssdpSocket;

    private DlnaRenderer(Context ctx) {
        this.ctx = ctx;
    }

    public boolean isRunning() {
        return running;
    }

    public String friendlyName() {
        return friendlyName;
    }

    public String location() {
        String ip = LocalServer.lanIp();
        if (ip == null || ip.isEmpty()) ip = "127.0.0.1";
        return "http://" + ip + ":" + LocalServer.PORT + "/dlna/desc.xml";
    }

    /** 打开接收端。已在跑时只更新名字。 */
    public synchronized void start(String name) {
        if (name != null && !name.trim().isEmpty()) friendlyName = name.trim();
        if (running) return;
        running = true;
        ssdpThread = new Thread(this::ssdpLoop, "yqk-dlna-ssdp");
        ssdpThread.setDaemon(true);
        ssdpThread.start();
        Log.i(TAG, "[YQK-DLNA] renderer ready name=" + friendlyName + " loc=" + location());
    }

    public synchronized void stop() {
        if (!running) return;
        running = false;
        try {
            if (ssdpSocket != null) ssdpSocket.close();
        } catch (Throwable ignored) {
        }
        ssdpSocket = null;
        ssdpThread = null;
        synchronized (pending) {
            // org.json 的 JSONArray 没有 reset()：倒着删空
            for (int i = pending.length() - 1; i >= 0; i--) pending.remove(i);
        }
        Log.i(TAG, "[YQK-DLNA] renderer stop");
    }

    // ---------------- SSDP ----------------

    private void ssdpLoop() {
        MulticastSocket sock = null;
        try {
            sock = new MulticastSocket(SSDP_PORT);
            sock.setReuseAddress(true);
            InetAddress group = InetAddress.getByName(SSDP_ADDR);
            try {
                sock.joinGroup(group);
            } catch (Throwable t) {
                // 有的机器默认网卡不走组播：逐个网卡再试一次
                Enumeration<NetworkInterface> it = NetworkInterface.getNetworkInterfaces();
                while (it != null && it.hasMoreElements()) {
                    NetworkInterface ni = it.nextElement();
                    try {
                        if (ni.isUp() && !ni.isLoopback()) sock.joinGroup(new InetSocketAddress(group, SSDP_PORT), ni);
                    } catch (Throwable ignored) {
                    }
                }
            }
            ssdpSocket = sock;
            byte[] buf = new byte[2048];
            while (running) {
                DatagramPacket pkt = new DatagramPacket(buf, buf.length);
                try {
                    sock.receive(pkt);
                } catch (Throwable t) {
                    if (!running) break;
                    continue;
                }
                String msg = new String(pkt.getData(), 0, pkt.getLength(), "UTF-8");
                if (!msg.toUpperCase().contains("M-SEARCH")) continue;
                String upper = msg.toUpperCase();
                boolean want = upper.contains("SSDP:DISCOVER")
                        && (upper.contains("MEDIARENDERER") || upper.contains("SSDP:ALL")
                        || upper.contains("UPNP:ROOTDEVICE"));
                if (!want) continue;
                reply(pkt.getAddress(), pkt.getPort());
            }
        } catch (Throwable t) {
            Log.w(TAG, "[YQK-DLNA] ssdp loop fail " + t);
        } finally {
            try {
                if (sock != null) sock.close();
            } catch (Throwable ignored) {
            }
        }
    }

    private void reply(InetAddress to, int port) {
        try {
            String body = "HTTP/1.1 200 OK\r\n"
                    + "CACHE-CONTROL: max-age=1800\r\n"
                    + "EXT:\r\n"
                    + "LOCATION: " + location() + "\r\n"
                    + "SERVER: Android/9 UPnP/1.0 YiQiKan/1.0\r\n"
                    + "ST: " + ST_RENDERER + "\r\n"
                    + "USN: uuid:" + uuid + "::" + ST_RENDERER + "\r\n"
                    + "Content-Length: 0\r\n"
                    + "\r\n";
            DatagramSocketHolder.send(body.getBytes("UTF-8"), to, port);
            Log.i(TAG, "[YQK-DLNA] ssdp reply to=" + to.getHostAddress() + ":" + port
                    + " st=" + ST_RENDERER);
        } catch (Throwable t) {
            Log.w(TAG, "[YQK-DLNA] ssdp reply fail " + t);
        }
    }

    /** 单播回包用的小工具：每次新建 socket，避免和监听 socket 抢端口。 */
    private static final class DatagramSocketHolder {
        static void send(byte[] data, InetAddress to, int port) throws Exception {
            java.net.DatagramSocket s = new java.net.DatagramSocket();
            try {
                s.send(new DatagramPacket(data, data.length, to, port));
            } finally {
                s.close();
            }
        }
    }

    // ---------------- 描述 ----------------

    public String descXml() {
        return "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"
                + "<root xmlns=\"urn:schemas-upnp-org:device-1-0\">"
                + "<specVersion><major>1</major><minor>0</minor></specVersion>"
                + "<device>"
                + "<deviceType>" + DEVICE_TYPE + "</deviceType>"
                + "<friendlyName>" + xml(friendlyName) + "</friendlyName>"
                + "<manufacturer>YiQiKan</manufacturer>"
                + "<modelName>YiQiKan Renderer</modelName>"
                + "<UDN>uuid:" + uuid + "</UDN>"
                + "<serviceList><service>"
                + "<serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType>"
                + "<serviceId>urn:upnp-org:serviceId:AVTransport</serviceId>"
                + "<SCPDURL>/dlna/avt.xml</SCPDURL>"
                + "<controlURL>/dlna/control</controlURL>"
                + "<eventSubURL>/dlna/event</eventSubURL>"
                + "</service></serviceList>"
                + "</device></root>";
    }

    public String avtScpdXml() {
        return "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"
                + "<scpd xmlns=\"urn:schemas-upnp-org:service-1-0\">"
                + "<specVersion><major>1</major><minor>0</minor></specVersion>"
                + "<actionList>"
                + action("SetAVTransportURI", "InstanceID", "CurrentURI", "CurrentURIMetaData")
                + action("Play", "InstanceID", "Speed")
                + action("Pause", "InstanceID")
                + action("Stop", "InstanceID")
                + action("Seek", "InstanceID", "Unit", "Target")
                + "</actionList></scpd>";
    }

    private static String action(String name, String... args) {
        StringBuilder sb = new StringBuilder("<action><name>").append(name).append("</name>");
        sb.append("<argumentList>");
        for (String a : args) {
            sb.append("<argument><name>").append(a)
                    .append("</name><direction>in</direction><relatedStateVariable>")
                    .append(a).append("</relatedStateVariable></argument>");
        }
        return sb.append("</argumentList></action>").toString();
    }

    // ---------------- SOAP 控制 ----------------

    /**
     * 处理一条 SOAP 请求。
     *
     * @param soapAction 头里的 SOAPAction（可能带引号）
     * @param body       SOAP 信封原文
     * @return 回应信封
     */
    public String control(String soapAction, String body) {
        String action = "Unknown";
        if (soapAction != null) {
            String a = soapAction.replace("\"", "");
            int i = a.lastIndexOf('#');
            if (i >= 0) action = a.substring(i + 1);
        }
        JSONObject cmd = new JSONObject();
        try {
            cmd.put("cmd", action);
            if ("SetAVTransportURI".equals(action)) {
                String uri = tag(body, "CurrentURI");
                cmd.put("url", uri);
                lastUri = uri;
                Log.i(TAG, "[YQK-DLNA] set uri=" + uri);
            } else if ("Seek".equals(action)) {
                String target = tag(body, "Target");
                cmd.put("pos", hms(target));
                Log.i(TAG, "[YQK-DLNA] cmd=Seek target=" + target);
            } else {
                Log.i(TAG, "[YQK-DLNA] cmd=" + action);
            }
        } catch (Throwable t) {
            Log.w(TAG, "[YQK-DLNA] control parse fail " + t);
        }
        synchronized (pending) {
            pending.put(cmd);
            if (pending.length() > 32) pending.remove(0);
        }
        String svc = "urn:schemas-upnp-org:service:AVTransport:1";
        return "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"
                + "<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\" "
                + "s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\">"
                + "<s:Body><u:" + action + "Response xmlns:u=\"" + svc + "\"/>"
                + "</s:Body></s:Envelope>";
    }

    /** 取走一条待执行命令（Flutter 侧轮询）。没有则返回 null。 */
    public JSONObject poll() {
        synchronized (pending) {
            if (pending.length() == 0) return null;
            Object o = pending.remove(0);
            return o instanceof JSONObject ? (JSONObject) o : null;
        }
    }

    public String lastUri() {
        return lastUri;
    }

    private static String tag(String body, String name) {
        if (body == null) return "";
        String open = "<" + name;
        int i = body.indexOf(open);
        if (i < 0) return "";
        int gt = body.indexOf('>', i);
        if (gt < 0) return "";
        int end = body.indexOf("</" + name + ">", gt);
        if (end < 0) return "";
        return unxml(body.substring(gt + 1, end).trim());
    }

    /** HH:MM:SS / HH:MM:SS.mmm → 秒 */
    private static double hms(String s) {
        if (s == null || s.isEmpty()) return 0;
        String[] parts = s.split(":");
        try {
            if (parts.length == 3) {
                return Integer.parseInt(parts[0]) * 3600
                        + Integer.parseInt(parts[1]) * 60
                        + Double.parseDouble(parts[2]);
            }
            if (parts.length == 2) {
                return Integer.parseInt(parts[0]) * 60 + Double.parseDouble(parts[1]);
            }
            return Double.parseDouble(s);
        } catch (Throwable t) {
            return 0;
        }
    }

    static String xml(String s) {
        if (s == null) return "";
        return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
                .replace("\"", "&quot;").replace("'", "&apos;");
    }

    static String unxml(String s) {
        if (s == null) return "";
        return s.replace("&lt;", "<").replace("&gt;", ">").replace("&quot;", "\"")
                .replace("&apos;", "'").replace("&amp;", "&");
    }
}
