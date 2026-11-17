package top.yiqikan.app.server;

import android.util.Log;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.DatagramPacket;
import java.net.DatagramSocket;
import java.net.HttpURLConnection;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.net.URL;
import java.util.ArrayList;
import java.util.List;

/**
 * 极简 UPnP IGD 客户端（② 公网直连用）。
 *
 * <p>流程：SSDP M-SEARCH 找 IGD → 取 description XML → 找 WANIPConnection/WANPPPConnection
 * 的 controlURL → SOAP 调 GetExternalIPAddress / AddPortMapping / DeletePortMapping。
 * 只做 TCP 映射，够"一起看"用。
 */
public final class Upnp {

    private static final String TAG = "YiqikanLocal";
    private static final String ST_IP = "urn:schemas-upnp-org:service:WANIPConnection:1";
    private static final String ST_PPP = "urn:schemas-upnp-org:service:WANPPPConnection:1";

    public volatile String controlUrl;
    public volatile String serviceType;
    public volatile String externalIp;
    public volatile boolean mapped;
    public volatile int mappedPort;

    private String location;

    /** 搜索网关，成功返回 true */
    public boolean discover() {
        List<String> locations = ssdpSearch();
        for (String loc : locations) {
            try {
                String xml = httpGet(loc, 4000);
                if (xml == null) continue;
                String st = pickService(xml);
                if (st == null) continue;
                String ctrl = pickControlUrl(xml, st);
                if (ctrl == null) continue;
                location = loc;
                serviceType = st;
                controlUrl = absolute(loc, ctrl);
                Log.i(TAG, "UPnP IGD found: " + controlUrl + " type=" + st);
                return true;
            } catch (Throwable t) {
                Log.w(TAG, "UPnP parse fail: " + t);
            }
        }
        return false;
    }

    /** 读网关外网 IP */
    public String externalAddress() {
        if (controlUrl == null) return null;
        String body = "<?xml version=\"1.0\"?>\r\n"
                + "<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\" "
                + "s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\"><s:Body>"
                + "<u:GetExternalIPAddress xmlns:u=\"" + serviceType + "\"/>"
                + "</s:Body></s:Envelope>";
        String resp = soap("GetExternalIPAddress", body);
        if (resp == null) return null;
        String ip = extract(resp, "NewExternalIPAddress");
        if (ip != null && ip.length() > 0 && !"0.0.0.0".equals(ip)) {
            externalIp = ip;
        }
        return externalIp;
    }

    /** 打洞：把 internal:port 映射到同号外网端口 */
    public boolean addMapping(int port) {
        if (controlUrl == null && !discover()) return false;
        String internal = NetInfo.lan();
        if (internal == null) return false;
        String body = "<?xml version=\"1.0\"?>\r\n"
                + "<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\" "
                + "s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\"><s:Body>"
                + "<u:AddPortMapping xmlns:u=\"" + serviceType + "\">"
                + "<NewRemoteHost></NewRemoteHost>"
                + "<NewExternalPort>" + port + "</NewExternalPort>"
                + "<NewProtocol>TCP</NewProtocol>"
                + "<NewInternalPort>" + port + "</NewInternalPort>"
                + "<NewInternalClient>" + internal + "</NewInternalClient>"
                + "<NewEnabled>1</NewEnabled>"
                + "<NewPortDescription>yiqikan-local</NewPortDescription>"
                + "<NewLeaseDuration>0</NewLeaseDuration>"
                + "</u:AddPortMapping></s:Body></s:Envelope>";
        String resp = soap("AddPortMapping", body);
        boolean ok = resp != null && resp.indexOf("AddPortMappingResponse") >= 0;
        mapped = ok;
        if (ok) {
            mappedPort = port;
            externalAddress();
            Log.i(TAG, "UPnP mapped " + port + " -> " + internal + ":" + port + " ext=" + externalIp);
        } else {
            Log.w(TAG, "UPnP AddPortMapping rejected (router may block it)");
        }
        return ok;
    }

    public void removeMapping(int port) {
        if (controlUrl == null) return;
        String body = "<?xml version=\"1.0\"?>\r\n"
                + "<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\" "
                + "s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\"><s:Body>"
                + "<u:DeletePortMapping xmlns:u=\"" + serviceType + "\">"
                + "<NewRemoteHost></NewRemoteHost>"
                + "<NewExternalPort>" + port + "</NewExternalPort>"
                + "<NewProtocol>TCP</NewProtocol>"
                + "</u:DeletePortMapping></s:Body></s:Envelope>";
        soap("DeletePortMapping", body);
        mapped = false;
    }

    // ---------- 内部 ----------

