package top.yiqikan.app.server;

import android.util.Log;

import java.net.DatagramPacket;
import java.net.DatagramSocket;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.net.NetworkInterface;
import java.util.Collections;

/**
 * 内置 STUN 服务（RFC 5389 的 Binding 子集）。
 * <p>
 * 作用：给 App 里的 WebRTC（flutter_webrtc / libjingle）一个<b>不依赖外网</b>的
 * STUN 端点。客户端拿到的 srflx 候选就是本机对外的地址，用于同一局域网内
 * 免中继互通；公网直连仍取决于 NAT 类型。
 * <p>
 * 只实现 Binding Request → Binding Success Response（XOR-MAPPED-ADDRESS +
 * MAPPED-ADDRESS），不处理 CHANGE-REQUEST / 认证。够用且不引入依赖。
 */
public final class Stun {

    public static final int PORT = Integer.getInteger("yiqikan.stun.port", 3478);

    private static final int MAGIC = 0x2112A442;
    private static final int TYPE_BINDING_REQUEST = 0x0001;
    private static final int TYPE_BINDING_OK = 0x0101;
    private static final int ATTR_MAPPED = 0x0001;
    private static final int ATTR_XOR_MAPPED = 0x0020;

    private static volatile boolean running = false;
    private static DatagramSocket socket;
    private static Thread worker;

    private Stun() {
    }

    public static synchronized boolean isRunning() {
        return running;
    }

    public static synchronized void start() {
        if (running) return;
        try {
            DatagramSocket s = new DatagramSocket(null);
            s.setReuseAddress(true);
            s.bind(new InetSocketAddress(PORT));
            socket = s;
            running = true;
        } catch (Throwable t) {
            Log.w(LocalServer.TAG, "stun bind failed on " + PORT + ": " + t);
            return;
        }
        worker = new Thread(new Runnable() {
            @Override
            public void run() {
                loop();
            }
        }, "yiqikan-stun");
        worker.setDaemon(true);
        worker.start();
        Log.i(LocalServer.TAG, "stun listening on udp/" + PORT);
    }

    public static synchronized void stop() {
        running = false;
        if (socket != null) {
            try {
                socket.close();
            } catch (Throwable ignored) {
            }
            socket = null;
        }
    }

    private static void loop() {
        byte[] buf = new byte[1500];
        while (running) {
            try {
                DatagramPacket p = new DatagramPacket(buf, buf.length);
                socket.receive(p);
                byte[] in = p.getData();
                int off = p.getOffset();
                int len = p.getLength();
                if (len < 20) continue;
                int type = ((in[off] & 0xff) << 8) | (in[off + 1] & 0xff);
                if (type != TYPE_BINDING_REQUEST) continue;
                int magic = ((in[off + 4] & 0xff) << 24) | ((in[off + 5] & 0xff) << 16)
                        | ((in[off + 6] & 0xff) << 8) | (in[off + 7] & 0xff);
                if (magic != MAGIC) continue;
                byte[] txid = new byte[12];
                System.arraycopy(in, off + 8, txid, 0, 12);

                InetAddress src = p.getAddress();
                int srcPort = p.getPort();
                byte[] resp = buildResponse(txid, src, srcPort);
                socket.send(new DatagramPacket(resp, resp.length, src, srcPort));
            } catch (Throwable t) {
                if (running) {
                    try {
                        Thread.sleep(20);
                    } catch (InterruptedException ignored) {
                    }
                }
            }
        }
    }

    private static byte[] buildResponse(byte[] txid, InetAddress addr, int port) {
        byte[] ip = addr.getAddress();
        boolean v6 = ip.length == 16;
        int attrLen = v6 ? 20 : 8;
        // XOR-MAPPED-ADDRESS + MAPPED-ADDRESS
        int total = 20 + (4 + attrLen) + (4 + attrLen);

        byte[] out = new byte[total];
        out[0] = (byte) (TYPE_BINDING_OK >> 8);
        out[1] = (byte) TYPE_BINDING_OK;
        int bodyLen = total - 20;
        out[2] = (byte) (bodyLen >> 8);
        out[3] = (byte) bodyLen;
        out[4] = (byte) (MAGIC >> 24);
        out[5] = (byte) (MAGIC >> 16);
        out[6] = (byte) (MAGIC >> 8);
        out[7] = (byte) MAGIC;
        System.arraycopy(txid, 0, out, 8, 12);

        int p = 20;
        // XOR-MAPPED-ADDRESS
        p = putAttrHeader(out, p, ATTR_XOR_MAPPED, attrLen);
        out[p++] = 0;
        out[p++] = (byte) (v6 ? 0x02 : 0x01);
        int xport = port ^ (MAGIC >>> 16);
        out[p++] = (byte) (xport >> 8);
        out[p++] = (byte) xport;
        for (int i = 0; i < ip.length; i++) {
            out[p++] = (byte) (ip[i] ^ ((MAGIC >>> (24 - (i % 4) * 8)) & 0xff));
        }
        // MAPPED-ADDRESS（老客户端）
        p = putAttrHeader(out, p, ATTR_MAPPED, attrLen);
        out[p++] = 0;
        out[p++] = (byte) (v6 ? 0x02 : 0x01);
        out[p++] = (byte) (port >> 8);
        out[p++] = (byte) port;
        System.arraycopy(ip, 0, out, p, ip.length);
        p += ip.length;
        return out;
    }

    private static int putAttrHeader(byte[] out, int p, int type, int len) {
        out[p++] = (byte) (type >> 8);
        out[p++] = (byte) type;
        out[p++] = (byte) (len >> 8);
        out[p++] = (byte) len;
        return p;
    }

    /** 给客户端用的 ICE 服务器列表：本机回环 + 局域网地址，全部指向内置 STUN */
    public static String iceServersJson() {
        StringBuilder sb = new StringBuilder();
        sb.append("{\"success\":true,\"ice_servers\":[");
        sb.append("{\"urls\":\"stun:").append("127.0.0.1:").append(PORT).append("\"}");
        String lan = NetInfo.lan();
        if (lan != null && !lan.isEmpty()) {
            sb.append(",{\"urls\":\"stun:").append(lan).append(":").append(PORT).append("\"}");
        }
        String v6 = NetInfo.primaryV6();
        if (v6 != null && !v6.isEmpty()) {
            sb.append(",{\"urls\":\"stun:[").append(v6).append("]:").append(PORT).append("\"}");
        }
        sb.append("],\"items\":[");
        sb.append("{\"urls\":\"stun:127.0.0.1:").append(PORT).append("\"}");
        sb.append("],\"port\":").append(PORT);
        sb.append(",\"local\":true}");
        return sb.toString();
    }

    /** 诊断：列出本机所有可能被 STUN 回显的地址 */
    static String ifaceSummary() {
        StringBuilder sb = new StringBuilder();
        try {
            for (NetworkInterface ni : Collections.list(NetworkInterface.getNetworkInterfaces())) {
                if (ni == null || !ni.isUp() || ni.isLoopback()) continue;
                sb.append(ni.getName()).append("=");
                sb.append(ni.getInetAddresses().hasMoreElements() ? "up" : "down").append(";");
            }
        } catch (Throwable ignored) {
        }
        return sb.toString();
    }
}
