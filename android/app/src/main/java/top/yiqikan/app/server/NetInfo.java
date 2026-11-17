package top.yiqikan.app.server;

import java.net.Inet4Address;
import java.net.Inet6Address;
import java.net.InetAddress;
import java.net.NetworkInterface;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/**
 * 网卡地址枚举，供七种建房方式选地址：
 * <ul>
 *   <li>{@code lan}   局域网 IPv4（① 局域网 / ⑤ 本机当后端）</li>
 *   <li>{@code ipv6}  全局 IPv6（② 公网直连，移动网络常直接给）</li>
 *   <li>{@code mesh}  100.64.0.0/10 CGNAT（⑦ Tailscale / ZeroTier 虚拟 IP）</li>
 * </ul>
 */
public final class NetInfo {

    public static final class Entry {
        public final String ip;
        public final String iface;
        public final String kind;

        Entry(String ip, String iface, String kind) {
            this.ip = ip;
            this.iface = iface;
            this.kind = kind;
        }

        public String toJson() {
            return "{\"ip\":" + Json.q(ip)
                    + ",\"iface\":" + Json.q(iface)
                    + ",\"kind\":" + Json.q(kind) + "}";
        }
    }

    public static List<Entry> all() {
        List<Entry> out = new ArrayList<Entry>();
        try {
            for (NetworkInterface ni : Collections.list(NetworkInterface.getNetworkInterfaces())) {
                if (ni == null || !ni.isUp() || ni.isLoopback()) continue;
                for (InetAddress a : Collections.list(ni.getInetAddresses())) {
                    if (a == null || a.isLoopbackAddress() || a.isLinkLocalAddress()) continue;
                    String ip = a.getHostAddress();
                    int pct = ip.indexOf('%');
                    if (pct > 0) ip = ip.substring(0, pct);
                    String kind;
                    if (a instanceof Inet4Address) {
                        kind = isMesh(ip) ? "mesh" : "lan";
                    } else if (a instanceof Inet6Address) {
                        kind = "ipv6";
                    } else {
                        continue;
                    }
                    if (isDockerish(ni.getName())) continue;
                    out.add(new Entry(ip, ni.getName(), kind));
                }
            }
        } catch (Throwable ignored) {
        }
        return out;
    }

    static boolean isDockerish(String name) {
        if (name == null) return false;
        String n = name.toLowerCase();
        return n.startsWith("docker") || n.startsWith("veth") || n.startsWith("br-")
                || n.startsWith("virbr") || n.startsWith("vboxnet") || n.startsWith("vmnet")
                || n.startsWith("vethernet") || n.startsWith("vnic") || n.startsWith("bridge")
                || n.startsWith("lxc") || n.startsWith("cni") || n.startsWith("flannel")
                || n.startsWith("tunl") || n.startsWith("isatap") || n.startsWith("teredo")
                || n.equals("dummy0") || n.equals("lo") || n.equals("sit0");
    }

    /**
     * 系统实际会用哪张网卡出网 —— 用「UDP connect 到公网 IP」让内核自己选路。
     * 这一步不发包，只是让内核按路由表填好本地地址，所以能准确拿到默认路由网卡。
     * 比按 NetworkInterface 枚举顺序猜要可靠得多（枚举顺序在 Windows 上常把
     * VMware / Hyper-V 虚拟网卡排在真实 WLAN 前面）。
     */
    static String egress(String probe) {
        java.net.DatagramSocket s = null;
        try {
            s = new java.net.DatagramSocket();
            s.connect(InetAddress.getByName(probe), 53);
            InetAddress a = s.getLocalAddress();
            if (a == null || a.isLoopbackAddress() || a.isLinkLocalAddress()) return null;
            String ip = a.getHostAddress();
            int pct = ip.indexOf('%');
            if (pct > 0) ip = ip.substring(0, pct);
            return ip;
        } catch (Throwable ignored) {
            return null;
        } finally {
            if (s != null) {
                try {
                    s.close();
                } catch (Throwable ignored) {
                }
            }
        }
    }

    /** 默认路由上的 IPv4（真实局域网地址），无路由时回退枚举 */
    public static String primaryV4() {
        String ip = egress("223.5.5.5");
        if (ip != null && ip.indexOf(':') < 0 && !isMesh(ip)) return ip;
        return null;
    }

    /** 默认路由上的全局 IPv6 */
    public static String primaryV6() {
        String ip = egress("2400:3200::1");
        if (ip != null && ip.indexOf(':') >= 0) return ip;
        return null;
    }

    /** 100.64.0.0/10 —— Tailscale / ZeroTier / 部分运营商 CGNAT */
    static boolean isMesh(String ip) {
        try {
            String[] s = ip.split("\\.");
            if (s.length != 4) return false;
            int a = Integer.parseInt(s[0]);
            int b = Integer.parseInt(s[1]);
            return a == 100 && b >= 64 && b <= 127;
        } catch (Throwable t) {
            return false;
        }
    }

    public static String lan() {
        String p = primaryV4();
        if (p != null) return p;
        for (Entry e : all()) if ("lan".equals(e.kind)) return e.ip;
        return null;
    }

    public static String v6() {
        String p = primaryV6();
        if (p != null) return p;
        for (Entry e : all()) if ("ipv6".equals(e.kind)) return e.ip;
        return null;
    }

    public static String mesh() {
        for (Entry e : all()) if ("mesh".equals(e.kind)) return e.ip;
        return null;
    }

    /** 10/8、172.16/12、192.168/16、169.254/16、127/8 —— 不可从公网直达 */
    static boolean isPrivateV4(String ip) {
        try {
            String[] s = ip.split("\\.");
            if (s.length != 4) return false;
            int a = Integer.parseInt(s[0]);
            int b = Integer.parseInt(s[1]);
            if (a == 10 || a == 127) return true;
            if (a == 172 && b >= 16 && b <= 31) return true;
            if (a == 192 && b == 168) return true;
            if (a == 169 && b == 254) return true;
            return false;
        } catch (Throwable t) {
            return true;
        }
    }

    /** 有没有真正可被公网访问的 IPv4（运营商 CGNAT 环境下通常没有） */
    public static String publicV4() {
        String p = primaryV4();
        if (p != null && !isPrivateV4(p)) return p;
        for (Entry e : all()) {
            if (!"lan".equals(e.kind)) continue;
            if (!isPrivateV4(e.ip)) return e.ip;
        }
        return null;
    }

    /** 地址归类：private / cgnat / public / ipv6 / mesh */
    public static String kindOf(String ip) {
        if (ip == null || ip.isEmpty()) return "none";
        if (ip.indexOf(':') >= 0) return "ipv6";
        if (isMesh(ip)) {
            // 100.64/10 既可能是组网虚拟 IP，也可能是运营商 CGNAT，这里统一标 cgnat+mesh
            return "mesh";
        }
        return isPrivateV4(ip) ? "private" : "public";
    }

    /** 把 IPv6 包成 URL 主机形式 */
    public static String host(String ip) {
        if (ip == null) return "127.0.0.1";
        return ip.indexOf(':') >= 0 ? "[" + ip + "]" : ip;
    }

    public static String baseUrl(String ip, int port) {
        return "http://" + host(ip) + ":" + port;
    }
}
