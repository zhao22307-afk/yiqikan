package top.yiqikan.app.server;

import android.content.Context;
import android.util.Log;

import org.json.JSONArray;
import org.json.JSONObject;

/**
 * 七种建房方式（与重写方案里的 {@code ConnectMode} 一一对应）。
 *
 * <table>
 *   <tr><th>mode</th><th>要起的服务</th><th>给客人的地址</th></tr>
 *   <tr><td>lan</td><td>UDP 45231 广播 advertise</td><td>http://内网IP:8080</td></tr>
 *   <tr><td>direct</td><td>UPnP 打洞（或全局 IPv6）</td><td>http://公网IP:8080 / http://[v6]:8080</td></tr>
 *   <tr><td>cloud</td><td>无（走外部中继）</td><td>relay 配置值，未配则回落内网</td></tr>
 *   <tr><td>backend</td><td>无（连别人的后端）</td><td>external_backend 配置值</td></tr>
 *   <tr><td>embedded</td><td>本机后端（本服务即后端）</td><td>可达地址（同 direct 优先级）</td></tr>
 *   <tr><td>tunnel</td><td>本机后端 + 外部隧道</td><td>tunnel_url 配置值</td></tr>
 *   <tr><td>mesh</td><td>无广播（走组网虚拟 IP）</td><td>http://100.x:8080</td></tr>
 * </table>
 */
public final class Rooms {

    private static final String TAG = "YiqikanLocal";

    public static final String[] MODES = {
            "lan", "direct", "cloud", "backend", "embedded", "tunnel", "mesh"
    };
    public static final String[] LABELS = {
            "① 局域网", "② 公网直连", "③ 云房间", "④ 后端房间（外部后端）",
            "⑤ 后端房间（本机当后端）", "⑥ SSH 隧道", "⑦ 组网（Tailscale/ZeroTier）"
    };
    public static final String[] HINTS = {
            "同一 WiFi，开房后自动出现在「附近的房间」",
            "手机当服务器：IPv6 / UPnP 打洞，异地可用",
            "零配置，走外部中继地址（本机不暴露端口）",
            "用你自己部署的后端，房间里的人通过它同步",
            "手机自己当后端，不需要服务器，有公网地址即可",
            "手机当服务器，用 VPS 当入口，开房后把隧道地址发给对方",
            "双方装组网 App 加入同一网络，用虚拟 IP 直连"
    };

    private static final Upnp UPNP = new Upnp();

    private Rooms() {
    }

    public static Upnp upnp() {
        return UPNP;
    }

    public static String label(String mode) {
        for (int i = 0; i < MODES.length; i++) {
            if (MODES[i].equals(mode)) return LABELS[i];
        }
        return LABELS[0];
    }

    static String norm(String raw) {
        String m = raw == null ? "" : raw.toLowerCase().trim();
        if (m.isEmpty()) return "lan";
        if (m.equals("1") || m.equals("local") || m.equals("wifi")) return "lan";
        if (m.equals("2") || m.equals("public") || m.equals("ipv6")) return "direct";
        if (m.equals("3") || m.equals("relay")) return "cloud";
        if (m.equals("4") || m.equals("server")) return "backend";
        if (m.equals("5") || m.equals("local_backend") || m.equals("phone")) return "embedded";
        if (m.equals("6") || m.equals("ssh")) return "tunnel";
        if (m.equals("7") || m.equals("tailscale") || m.equals("zerotier")) return "mesh";
        for (String x : MODES) if (x.equals(m)) return m;
        return "lan";
    }

    /** 建房时调用：起该模式需要的服务，并把 join 信息写进 room */
    public static JSONObject apply(Context ctx, Store st, String code, JSONObject body, JSONObject room) {
        JSONObject out = new JSONObject();
        String mode = norm(body == null ? "" : body.optString("mode", body.optString("connect_mode", "")));
        try {
            out.put("mode", mode);
            out.put("label", label(mode));
            startFor(ctx, st, mode, code, room);
            JSONObject join = joinInfo(st, mode, code, room);
            out.put("join", join);
            out.put("join_url", join.optString("url", ""));
            out.put("join_text", join.optString("text", ""));
            if (room != null) {
                room.put("mode", mode);
                room.put("join_url", join.optString("url", ""));
            }
        } catch (Throwable t) {
            Log.w(TAG, "Rooms.apply failed: " + t);
        }
        return out;
    }