    private List<String> ssdpSearch() {
        List<String> out = new ArrayList<String>();
        DatagramSocket s = null;
        try {
            s = new DatagramSocket();
            s.setSoTimeout(1200);
            String msg = "M-SEARCH * HTTP/1.1\r\n"
                    + "HOST: 239.255.255.250:1900\r\n"
                    + "MAN: \"ssdp:discover\"\r\n"
                    + "MX: 2\r\n"
                    + "ST: " + ST_IP + "\r\n\r\n";
            byte[] b = msg.getBytes("UTF-8");
            InetAddress group = InetAddress.getByName("239.255.255.250");
            for (int i = 0; i < 2; i++) {
                s.send(new DatagramPacket(b, b.length, group, 1900));
            }
            long deadline = System.currentTimeMillis() + 1500;
            byte[] buf = new byte[8192];
            while (System.currentTimeMillis() < deadline) {
                try {
                    DatagramPacket p = new DatagramPacket(buf, buf.length);
                    s.receive(p);
                    String text = new String(p.getData(), 0, p.getLength(), "UTF-8");
                    String loc = header(text, "location");
                    if (loc != null && !out.contains(loc)) out.add(loc);
                } catch (Throwable timeout) {
                    break;
                }
            }
        } catch (Throwable t) {
            Log.w(TAG, "SSDP failed: " + t);
        } finally {
            if (s != null) s.close();
        }
        Log.i(TAG, "SSDP candidates: " + out.size());
        return out;
    }

    private static String header(String resp, String name) {
        String lower = resp.toLowerCase();
        int i = lower.indexOf("\n" + name + ":");
        if (i < 0) return null;
        int start = resp.indexOf(':', i) + 1;
        int end = resp.indexOf('\n', start);
        if (end < 0) end = resp.length();
        return resp.substring(start, end).trim();
    }

    private static String pickService(String xml) {
        if (xml.contains(ST_IP)) return ST_IP;
        if (xml.contains(ST_PPP)) return ST_PPP;
        return null;
    }

    /** 取某个 service 块里的 controlURL */
    private static String pickControlUrl(String xml, String st) {
        int at = xml.indexOf(st);
        if (at < 0) return null;
        int end = xml.indexOf("</service>", at);
        if (end < 0) end = Math.min(xml.length(), at + 2000);
        String block = xml.substring(at, end);
        String c = extract(block, "controlURL");
        return c;
    }

    private static String extract(String xml, String tag) {
        String open = "<" + tag + ">";
        String close = "</" + tag + ">";
        int a = xml.indexOf(open);
        if (a < 0) {
            int b = xml.indexOf(":" + tag + ">");
            if (b < 0) return null;
            a = xml.lastIndexOf('<', b);
            int e2 = xml.indexOf("</", b);
            if (e2 < 0) return null;
            String v = xml.substring(xml.indexOf('>', b) + 1, e2);
            return v.trim();
        }
        int b = xml.indexOf(close, a);
        if (b < 0) return null;
        return xml.substring(a + open.length(), b).trim();
    }

    private static String absolute(String base, String rel) {
        try {
            URL b = new URL(base);
            return new URL(b, rel).toString();
        } catch (Throwable t) {
            return rel;
        }
    }

    private String soap(String action, String body) {
        HttpURLConnection c = null;
        try {
            c = (HttpURLConnection) new URL(controlUrl).openConnection();
            c.setRequestMethod("POST");
            c.setConnectTimeout(4000);
            c.setReadTimeout(6000);
            c.setDoOutput(true);
            c.setRequestProperty("Content-Type", "text/xml; charset=\"utf-8\"");
            c.setRequestProperty("SOAPACTION", "\"" + serviceType + "#" + action + "\"");
            byte[] b = body.getBytes("UTF-8");
            c.setFixedLengthStreamingMode(b.length);
            OutputStream os = c.getOutputStream();
            os.write(b);
            os.flush();
            os.close();
            int code = c.getResponseCode();
            InputStream in = code >= 400 ? c.getErrorStream() : c.getInputStream();
            if (in == null) return null;
            ByteArrayOutputStream bo = new ByteArrayOutputStream();
            byte[] buf = new byte[4096];
            int n;
            while ((n = in.read(buf)) > 0) bo.write(buf, 0, n);
            in.close();
            return bo.toString("UTF-8");
        } catch (Throwable t) {
            Log.w(TAG, "SOAP " + action + " failed: " + t);
            return null;
        } finally {
            if (c != null) c.disconnect();
        }
    }

    private static String httpGet(String url, int timeout) {
        HttpURLConnection c = null;
        try {
            c = (HttpURLConnection) new URL(url).openConnection();
            c.setConnectTimeout(timeout);
            c.setReadTimeout(timeout);
            c.setRequestProperty("User-Agent", "yiqikan-local/1.0 UPnP/1.1");
            if (c.getResponseCode() != 200) return null;
            InputStream in = c.getInputStream();
            ByteArrayOutputStream bo = new ByteArrayOutputStream();
            byte[] buf = new byte[8192];
            int n;
            while ((n = in.read(buf)) > 0) bo.write(buf, 0, n);
            in.close();
            return bo.toString("UTF-8");
        } catch (Throwable t) {
            return null;
        } finally {
            if (c != null) c.disconnect();
        }
    }
}