    private static void startFor(Context ctx, final Store st, String mode, final String code, JSONObject room) {
        try {
            if ("lan".equals(mode)) {
                // 起广播，让同网设备在「附近的房间」里看到
                JSONObject adv = new JSONObject();
                adv.put("id", code);
                adv.put("name", room == null ? "本地房间" : room.optString("name", room.optString("title", "本地房间")));
                adv.put("host", or(NetInfo.lan(), "127.0.0.1"));
                adv.put("port", LocalServer.PORT);
                adv.put("title", room == null ? "" : room.optString("video_url", ""));
                adv.put("code", code);
                Discovery.get().advertise(adv);
            } else if ("direct".equals(mode) || "embedded".equals(mode)) {
                // 公网直连 / 本机当后端：尝试 UPnP（失败就算了，还有 IPv6）
                new Thread(new Runnable() {
                    public void run() {
                        try {
                            if (UPNP.discover()) UPNP.addMapping(LocalServer.PORT);
                        } catch (Throwable ignored) {
                        }
                    }
                }, "yiqikan-upnp").start();
            } else if ("mesh".equals(mode)) {
                // 组网：不广播，等对方手填虚拟 IP
                Discovery.get().stopAdvertise();
            }
        } catch (Throwable t) {
            Log.w(TAG, "startFor " + mode + " failed: " + t);
        }
    }

    /** 对外可用的地址，优先级：显式配置 > 隧道 > 公网IP(UPnP) > IPv6 > 组网 > 内网 */
    public static JSONObject joinInfo(Store st, String mode, String code, JSONObject room) throws Exception {
        JSONObject j = new JSONObject();
        String url;
        String why;

        if ("backend".equals(mode)) {
            String b = or(st.externalBackend, "");
            url = b.isEmpty() ? NetInfo.baseUrl(or(NetInfo.lan(), "127.0.0.1"), LocalServer.PORT) : trimSlash(b);
            why = b.isEmpty() ? "未配置外部后端，回落内网地址" : "外部后端";
        } else if ("cloud".equals(mode)) {
            String r = or(st.relay, "");
            url = r.isEmpty() ? NetInfo.baseUrl(or(NetInfo.lan(), "127.0.0.1"), LocalServer.PORT) : trimSlash(r);
            why = r.isEmpty() ? "未配置云中继，回落内网地址" : "云中继";
        } else if ("tunnel".equals(mode)) {
            String t = or(st.tunnelUrl, "");
            url = t.isEmpty() ? NetInfo.baseUrl(or(NetInfo.lan(), "127.0.0.1"), LocalServer.PORT) : trimSlash(t);
            why = t.isEmpty() ? "未配置隧道地址，回落内网地址" : "SSH 隧道";
        } else if ("mesh".equals(mode)) {
            String m = or(st.meshIp, "");
            if (m.isEmpty()) m = NetInfo.mesh();
            url = m != null ? NetInfo.baseUrl(m, LocalServer.PORT)
                    : NetInfo.baseUrl(or(NetInfo.lan(), "127.0.0.1"), LocalServer.PORT);
            why = m != null ? "组网虚拟 IP" : "未发现组网地址，回落内网";
        } else if ("direct".equals(mode) || "embedded".equals(mode)) {
            if (UPNP.mapped && UPNP.externalIp != null) {
                url = "http://" + UPNP.externalIp + ":" + LocalServer.PORT;
                why = "UPnP 已映射到公网";
            } else if (NetInfo.v6() != null) {
                url = NetInfo.baseUrl(NetInfo.v6(), LocalServer.PORT);
                why = "全局 IPv6 直连";
            } else {
                url = NetInfo.baseUrl(or(NetInfo.lan(), "127.0.0.1"), LocalServer.PORT);
                why = "无公网地址（IPv6/UPnP 都不可用），回落内网";
            }
        } else {
            url = NetInfo.baseUrl(or(NetInfo.lan(), "127.0.0.1"), LocalServer.PORT);
            why = "同一 WiFi";
        }

        j.put("url", url);
        j.put("code", or(code, ""));
        j.put("mode", mode);
        j.put("reason", why);
        j.put("text", "让对方在「设置 → 服务器」填 " + url + " ，再「加入」输房间码 " + or(code, ""));
        JSONArray alts = new JSONArray();
        for (NetInfo.Entry e : NetInfo.all()) {
            JSONObject x = new JSONObject();
            x.put("kind", e.kind);
            x.put("ip", e.ip);
            x.put("iface", e.iface);
            x.put("url", NetInfo.baseUrl(e.ip, LocalServer.PORT));
            alts.put(x);
        }
        j.put("alternatives", alts);

        // D26：给客户端一份"能直接连的通道"列表 —— lan 项是 host+port，tunnel 项是 url，
        // 客户端按 id 分支解析。隧道没配置是正常状态，不塞占位地址。
        JSONArray addrs = buildAddrs(st);
        j.put("addrs", addrs);
        Log.i(TAG, "[YQK-CH] addrs n=" + addrs.length()
                + " tunnel=" + (or(st.tunnelUrl, "").length() > 0));
        return j;
    }

    /**
     * D26：把"能直接连的通道"拼成一份列表。lanAddrs 给局域网项，隧道配了才追加一项。
     * joinInfo（建房/分享）和房间详情接口共用这一份，别留两份实现。
     */
    public static JSONArray buildAddrs(Store st) {
        JSONArray addrs = LocalServer.lanAddrs(LocalServer.PORT);
        String tun = or(st.tunnelUrl, "");
        if (tun.length() > 0) {
            JSONObject t = new JSONObject();
            try {
                t.put("id", "tunnel");
                t.put("name", "隧道");
                t.put("url", trimSlash(tun));
                addrs.put(t);
            } catch (org.json.JSONException e) {
                Log.w(TAG, "[YQK-CH] build tunnel addr fail " + e);
            }
        }
        return addrs;
    }

    /** 房间可用地址列表（/local/net） */
    public static JSONObject netJson() throws Exception {
        JSONObject o = new JSONObject();
        o.put("success", true);
        o.put("port", LocalServer.PORT);
        o.put("discovery_port", Discovery.PORT);
        o.put("discovery_running", Discovery.get().isRunning());
        o.put("primary_v4", NetInfo.primaryV4());
        o.put("primary_v6", NetInfo.primaryV6());
        o.put("lan", NetInfo.lan());
        o.put("ipv6", NetInfo.v6());
        o.put("mesh", NetInfo.mesh());
        o.put("upnp_mapped", UPNP.mapped);
        o.put("upnp_external", UPNP.externalIp);
        JSONArray arr = new JSONArray();
        for (NetInfo.Entry e : NetInfo.all()) {
            JSONObject x = new JSONObject();
            x.put("ip", e.ip);
            x.put("iface", e.iface);
            x.put("kind", e.kind);
            x.put("url", NetInfo.baseUrl(e.ip, LocalServer.PORT));
            arr.put(x);
        }
        o.put("addresses", arr);
        return o;
    }

    /** 七种模式清单（/local/modes） */
    public static JSONObject modesJson(Store st) throws Exception {
        JSONObject o = new JSONObject();
        o.put("success", true);
        JSONArray arr = new JSONArray();
        for (int i = 0; i < MODES.length; i++) {
            JSONObject m = new JSONObject();
            m.put("mode", MODES[i]);
            m.put("index", i + 1);
            m.put("label", LABELS[i]);
            m.put("hint", HINTS[i]);
            try {
                m.put("url", joinInfo(st, MODES[i], "", null).optString("url", ""));
            } catch (Throwable ignored) {
                m.put("url", "");
            }
            arr.put(m);
        }
        o.put("items", arr);
        o.put("modes", arr);
        o.put("total", arr.length());
        String dm = st == null || st.defaultMode == null ? "" : st.defaultMode;
        o.put("default_mode", dm);
        o.put("needs_choice", dm.isEmpty());
        o.put("choose_url", "http://127.0.0.1:" + LocalServer.PORT + "/local/choose");
        return o;
    }

    // ============================================================ E8 六层优先级

    /** 一层的 JSON 形状：和 02 §5.2 的 modes 对齐（join_url + ready），另给 url 别名。 */
    private static JSONObject layer(String id, String name, String url) {
        JSONObject o = new JSONObject();
        try {
            o.put("id", id);
            o.put("name", name);
            o.put("url", url);
            o.put("join_url", url);
            o.put("ready", true);
        } catch (org.json.JSONException ignored) {
        }
        return o;
    }

    /** 没上的层：一定要带 reason，不许静默跳过。 */
    private static JSONObject miss(String id, String reason) {
        JSONObject o = new JSONObject();
        try {
            o.put("id", id);
            o.put("ready", false);
            o.put("reason", reason);
        } catch (org.json.JSONException ignored) {
        }
        return o;
    }

    /**
     * E8：六层地址优先级（explicit → tunnel → upnp → ipv6 → mesh → lan），
     * 外加 relay 这一层（cloud 模式用，没 VPS 时未配置）。
     *
     * <p>返回 {"primary": {...}, "ranked": [...], "skipped": [{"id","reason"}]}。
     * ranked 只放就绪的层，顺序即优先级；skipped 每层一条，说明为什么没上。
     *
     * @param prefer 客户端的优先通道策略（auto/lanOnly/forceTunnel/ipv6Only 或层 id）
     */
    public static JSONObject pickAddr(Store st, String roomCode, String prefer) {
        JSONArray ranked = new JSONArray();
        JSONArray skipped = new JSONArray();
        JSONObject room = st == null || roomCode == null || roomCode.isEmpty()
                ? null : st.findRoom(roomCode);
        String pref = prefer == null ? "" : prefer.trim();

        // 1 explicit：房间设置里手填的地址
        String explicit = "";
        if (room != null) {
            JSONObject set = room.optJSONObject("settings");
            if (set != null) explicit = or(set.optString("url", ""), "").trim();
        }
        if (explicit.isEmpty()) {
            skipped.put(miss("explicit", "房间设置里没填指定地址"));
        } else {
            ranked.put(layer("explicit", "指定地址", trimSlash(explicit)));
        }

        // 2 tunnel
        String tun = or(st == null ? "" : st.tunnelUrl, "").trim();
        if (tun.isEmpty()) {
            skipped.put(miss("tunnel", "隧道没起来（cloudflared 未启动）"));
        } else {
            ranked.put(layer("tunnel", "隧道", trimSlash(tun)));
        }

        // 2.5 relay：cloud 模式，没配置就跳过（E9 骨架，未验证）
        String relay = or(st == null ? "" : st.relay, "").trim();
        if (relay.isEmpty()) {
            skipped.put(miss("relay", "未配置中继"));
        } else {
            ranked.put(layer("relay", "中继", trimSlash(relay)));
        }

        // 3 upnp
        String up = UPNP.mapped ? or(UPNP.externalIp, "").trim() : "";
        if (up.isEmpty()) {
            skipped.put(miss("upnp", "路由器未接受映射（可能不支持 UPnP）"));
        } else {
            ranked.put(layer("upnp", "公网直连", NetInfo.baseUrl(up, LocalServer.PORT)));
        }

        // 4 ipv6：NetInfo.v6() 已经排除了链路本地与 mesh 段
        String v6 = NetInfo.v6();
        if (v6 == null || v6.isEmpty()) {
            skipped.put(miss("ipv6", "没有全局 IPv6 地址"));
        } else {
            ranked.put(layer("ipv6", "IPv6", NetInfo.baseUrl(v6, LocalServer.PORT)));
        }

        // 5 mesh：组网虚拟 IP（Tailscale/ZeroTier），本轮只读配置
        String mesh = st == null ? "" : or(st.meshIp, "");
        if (mesh == null) mesh = "";
        if (mesh.isEmpty()) {
            String auto = NetInfo.mesh();
            mesh = auto == null ? "" : auto;
        }
        mesh = mesh.trim();
        if (mesh.isEmpty()) {
            skipped.put(miss("mesh", "未发现组网地址（Tailscale/ZeroTier 未启用）"));
        } else {
            ranked.put(layer("mesh", "组网", NetInfo.baseUrl(mesh, LocalServer.PORT)));
        }

        // 6 lan
        String lan = NetInfo.lan();
        if (lan == null || lan.isEmpty()) {
            skipped.put(miss("lan", "没有内网地址"));
        } else {
            ranked.put(layer("lan", "局域网", NetInfo.baseUrl(lan, LocalServer.PORT)));
        }

        // prefer → primary：这一层就绪就用它，否则用 ranked 第一条
        String want = "";
        if ("forceTunnel".equals(pref) || "tunnel".equals(pref)) want = "tunnel";
        else if ("lanOnly".equals(pref) || "lan".equals(pref)) want = "lan";
        else if ("ipv6Only".equals(pref) || "ipv6".equals(pref)) want = "ipv6";

        JSONObject primary = null;
        if (!want.isEmpty()) {
            for (int i = 0; i < ranked.length(); i++) {
                JSONObject x = ranked.optJSONObject(i);
                if (x != null && want.equals(x.optString("id", ""))) {
                    primary = x;
                    break;
                }
            }
        }
        if (primary == null && ranked.length() > 0) primary = ranked.optJSONObject(0);

        JSONObject out = new JSONObject();
        try {
            out.put("primary", primary == null ? JSONObject.NULL : primary);
            out.put("ranked", ranked);
            out.put("skipped", skipped);
            out.put("prefer", pref);
        } catch (org.json.JSONException ignored) {
        }

        StringBuilder ids = new StringBuilder();
        for (int i = 0; i < ranked.length(); i++) {
            if (i > 0) ids.append(',');
            JSONObject x = ranked.optJSONObject(i);
            ids.append(x == null ? "" : x.optString("id", ""));
        }
        StringBuilder sk = new StringBuilder();
        for (int i = 0; i < skipped.length(); i++) {
            if (i > 0) sk.append(';');
            JSONObject x = skipped.optJSONObject(i);
            sk.append(x == null ? "" : x.optString("id", "") + ":" + x.optString("reason", ""));
        }
        Log.i(TAG, "[YQK-CH] pick room=" + or(roomCode, "") + " primary="
                + (primary == null ? "none" : primary.optString("id", ""))
                + " ranked=" + ids + " skipped=" + sk);
        return out;
    }

    static String trimSlash(String s) {
        String x = s.trim();
        while (x.endsWith("/")) x = x.substring(0, x.length() - 1);
        return x;
    }

    static String or(String a, String b) {
        return a == null || a.isEmpty() ? b : a;
    }
}
