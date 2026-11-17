package top.yiqikan.app.server;

import android.content.Context;
import android.util.Log;

import org.json.JSONArray;
import org.json.JSONObject;

import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.Iterator;
import java.util.Locale;

/**
 * 全部本地端点。
 *
 * 设计原则：
 *  1) 任何未实现的路径都返回 200 + 空结构，避免 Dart 端 jsonDecode 崩溃；
 *  2) 需要鉴权的端点认 Bearer token，也认 X-Device-Id（App 的封禁主键）；
 *  3) 房间同步同时写内存并 HTTP/WS 双通道广播，保证"一起看"可用。
 */
public final class Api {

    public static final String VER = "1.0.0";
    public static final String VER_MIN = "1.0.0";

    private Api() {
    }

    /**
     * 发版时间：取本机安装/更新时间，不写死常量。
     * 原包在此处硬编码 2026-11-01 12:41:21（旧软件的发版日期）；
     * 本地化后没有远程发版动作，改用本机 APK 的安装时间作为真实发版时间。
     */
    static String releaseDate(Context ctx) {
        long t = 0L;
        try {
            t = ctx.getPackageManager().getPackageInfo(ctx.getPackageName(), 0).lastUpdateTime;
        } catch (Throwable ignored) {
        }
        if (t <= 0L) {
            t = System.currentTimeMillis();
        }
        return new SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).format(new Date(t));
    }


    // ---------------------------------------------------------------- 小工具

    static JSONObject o() {
        return new JSONObject();
    }

    static void put(JSONObject o, String k, Object v) {
        try {
            o.put(k, v);
        } catch (Throwable ignored) {
        }
    }

    static String pick(String a, String b) {
        if (a != null && !a.trim().isEmpty()) return a.trim();
        if (b != null && !b.trim().isEmpty()) return b.trim();
        return "";
    }

    static JSONObject ok() {
        JSONObject o = o();
        put(o, "success", true);
        return o;
    }

    static JSONObject fail(String msg) {
        JSONObject o = o();
        put(o, "success", false);
        put(o, "detail", msg);
        put(o, "message", msg);
        return o;
    }

    static JSONObject emptyList() {
        JSONObject o = o();
        put(o, "success", true);
        put(o, "items", new JSONArray());
        put(o, "data", new JSONArray());
        put(o, "total", 0);
        put(o, "page", 1);
        put(o, "has_more", false);
        return o;
    }

    /**
     * 精简模式：去掉登录/会员/社交/运营位。
     *
     *  - 登录：任意输入（含空）都直接进入固定本地账号，不再有注册/校验/找回密码
     *  - 会员：恒为永久 VIP，所有权益解锁，支付端点直接回"无需购买"
     *  - 社交：/api/social/* 一律返回合法空结构（红点计数为 0）
     *  - 运营位：公告、动态 UI、推广、问卷、表情商店、卖家全部返回空
     */
    public static final boolean LEAN = true;

    /** 固定本地账号：免登录模式下的唯一用户 */
    static final String LEAN_EMAIL = "local@local";
    static final String LEAN_NICK = "本机用户";
    static final String LEAN_VIP_UNTIL = "2099-12-31T23:59:59";

    /** 各字段齐全的空结构，保证任何解析路径都不崩 */
    static JSONObject leanEmpty() {
        JSONObject o = ok();
        put(o, "items", new JSONArray());
        put(o, "data", new JSONArray());
        put(o, "list", new JSONArray());
        put(o, "records", new JSONArray());
        put(o, "results", new JSONArray());
        put(o, "total", 0);
        put(o, "count", 0);
        put(o, "unread", 0);
        put(o, "unread_count", 0);
        put(o, "page", 1);
        put(o, "pages", 0);
        put(o, "has_more", false);
        put(o, "popup", JSONObject.NULL);
        put(o, "lean", true);
        return o;
    }

    /** 精简模式的固定用户：不存在就建，字段补齐（永久 VIP、永不封禁） */
    static JSONObject leanUser(Store st) {
        JSONObject u = st.findUserByEmail(LEAN_EMAIL);
        if (u == null) u = st.createUser(LEAN_EMAIL, "local", LEAN_NICK);
        put(u, "is_vip", true);
        put(u, "vip", true);
        put(u, "vip_expire_at", LEAN_VIP_UNTIL);
        put(u, "banned", false);
        put(u, "lean", true);
        if (Store.str(u, "nickname").isEmpty()) put(u, "nickname", LEAN_NICK);
        return u;
    }

    static String bearer(LocalServer.Req r) {
        String a = r.header("authorization");
        if (a != null && a.length() > 7 && a.toLowerCase(Locale.US).startsWith("bearer ")) {
            return a.substring(7).trim();
        }
        String t = r.header("x-access-token");
        if (t != null && !t.isEmpty()) return t;
        return r.q("token", null);
    }

    /** 按登录用户的 user_id 找房间成员 id；找不到返回 null（HTTP 无鉴权路径用）。 */
    static String memberIdOf(JSONObject room, JSONObject user) {
        if (room == null || user == null) return null;
        Object uid = user.opt("id");
        JSONArray ms = room.optJSONArray("members");
        if (ms == null) return null;
        for (int i = 0; i < ms.length(); i++) {
            JSONObject m = ms.optJSONObject(i);
            if (m == null || m.optBoolean("kicked", false)) continue;
            if (uid != null && String.valueOf(uid).equals(String.valueOf(m.opt("user_id")))) {
                return Store.str(m, "id", null);
            }
        }
        return null;
    }

    static JSONObject auth(Store st, LocalServer.Req r) {        return st.findUserByToken(bearer(r));
    }

    /** 用户对外视图（去掉密码） */
    static JSONObject pub(JSONObject u) {
        JSONObject c = o();
        if (u == null) return c;
        Iterator<String> it = u.keys();
        while (it.hasNext()) {
            String k = it.next();
            if ("password".equals(k)) continue;
            put(c, k, u.opt(k));
        }
        return c;
    }

    static JSONObject tokenPayload(Store st, JSONObject u, String token) {
        JSONObject o = ok();
        put(o, "access_token", token);
        put(o, "token", token);
        put(o, "refresh_token", token);
        put(o, "token_type", "bearer");
        put(o, "expires_in", 86400 * 30);
        put(o, "is_new_user", false);
        put(o, "user", pub(u));
        put(o, "users", pub(u));
        put(o, "data", pub(u));
        return o;
    }

    static JSONObject userPayload(JSONObject u) {
        JSONObject o = o();
        put(o, "success", true);
        put(o, "user", pub(u));
        put(o, "data", pub(u));
        put(o, "profile", pub(u));
        if (u != null) {
            put(o, "id", u.opt("id"));
            put(o, "email", u.opt("email"));
            put(o, "nickname", u.opt("nickname"));
            put(o, "is_vip", u.opt("is_vip"));
            put(o, "points", u.opt("points"));
            put(o, "check_in_count", u.opt("check_in_count"));
            put(o, "checked_in_today", u.opt("checked_in_today"));
        }
        return o;
    }

    /** 从 /rooms/{code} 这类路径里取尾部 */
    /**
     * E6：取本机出口公网 IP。cloudflare 的 trace 端点是纯文本，最后一行是 ip=…。
     *
     * <p>必须在 handler 线程里同步跑：3s 连接 + 3s 读，最坏多占 6 秒，
     * 比"异步回调再拼 JSON"简单，也不会把端点变成 500。
     * 失败只记一条日志、返回 null，绝不抛。
     */
    static String reachPublicIp() {
        java.net.HttpURLConnection c = null;
        try {
            java.net.URL u = new java.net.URL("https://www.cloudflare.com/cdn-cgi/trace");
            c = (java.net.HttpURLConnection) u.openConnection();
            c.setConnectTimeout(3000);
            c.setReadTimeout(3000);
            c.setRequestProperty("User-Agent", "yiqikan-reach/1");
            int code = c.getResponseCode();
            if (code != 200) {
                Log.w(LocalServer.TAG, "[YQK-REACH] public ip fail HTTP " + code);
                return null;
            }
            java.io.BufferedReader br = new java.io.BufferedReader(
                    new java.io.InputStreamReader(c.getInputStream(), "UTF-8"));
            String line;
            String ip = null;
            while ((line = br.readLine()) != null) {
                if (line.startsWith("ip=")) {
                    ip = line.substring(3).trim();
                    break;
                }
            }
            br.close();
            if (ip == null || ip.isEmpty()) return null;
            return ip;
        } catch (Throwable t) {
            Log.w(LocalServer.TAG, "[YQK-REACH] public ip fail "
                    + t.getClass().getSimpleName() + " " + t.getMessage());
            return null;
        } finally {
            try {
                if (c != null) c.disconnect();
            } catch (Throwable ignored) {
            }
        }
    }

    /** 100.64.0.0/10：运营商级 NAT 段。解析不出来就当不是。 */
    static boolean isCgnat(String ip) {
        int[] q = quad(ip);
        if (q == null) return false;
        return q[0] == 100 && q[1] >= 64 && q[1] <= 127;
    }

    /** 10/8、172.16/12、192.168/16：私有段。 */
    static boolean isPrivateIp(String ip) {
        int[] q = quad(ip);
        if (q == null) return false;
        if (q[0] == 10) return true;
        if (q[0] == 172 && q[1] >= 16 && q[1] <= 31) return true;
        return q[0] == 192 && q[1] == 168;
    }

    static int[] quad(String ip) {
        if (ip == null) return null;
        String[] p = ip.trim().split("\\.");
        if (p.length != 4) return null;
        int[] q = new int[4];
        try {
            for (int i = 0; i < 4; i++) {
                q[i] = Integer.parseInt(p[i]);
                if (q[i] < 0 || q[i] > 255) return null;
            }
        } catch (Throwable t) {
            return null;
        }
        return q;
    }

    /** 默认出口网卡的 IPv4：不认网卡名，只看"能用"（非 loopback / 非 link-local）。 */
    static String reachDeviceIp() {
        try {
            java.util.Enumeration<java.net.NetworkInterface> ifs =
                    java.net.NetworkInterface.getNetworkInterfaces();
            while (ifs != null && ifs.hasMoreElements()) {
                java.net.NetworkInterface ni = ifs.nextElement();
                if (ni == null || !ni.isUp() || ni.isLoopback()) continue;
                java.util.Enumeration<java.net.InetAddress> addrs = ni.getInetAddresses();
                while (addrs != null && addrs.hasMoreElements()) {
                    java.net.InetAddress a = addrs.nextElement();
                    if (!(a instanceof java.net.Inet4Address)) continue;
                    String h = a.getHostAddress();
                    if (h == null || h.isEmpty()) continue;
                    if (h.startsWith("127.") || h.startsWith("169.254.")) continue;
                    return h;
                }
            }
        } catch (Throwable t) {
            Log.w(LocalServer.TAG, "[YQK-REACH] device ip fail "
                    + t.getClass().getSimpleName() + " " + t.getMessage());
        }
        return null;
    }

    static String tail(String path, String prefix) {
        String s = path.substring(prefix.length());
        if (s.startsWith("/")) s = s.substring(1);
        int slash = s.indexOf('/');
        if (slash >= 0) s = s.substring(0, slash);
        return s;
    }

    static String seg(String path, int idx) {
        String[] a = path.split("/");
        int n = 0;
        for (String s : a) {
            if (s.isEmpty()) continue;
            if (n == idx) return s;
            n++;
        }
        return "";
    }

    // ================================================================ 入口

    public static LocalServer.Res handle(Context ctx, LocalServer.Req r) {
        Store st = Store.get(ctx);
        String p = r.path;
        String m = r.method;
        boolean get = "GET".equals(m) || "HEAD".equals(m);

        try {
            // ---------- 自建诊断端点 ----------
            if (p.equals("/health")) {
                JSONObject o = ok();
                put(o, "service", "yiqikan-backend");
                put(o, "status", "ok");
                put(o, "version", VER);
                put(o, "port", LocalServer.PORT);
                put(o, "lan", LocalServer.lanIp());
                put(o, "users", st.users.size());
                put(o, "rooms", st.rooms.size());
                put(o, "ws", LocalServer.get(ctx).wsList.size());
                return LocalServer.Res.json(o);
            }
            if (p.equals("/local/status") || p.equals("/local")) {
                JSONObject o = ok();
                put(o, "lan", LocalServer.lanIp());
                put(o, "port", LocalServer.PORT);
                put(o, "endpoint", "http://" + LocalServer.lanIp() + ":" + LocalServer.PORT);
                put(o, "users", st.users.size());
                put(o, "rooms", st.rooms.size());
                put(o, "ws", LocalServer.get(ctx).wsList.size());
                put(o, "running", LocalServer.get(ctx).isRunning());
                put(o, "default_mode", st.defaultMode == null ? "" : st.defaultMode);
                put(o, "default_mode_label", st.defaultMode == null || st.defaultMode.isEmpty()
                        ? "未选择" : Rooms.label(st.defaultMode));
                put(o, "choose_url", "http://127.0.0.1:" + LocalServer.PORT + "/local/choose");
                return LocalServer.Res.json(o);
            }
            if (p.equals("/local/demo") || p.equals("/local/streams")) {
                JSONObject o = ok();
                JSONArray arr = new JSONArray();
                arr.put(stream("Big Buck Bunny", "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8", "https://peach.blender.org/wp-content/uploads/title_anouncement.jpg"));
                arr.put(stream("Tears of Steel", "https://test-streams.mux.dev/pts_shift/master.m3u8", ""));
                arr.put(stream("Sintel", "https://bitdash-a.akamaihd.net/content/sintel/hls/playlist.m3u8", ""));
                put(o, "items", arr);
                put(o, "data", arr);
                put(o, "total", arr.length());
                return LocalServer.Res.json(o);
            }

            // ---------- 七种建房方式 / 一起看 ----------
            if (p.equals("/local/net") || p.equals("/local/addresses")) {
                return LocalServer.Res.json(Rooms.netJson());
            }
            if (p.equals("/local/modes") || p.equals("/local/room_modes")
                    || p.equals("/local/connect_modes")) {
                return LocalServer.Res.json(Rooms.modesJson(st));
            }
            if (p.equals("/local/discover") || p.equals("/local/nearby")
                    || p.equals("/local/rooms/nearby")) {
                // 主动探测一次，房主会立刻回应
                Discovery.get().probe();
                try {
                    Thread.sleep(600);
                } catch (Throwable ignored) {
                }
                JSONObject o = ok();
                JSONArray arr = new JSONArray(Discovery.get().foundJson());
                put(o, "items", arr);
                put(o, "rooms", arr);
                put(o, "total", arr.length());
                put(o, "discovery_port", Discovery.PORT);
                put(o, "listening", Discovery.get().isRunning());
                return LocalServer.Res.json(o);
            }
            if (p.equals("/local/peer") || p.equals("/local/join")) {
                // I-82：这是调试用的转发开关，release 包不许开 —— 任何人都能改房主
                // 手机的转发目标。debug 包保留（探针要用）。
                if (!top.yiqikan.app.BuildConfig.DEBUG) {
                    JSONObject nf = o();
                    put(nf, "success", false);
                    put(nf, "detail", "not found");
                    LocalServer.Res res = LocalServer.Res.json(nf);
                    res.code = 404;
                    return res;
                }
                // 客人侧：把自己的请求转发到房主那台手机（支持 http/https，隧道域名也行）
                String ip = r.q("ip", r.q("url", r.json.optString("ip", r.json.optString("url", ""))));
                String clear = r.q("clear", r.json.optString("clear", ""));
                if (!clear.isEmpty()) {
                    st.peer = "";
                } else if (!ip.isEmpty()) {
                    String v = ip.trim();
                    while (v.endsWith("/")) v = v.substring(0, v.length() - 1);
                    st.peer = v;
                }
                st.save();
                LocalServer.Target t = LocalServer.parsePeer(st.peer);
                JSONObject o = ok();
                put(o, "peer", st.peer);
                put(o, "scheme", t.scheme);
                put(o, "host", t.host);
                put(o, "port", t.port);
                put(o, "tls", t.tls() ? Boolean.TRUE : Boolean.FALSE);
                put(o, "message", st.peer.isEmpty()
                        ? "已关闭转发，回到本机服务"
                        : ("已设置转发到 " + t.forLog() + (t.tls() ? "（TLS）" : "")));
                return LocalServer.Res.json(o);
            }

            // 异地自检：告诉用户这台机器能被哪种方式访问到
            if (p.equals("/local/reach") || p.equals("/local/diagnose")) {
                JSONObject o = ok();
                String lan = NetInfo.lan();
                String v6 = NetInfo.v6();
                String mesh = NetInfo.mesh();
                String pub4 = NetInfo.publicV4();
                Upnp u = Rooms.upnp();
                put(o, "port", LocalServer.PORT);
                put(o, "lan", lan);
                put(o, "lan_kind", NetInfo.kindOf(lan));
                put(o, "ipv6", v6);
                put(o, "mesh", mesh);
                put(o, "public_v4", pub4);
                put(o, "upnp_mapped", u.mapped ? Boolean.TRUE : Boolean.FALSE);
                put(o, "upnp_external", u.externalIp);
                put(o, "peer", st.peer);

                JSONArray addresses = new JSONArray();
                for (NetInfo.Entry e : NetInfo.all()) {
                    JSONObject x = o();
                    put(x, "ip", e.ip);
                    put(x, "iface", e.iface);
                    put(x, "kind", e.kind);
                    put(x, "reach_kind", NetInfo.kindOf(e.ip));
                    put(x, "url", NetInfo.baseUrl(e.ip, LocalServer.PORT));
                    addresses.put(x);
                }
                put(o, "addresses", addresses);

                JSONArray tips = new JSONArray();
                if (v6 != null) {
                    tips.put("② 公网直连（IPv6）：把这个地址发给对方 → http://[" + v6 + "]:"
                            + LocalServer.PORT + " （对方也要有 IPv6，且路由器/光猫要放行入站）");
                }
                if (pub4 != null || (u.mapped && u.externalIp != null)) {
                    tips.put("② 公网直连（IPv4+UPnP）：http://" + (u.mapped && u.externalIp != null ? u.externalIp : pub4)
                            + ":" + LocalServer.PORT);
                }
                if (mesh != null) {
                    tips.put("⑦ 组网：http://" + mesh + ":" + LocalServer.PORT
                            + " （双方都装 Tailscale/ZeroTier 并加入同一网络）");
                }
                tips.put("⑥ 隧道：电脑或手机跑 cloudflared tunnel --url http://127.0.0.1:" + LocalServer.PORT
                        + "，再把 https 域名填到 /local/peer?ip=https://你的域名");
                if (lan != null) {
                    tips.put("① 局域网：http://" + lan + ":" + LocalServer.PORT + " （同一 WiFi）");
                }
                put(o, "tips", tips);

                // E6 网络诊断：八键稳定输出（拿不到就给 null，不许缺键）。
                // lanIps 复用 LocalServer.lanAddrs() 的枚举（同一套跳过规则），不另写。
                JSONArray lanIps = new JSONArray();
                JSONArray la = LocalServer.lanAddrs(LocalServer.PORT);
                for (int i = 0; la != null && i < la.length(); i++) {
                    JSONObject x = la.optJSONObject(i);
                    String host = x == null ? null : x.optString("host", "");
                    if (host != null && !host.isEmpty()) lanIps.put(host);
                }
                String publicIp = reachPublicIp();
                boolean cgnat = isCgnat(publicIp);
                boolean priv = isPrivateIp(publicIp);
                String tunnel = (st.tunnelUrl == null || st.tunnelUrl.trim().isEmpty())
                        ? null : st.tunnelUrl.trim();
                String deviceIp = reachDeviceIp();
                put(o, "ok", Boolean.TRUE);
                put(o, "lanIps", lanIps);
                put(o, "publicIp", publicIp == null ? (Object) JSONObject.NULL : publicIp);
                put(o, "cgnat", cgnat ? Boolean.TRUE : Boolean.FALSE);
                put(o, "privateIp", priv ? Boolean.TRUE : Boolean.FALSE);
                put(o, "tunnelUrl", tunnel == null ? (Object) JSONObject.NULL : tunnel);
                put(o, "deviceIp", deviceIp == null ? (Object) JSONObject.NULL : deviceIp);
                Log.i(LocalServer.TAG, "[YQK-REACH] lan=" + lanIps.length()
                        + " public=" + (publicIp == null ? "null" : publicIp)
                        + " cgnat=" + cgnat
                        + " tunnel=" + (tunnel == null ? "no" : "yes"));
                return LocalServer.Res.json(o);
            }
            // DEV-ONLY: 验收用端点（assets/web/video_test.html + yqk_test.mp4）。
            // M10 前清理，或改成 BuildConfig.DEBUG 守卫。见 19 号 I-49。
            // D22 验收：把 assets/web/video_test.html 用 http 发出去。
            // 为什么要这条路由：WebView 里 file:// 文档拉 https 的 <video> 子资源会被拦
            // （net::ERR_FAILED），换成 http 文档就没这个问题。
            if (p.equals("/local/webasset") || p.equals("/local/video_test")) {
                java.io.InputStream in = null;
                try {
                    in = ctx.getAssets().open("flutter_assets/assets/web/video_test.html");
                    java.io.ByteArrayOutputStream bo = new java.io.ByteArrayOutputStream();
                    byte[] buf = new byte[4096];
                    int n;
                    while ((n = in.read(buf)) > 0) bo.write(buf, 0, n);
                    LocalServer.Res res = new LocalServer.Res();
                    res.type = "text/html; charset=utf-8";
                    res.body = bo.toByteArray();
                    return res;
                } catch (Throwable e) {
                    Log.w(LocalServer.TAG, "[YQK-WEB] webasset missing " + e);
                    return LocalServer.Res.json(404, "{\"ok\":false,\"error\":\"no asset\"}");
                } finally {
                    try {
                        if (in != null) in.close();
                    } catch (Throwable ignored) {
                    }
                }
            }
            // DEV-ONLY: 验收用端点（assets/web/video_test.html + yqk_test.mp4）。
            // M10 前清理，或改成 BuildConfig.DEBUG 守卫。见 19 号 I-49。
            // D22 验收：把验收页用到的 mp4 从本机文件发出去（同源播放，绕开
            // 「页面内跨源 <video> 一律 net::ERR_FAILED」这个 WebView 行为）。
            // 文件来源：/sdcard/Android/data/<pkg>/files/yqk_test.mp4（验收时 adb push）
            if (p.equals("/local/webvideo")) {
                java.io.File f = new java.io.File(ctx.getExternalFilesDir(null), "yqk_test.mp4");
                if (!f.isFile()) {
                    return LocalServer.Res.json(404, "{\"ok\":false,\"error\":\"no video\"}");
                }
                try {
                    byte[] all = new byte[(int) f.length()];
                    java.io.FileInputStream fi = new java.io.FileInputStream(f);
                    int off = 0;
                    while (off < all.length) {
                        int n = fi.read(all, off, all.length - off);
                        if (n <= 0) break;
                        off += n;
                    }
                    fi.close();
                    LocalServer.Res res = new LocalServer.Res();
                    res.type = "video/mp4";
                    // 支持 Range：WebView 的 <video> 拖进度条会发 Range 请求，
                    // 只会回 200 全量的服务器上，seek 会被忽略（currentTime 停在 0）。
                    String rng = r.header("range");
                    int start = 0;
                    int end = all.length - 1;
                    if (rng != null && rng.startsWith("bytes=")) {
                        String spec = rng.substring(6).trim();
                        int dash = spec.indexOf('-');
                        if (dash > 0) {
                            try {
                                start = Integer.parseInt(spec.substring(0, dash).trim());
                                String tail = spec.substring(dash + 1).trim();
                                if (!tail.isEmpty()) end = Integer.parseInt(tail);
                            } catch (Throwable ignored) {
                            }
                        } else if (dash == 0 && spec.length() > 1) {
                            try {
                                int n = Integer.parseInt(spec.substring(1).trim());
                                start = Math.max(0, all.length - n);
                            } catch (Throwable ignored) {
                            }
                        }
                        if (start < 0) start = 0;
                        if (end >= all.length) end = all.length - 1;
                        if (start > end) start = 0;
                        int len = end - start + 1;
                        byte[] part = new byte[len];
                        System.arraycopy(all, start, part, 0, len);
                        res.code = 206;
                        res.body = part;
                        res.headers.put("Content-Range",
                                "bytes " + start + "-" + end + "/" + all.length);
                    } else {
                        res.body = all;
                    }
                    res.headers.put("Accept-Ranges", "bytes");
                    return res;
                } catch (Throwable e) {
                    return LocalServer.Res.json(500, "{\"ok\":false,\"error\":\"read\"}");
                }
            }
            if (p.equals("/local/features") || p.equals("/local/feature_flags")) {
                String v = r.q("voice", null);
                if (v == null && "POST".equals(m) && r.json != null && r.json.has("voice")) {
                    v = r.json.optString("voice", "");
                }
                if (v != null && !v.isEmpty()) {
                    st.voiceEnabled = !("0".equals(v) || "false".equalsIgnoreCase(v) || "off".equalsIgnoreCase(v));
                    Log.i(LocalServer.TAG, "[YQK-FEAT] voiceEnabled=" + st.voiceEnabled);
                }
                JSONObject o = new JSONObject();
                o.put("ok", true);
                o.put("voiceEnabled", st.voiceEnabled);
                return LocalServer.Res.json(o);
            }
            if (p.equals("/local/settings") || p.equals("/local/server_config")) {
                String acc = r.header("accept");
                boolean wantsHtml = acc != null && acc.indexOf("html") >= 0;
                boolean wantJson = "1".equals(r.q("json", "")) || "json".equals(r.q("format", ""))
                        || "1".equals(r.q("raw", "")) || !wantsHtml;
                JSONObject src = "POST".equals(m) ? mergeJson(r.json, formObj(r)) : new JSONObject();
                String relay = pick(src.optString("relay", ""), r.q("relay", ""));
                String backend = pick(src.optString("external_backend", src.optString("backend", "")),
                        r.q("external_backend", r.q("backend", "")));
                String tunnel = pick(src.optString("tunnel_url", src.optString("tunnel", "")),
                        r.q("tunnel_url", r.q("tunnel", "")));
                String mesh = pick(src.optString("mesh_ip", src.optString("mesh", "")),
                        r.q("mesh_ip", r.q("mesh", "")));
                String peer = pick(src.optString("peer", ""), r.q("peer", ""));
                String defMode = pick(src.optString("default_mode", src.optString("mode", "")),
                        r.q("default_mode", ""));
                boolean posted = "POST".equals(m);
                boolean postBody = posted && r.json != null;
                if (posted || postBody || src.has("relay") || r.q("relay", null) != null) st.relay = relay.trim();
                if (posted || postBody || src.has("external_backend") || src.has("backend")
                        || r.q("external_backend", null) != null || r.q("backend", null) != null) {
                    st.externalBackend = backend.trim();
                }
                if (posted || postBody || src.has("tunnel_url") || src.has("tunnel")
                        || r.q("tunnel_url", null) != null || r.q("tunnel", null) != null) {
                    st.tunnelUrl = tunnel.trim();
                }
                if (posted || postBody || src.has("mesh_ip") || src.has("mesh")
                        || r.q("mesh_ip", null) != null || r.q("mesh", null) != null) {
                    st.meshIp = mesh.trim();
                }
                if (posted || postBody || src.has("peer") || r.q("peer", null) != null) st.peer = peer.trim();
                if (src.has("default_mode") || src.has("mode")
                        || r.q("default_mode", null) != null || r.q("mode", null) != null) {
                    String dm = Rooms.norm(defMode);
                    st.defaultMode = "".equals(defMode.trim()) ? "" : dm;
                }
                if ("1".equals(r.q("clear", "")) || src.optBoolean("clear", false)) {
                    st.relay = "";
                    st.externalBackend = "";
                    st.tunnelUrl = "";
                    st.meshIp = "";
                    st.peer = "";
                }
                st.save();
                if (wantJson) {
                    JSONObject o = ok();
                    put(o, "relay", st.relay);
                    put(o, "external_backend", st.externalBackend);
                    put(o, "tunnel_url", st.tunnelUrl);
                    put(o, "mesh_ip", st.meshIp);
                    put(o, "peer", st.peer);
                    put(o, "default_mode", st.defaultMode);
                    put(o, "modes", Rooms.modesJson(st).optJSONArray("items"));
                    return LocalServer.Res.json(o);
                }
                return LocalServer.Res.text(settingsHtml(st, posted), "text/html; charset=utf-8");
            }
            if (p.equals("/local/upnp") || p.equals("/local/punch")) {
                Upnp u = Rooms.upnp();
                boolean okMap = false;
                try {
                    okMap = u.discover() && u.addMapping(LocalServer.PORT);
                } catch (Throwable ignored) {
                }
                JSONObject o = ok();
                put(o, "discovered", u.controlUrl != null);
                put(o, "mapped", okMap);
                put(o, "external_ip", u.externalIp);
                put(o, "port", LocalServer.PORT);
                put(o, "message", okMap
                        ? "路由器已开放端口 " + LocalServer.PORT
                        : "路由器未接受映射（可能不支持 UPnP，改用 IPv6 或隧道）");
                return LocalServer.Res.json(o);
            }

            // ---------- quick tunnel 控制 ----------
            // /local/tunnel?on=1  start, ?on=0  stop, no arg  returns current state.
            if (p.equals("/local/tunnel")) {
                TunnelManager tm = TunnelManager.get(ctx);
                String on = r.q("on", "");
                // port 只在诊断自检失败路径时用（正常调用不带，默认 LocalServer.PORT）
                int port = LocalServer.PORT;
                String ps = r.q("port", "");
                if (!ps.isEmpty()) {
                    try {
                        port = Integer.parseInt(ps);
                    } catch (Throwable ignored) {
                        port = LocalServer.PORT;
                    }
                }
                if ("1".equals(on)) {
                    tm.start(port);
                } else if ("0".equals(on)) {
                    tm.stop();
                }
                JSONObject o = ok();
                put(o, "state", tm.state());
                String tu = tm.url();
                put(o, "url", tu == null ? (Object) JSONObject.NULL : tu);
                String te = tm.lastError();
                put(o, "last_error", te == null ? (Object) JSONObject.NULL : te);
                put(o, "port", port);
                return LocalServer.Res.json(o);
            }

            // ---------- E7 DDNS ----------
            // GET  ?json=1 读状态；POST host=&provider=&token= 写配置并立刻更新一次
            if (p.equals("/local/ddns")) {
                boolean posted = "POST".equals(m);
                JSONObject src = posted && r.json != null ? r.json : o();
                String host = pick(src.optString("host", ""), r.q("host", ""));
                String provider = pick(src.optString("provider", ""), r.q("provider", ""));
                String token = pick(src.optString("token", ""), r.q("token", ""));
                if (posted) {
                    String pv = provider.trim().toLowerCase();
                    if (!pv.isEmpty() && !"duckdns".equals(pv)) {
                        // TODO: noip（Basic Auth）/ custom（自己 CNAME 到隧道）
                        JSONObject no = fail("unsupported provider");
                        return LocalServer.Res.json(no);
                    }
                    String oldHost = st.ddnsHost;
                    st.ddnsHost = host.trim();
                    st.ddnsProvider = pv.isEmpty() ? "duckdns" : pv;
                    st.ddnsToken = token.trim();
                    if (!st.ddnsHost.equals(oldHost)) {
                        st.ddnsLastIp = "";
                        st.ddnsLastResult = "";
                    }
                    st.save();
                    final Store fst = st;
                    final Context fctx = ctx;
                    Thread t = new Thread(new Runnable() {
                        @Override
                        public void run() {
                            Ddns.updateNow(fctx, fst);
                        }
                    }, "yqk-ddns-now");
                    t.setDaemon(true);
                    t.start();
                    Log.i(LocalServer.TAG, "[YQK-DDNS] set host=" + st.ddnsHost
                            + " provider=" + st.ddnsProvider + " token=" + (st.ddnsToken.isEmpty() ? "" : "***"));
                }
                JSONObject o2 = ok();
                put(o2, "host", st.ddnsHost);
                put(o2, "provider", st.ddnsProvider);
                put(o2, "lastUpdate", st.ddnsLastAt);
                put(o2, "lastIp", st.ddnsLastIp);
                put(o2, "lastResult", st.ddnsLastResult);
                put(o2, "running", Ddns.get(ctx).isRunning());
                return LocalServer.Res.json(o2);
            }

            // ---------- E9 relay 控制（骨架：没有 VPS 时只回状态） ----------
            if (p.equals("/local/relay")) {
                if ("POST".equals(m)) {
                    JSONObject src = r.json != null ? r.json : o();
                    String rurl = pick(src.optString("url", ""), r.q("url", ""));
                    String rtok = pick(src.optString("token", ""), r.q("token", ""));
                    st.relay = rurl.trim();
                    st.relayToken = rtok.trim();
                    st.save();
                    Relay.get(ctx).configure(st.relay, st.relayToken);
                    Log.i(LocalServer.TAG, "[YQK-RELAY] set url=" + st.relay
                            + " token=" + (st.relayToken.isEmpty() ? "" : "***"));
                }
                Relay rl = Relay.get(ctx);
                JSONObject o3 = ok();
                put(o3, "configured", rl.configured());
                put(o3, "connected", rl.connected());
                put(o3, "url", rl.url());
                put(o3, "lastError", rl.lastError());
                put(o3, "attempts", rl.attempts());
                return LocalServer.Res.json(o3);
            }

            // ---------- H11 房间回放：只读内存录制，不落盘 ----------
            if (p.equals("/local/replay")) {
                String rcode = r.q("code", "").trim();
                int limit = 200;
                try {
                    limit = Math.max(1, Math.min(2000, Integer.parseInt(r.q("limit", "200"))));
                } catch (Throwable ignored) {
                }
                if (rcode.isEmpty()) {
                    JSONObject bad = fail("code 必填");
                    LocalServer.Res rbad = LocalServer.Res.json(bad);
                    rbad.code = 400;
                    return rbad;
                }
                JSONArray items = new JSONArray();
                java.util.Deque<JSONObject> dq = LocalServer.REC.get(rcode);
                int total = 0;
                if (dq != null) {
                    synchronized (dq) {
                        total = dq.size();
                        int skip = Math.max(0, total - limit);
                        int i = 0;
                        for (JSONObject row : dq) {
                            if (i++ < skip) continue;
                            items.put(new JSONObject(row.toString()));
                        }
                    }
                }
                JSONObject or = ok();
                put(or, "code", rcode);
                put(or, "count", items.length());
                put(or, "total", total);
                put(or, "items", items);
                Log.i(LocalServer.TAG, "[YQK-REC] replay code=" + rcode
                        + " count=" + items.length() + " total=" + total);
                return LocalServer.Res.json(or);
            }

            // ---------- E10 F13 活动页（dynamic_ui）：只读 Android assets ----------
            // 原包是 GET /api/dynamic_ui/{id}；本机版读 assets/dynamic/<id>.json，
            // 不复制到私有目录（任务书要求），也不联网。
            if (p.equals("/local/dynamic/list")) {
                JSONArray arr = new JSONArray();
                try {
                    String[] names = ctx.getAssets().list("dynamic");
                    if (names != null) {
                        java.util.Arrays.sort(names);
                        for (String n : names) {
                            if (n.endsWith(".json")) arr.put(n);
                        }
                    }
                } catch (Exception e) {
                    Log.w(LocalServer.TAG, "[YQK-DYN] list fail " + e);
                }
                JSONObject ol = ok();
                put(ol, "items", arr);
                put(ol, "count", arr.length());
                return LocalServer.Res.json(ol);
            }
            if (p.equals("/local/dynamic")) {
                String id = r.q("id", "");
                if (id == null || id.isEmpty()) {
                    return LocalServer.Res.json(fail("missing id"));
                }
                // 只允许 assets/dynamic/ 下的普通文件名，挡住 ../ 之类
                if (!id.matches("[A-Za-z0-9_-]{1,64}")) {
                    return LocalServer.Res.json(fail("bad id"));
                }
                String body = null;
                try {
                    java.io.InputStream in = ctx.getAssets().open("dynamic/" + id + ".json");
                    java.io.ByteArrayOutputStream bo = new java.io.ByteArrayOutputStream();
                    byte[] buf = new byte[8192];
                    int n;
                    while ((n = in.read(buf)) > 0) {
                        bo.write(buf, 0, n);
                    }
                    in.close();
                    body = new String(bo.toByteArray(), "UTF-8");
                } catch (Exception e) {
                    Log.i(LocalServer.TAG, "[YQK-DYN] asset miss id=" + id);
                    LocalServer.Res nf = LocalServer.Res.json(fail("这个活动不存在或已下线"));
                    nf.code = 404;
                    return nf;
                }
                Log.i(LocalServer.TAG, "[YQK-DYN] asset id=" + id + " len=" + body.length());
                LocalServer.Res res = LocalServer.Res.json(200, body);
                res.headers.put("Access-Control-Allow-Origin", "*");
                return res;
            }

            // ---------- C 组：DLNA 接收端（本机当 MediaRenderer） ----------
            // 只在房主房间内打开（Dart 侧调 /local/dlna/renderer?on=1），退房关掉。
            if (p.equals("/dlna/desc.xml")) {
                LocalServer.Res res = LocalServer.Res.text(
                        DlnaRenderer.get(ctx).descXml(), "text/xml; charset=utf-8");
                res.headers.put("Access-Control-Allow-Origin", "*");
                return res;
            }
            if (p.equals("/dlna/avt.xml")) {
                return LocalServer.Res.text(DlnaRenderer.get(ctx).avtScpdXml(),
                        "text/xml; charset=utf-8");
            }
            if (p.equals("/dlna/control")) {
                String sa = r.header("soapaction");
                String out = DlnaRenderer.get(ctx).control(
                        sa == null ? "" : sa, r.body == null ? "" : r.body);
                LocalServer.Res res = LocalServer.Res.text(out, "text/xml; charset=utf-8");
                res.headers.put("EXT", "");
                return res;
            }
            if (p.equals("/dlna/pending")) {
                DlnaRenderer dr = DlnaRenderer.get(ctx);
                JSONObject o4 = ok();
                JSONObject c = dr.poll();
                put(o4, "cmd", c == null ? (Object) JSONObject.NULL : c);
                put(o4, "running", dr.isRunning());
                put(o4, "lastUri", dr.lastUri());
                return LocalServer.Res.json(o4);
            }
            if (p.equals("/local/dlna/renderer")) {
                DlnaRenderer dr = DlnaRenderer.get(ctx);
                String on = r.q("on", "1");
                boolean wantOn = !("0".equals(on) || "false".equalsIgnoreCase(on));
                if (wantOn) dr.start(pick(r.q("name", ""), "一起看"));
                else dr.stop();
                JSONObject o5 = ok();
                put(o5, "running", dr.isRunning());
                put(o5, "name", dr.friendlyName());
                put(o5, "loc", dr.location());
                Log.i(LocalServer.TAG, "[YQK-DLNA] renderer on=" + (wantOn ? 1 : 0)
                        + " running=" + dr.isRunning() + " name=" + dr.friendlyName());
                return LocalServer.Res.json(o5);
            }

            // ---------- D 组：局域网媒体库 ----------
            if (p.equals("/local/media")) {
                String dir = pick(r.q("path", ""), "/sdcard/Movies");
                java.io.File d = new java.io.File(dir);
                String perm = android.os.Build.VERSION.SDK_INT >= 33
                        ? "android.permission.READ_MEDIA_VIDEO"
                        : "android.permission.READ_EXTERNAL_STORAGE";
                boolean granted = ctx.checkSelfPermission(perm)
                        == android.content.pm.PackageManager.PERMISSION_GRANTED;
                if (!granted) {
                    JSONObject o6 = fail("permission denied");
                    put(o6, "need", perm);
                    put(o6, "path", dir);
                    Log.i(LocalServer.TAG, "[YQK-MEDIA] permission denied need=" + perm);
                    return LocalServer.Res.json(o6);
                }
                if (!d.isDirectory()) {
                    JSONObject o6 = fail("not a directory");
                    put(o6, "path", dir);
                    return LocalServer.Res.json(o6);
                }
                JSONArray items = new JSONArray();
                // E6 B 组：子目录单独给一份，客户端要能点进去（items 结构保持 E3 的形状不变）
                JSONArray dirs = new JSONArray();
                java.io.File[] files = d.listFiles();
                if (files != null) {
                    for (java.io.File f : files) {
                        if (f.isDirectory()) {
                            String dn = f.getName();
                            if (dn.startsWith(".")) continue;
                            JSONObject dit = o();
                            put(dit, "name", dn);
                            put(dit, "path", f.getAbsolutePath());
                            dirs.put(dit);
                            continue;
                        }
                        if (!f.isFile()) continue;
                        String n = f.getName();
                        String lower = n.toLowerCase(java.util.Locale.US);
                        if (!(lower.endsWith(".mp4") || lower.endsWith(".mkv") || lower.endsWith(".ts")
                                || lower.endsWith(".avi") || lower.endsWith(".flv"))) continue;
                        JSONObject it = o();
                        put(it, "name", n);
                        put(it, "path", f.getAbsolutePath());
                        put(it, "size", f.length());
                        put(it, "mtime", f.lastModified());
                        items.put(it);
                    }
                }
                JSONObject o6 = ok();
                put(o6, "path", dir);
                put(o6, "parent", d.getParent() == null ? "" : d.getParent());
                put(o6, "count", items.length());
                put(o6, "dirCount", dirs.length());
                put(o6, "items", items);
                put(o6, "dirs", dirs);
                Log.i(LocalServer.TAG, "[YQK-MEDIA] list path=" + dir + " n=" + items.length()
                        + " dirs=" + dirs.length());
                return LocalServer.Res.json(o6);
            }
            if (p.equals("/local/media/play")) {
                String path = r.q("path", "");
                java.io.File f = new java.io.File(path);
                if (path.isEmpty() || !f.isFile()) {
                    return LocalServer.Res.json(404, "{\"success\":false,\"detail\":\"no such file\"}");
                }
                long total = f.length();
                long start = 0;
                long end = total - 1;
                String range = r.header("range");
                boolean partial = false;
                if (range != null && range.startsWith("bytes=")) {
                    String spec = range.substring(6).trim();
                    int dash = spec.indexOf('-');
                    if (dash >= 0) {
                        String a = spec.substring(0, dash).trim();
                        String b = spec.substring(dash + 1).trim();
                        try {
                            if (!a.isEmpty()) {
                                start = Long.parseLong(a);
                                if (!b.isEmpty()) end = Long.parseLong(b);
                            } else if (!b.isEmpty()) {
                                // bytes=-N 表示"最后 N 字节"，不是"前 N 字节"
                                long n = Long.parseLong(b);
                                start = (n >= total) ? 0 : (total - n);
                                end = total - 1;
                            }
                        } catch (Throwable ignored) {
                        }
                        if (end >= total) end = total - 1;
                        if (start < 0) start = 0;
                        if (start <= end) partial = true;
                    }
                }
                long len = partial ? (end - start + 1) : total;
                LocalServer.Res res = new LocalServer.Res();
                res.code = partial ? 206 : 200;
                res.type = "video/*";
                res.headers.put("Accept-Ranges", "bytes");
                // 不要再手写 Content-Length：Res 写 body 时 LocalServer 已经按 body.length 发一次，
                // 两条同时存在会被 OkHttp/dio 判成 "The Content-Length header occurred more than once"
                if (partial) {
                    res.headers.put("Content-Range", "bytes " + start + "-" + end + "/" + total);
                }
                byte[] body = new byte[(int) len];
                java.io.RandomAccessFile raf = null;
                try {
                    raf = new java.io.RandomAccessFile(f, "r");
                    raf.seek(start);
                    raf.readFully(body);
                    res.body = body;
                } catch (Throwable t) {
                    Log.w(LocalServer.TAG, "[YQK-MEDIA] read fail " + t);
                    return LocalServer.Res.json(500, "{\"success\":false,\"detail\":\"read fail\"}");
                } finally {
                    try {
                        if (raf != null) raf.close();
                    } catch (Throwable ignored) {
                    }
                }
                Log.i(LocalServer.TAG, "[YQK-MEDIA] stream path=" + path
                        + " range=" + (partial ? (start + "-" + end) : "full") + " len=" + len
                        + (range != null && range.startsWith("bytes=-") ? " tail" : ""));
                return res;
            }

            // ---------- 建房方式选择页（浏览器 / WebView 入口） ----------
            if (p.equals("/local/choose") || p.equals("/local/mode") || p.equals("/local/room_mode")) {
                String sel = r.q("mode", "");
                if (!sel.isEmpty()) {
                    final String selMode = Rooms.norm(sel);
                    st.defaultMode = selMode;
                    JSONObject ext = null;
                    String target = r.q("code", "");
                    if (!target.isEmpty() && st.findRoom(target) != null) {
                        JSONObject b = o();
                        put(b, "mode", selMode);
                        ext = Rooms.apply(ctx, st, target, b, st.findRoom(target));
                    } else {
                        for (JSONObject room : st.allRooms()) {
                            String cur = room.optString("mode", "");
                            if (cur.isEmpty() || "pending".equals(cur)) {
                                JSONObject b = o();
                                put(b, "mode", selMode);
                                ext = Rooms.apply(ctx, st, room.optString("code", ""), b, room);
                            }
                        }
                    }
                    st.save();
                    if ("1".equals(r.q("json", "")) || r.path.startsWith("/local/mode") || r.path.startsWith("/local/room_mode")) {
                        JSONObject out = ok();
                        put(out, "default_mode", selMode);
                        put(out, "label", Rooms.label(selMode));
                        put(out, "applied", ext);
                        return LocalServer.Res.json(out);
                    }
                    StringBuilder done = new StringBuilder();
                    done.append("<!DOCTYPE html><html lang='zh-CN'><head><meta charset='utf-8'>")
                            .append("<meta name='viewport' content='width=device-width,initial-scale=1'>")
                            .append("<title>已选择</title>").append(CHOOSE_CSS).append("</head><body>")
                            .append("<div class='wrap'><div class='ok'>")
                            .append("<div class='mark'>&#10003;</div>")
                            .append("<div class='kicker'>已设置默认方式</div>")
                            .append("<h1 style='margin-top:10px'>").append(stripNo(Rooms.label(selMode))).append("</h1>")
                            .append("<div class='lead' style='margin-bottom:0'>以后建房默认用它；当前「待定」房间已按该方式重算连接地址。</div>")
                            .append("</div>")
                            .append("<a class='btn' href='/local/choose'>重新选择</a>")
                            .append("<a class='btn2' href='/local/rooms'>查看房间</a></div>")
                            .append("</body></html>");
                    return LocalServer.Res.text(done.toString(), "text/html; charset=utf-8");
                }

                String cur = st.defaultMode == null ? "" : st.defaultMode;
                String code = r.q("code", "");
                StringBuilder h = new StringBuilder();
                h.append("<!DOCTYPE html><html lang='zh-CN'><head><meta charset='utf-8'>")
                        .append("<meta name='viewport' content='width=device-width,initial-scale=1'>")
                        .append("<title>选择建房方式</title>")
                        .append(CHOOSE_CSS)
                        .append("</head><body>")
                        .append("<div class='kicker'>一起看 &middot; 本机服务</div>")
                        .append("<h1>朋友怎么连进来？</h1>")
                        .append("<div class='lead'>选一种通道。选定后本机所有房间的「客人要填的地址」按它计算，以后建房默认用它。</div>");
                if (!code.isEmpty()) {
                    h.append("<div class='chip'>房间 ").append(esc(code)).append("</div>");
                }
                if (cur.isEmpty()) {
                    h.append("<div class='chip warn'>尚未选择默认方式 · 首次建房会提示你选</div>");
                }
                for (int i = 0; i < Rooms.MODES.length; i++) {
                    String md = Rooms.MODES[i];
                    boolean on = md.equals(cur);
                    h.append("<a class='card").append(on ? " on" : "").append("' href='/local/choose?mode=")
                            .append(md);
                    if (!code.isEmpty()) h.append("&amp;code=").append(esc(code));
                    h.append("'>")
                            .append("<div class='badge'>").append(i + 1).append("</div>")
                            .append("<div class='body'><div class='t'>").append(stripNo(Rooms.LABELS[i]))
                            .append(on ? "<span class='now'>当前</span>" : "").append("</div>")
                            .append("<div class='h'>").append(Rooms.HINTS[i]).append("</div></div>")
                            .append("<div class='arrow'>&rsaquo;</div>")
                            .append("</a>");
                }
                h.append("<div class='line'></div>")
                        .append("<a class='btn2' href='/local/qr'>扫码加房（让对方扫二维码）</a>")
                        .append("<a class='btn2' href='/local/settings' style='margin-top:10px'>连接配置</a>")
                        .append("<div class='foot' style='margin-top:14px'>也可以从桌面图标「建房方式」进 App 选择。</div>")
                        .append("</body></html>");
                return LocalServer.Res.text(h.toString(), "text/html; charset=utf-8");
            }

            // ---------- 扫码加房 ----------
            if (p.equals("/local/qr") || p.equals("/local/qrcode")) {
                String code = r.q("code", "");
                if (code.isEmpty()) {
                    for (JSONObject room : st.allRooms()) code = room.optString("code", "");
                }
                JSONObject room = code.isEmpty() ? null : st.findRoom(code);
                String base = shareBase(st, code, room);
                if (base.endsWith("/")) base = base.substring(0, base.length() - 1);
                String joinUrl = code.isEmpty() ? base : base + "/r/" + code;
                int scale = 6;
                String svg = Qr.svg(joinUrl, scale, 4, "#0B0E14", "#FFFFFF");

                if ("1".equals(r.q("svg", "")) || "svg".equals(r.q("format", ""))) {
                    return LocalServer.Res.text(svg, "image/svg+xml; charset=utf-8");
                }
                if ("1".equals(r.q("json", "")) || "json".equals(r.q("format", ""))) {
                    JSONObject out = ok();
                    put(out, "code", code);
                    put(out, "url", joinUrl);
                    put(out, "mode", room == null ? st.defaultMode : room.optString("mode", ""));
                    put(out, "label", room == null ? "" : Rooms.label(room.optString("mode", "")));
                    put(out, "scale", scale);
                    put(out, "svg", svg);
                    return LocalServer.Res.json(out);
                }

                StringBuilder h = new StringBuilder();
                h.append("<!DOCTYPE html><html lang='zh-CN'><head><meta charset='utf-8'>")
                        .append("<meta name='viewport' content='width=device-width,initial-scale=1'>")
                        .append("<title>扫码加房</title>").append(CHOOSE_CSS)
                        .append("<style>")
                        .append(".qrbox{background:#fff;border-radius:18px;padding:16px;display:flex;justify-content:center;")
                        .append("box-shadow:0 12px 36px rgba(0,0,0,.45);margin:6px 0 18px}")
                        .append(".qrbox svg{width:100%;max-width:300px;height:auto;display:block}")
                        .append(".url{background:#12161F;border:1px solid #2E3646;border-radius:11px;padding:12px 13px;")
                        .append("font-size:13px;color:#C8D0DE;word-break:break-all;line-height:1.5}")
                        .append(".tip{font-size:12px;color:#7A8398;margin-top:10px;line-height:1.6}")
                        .append("</style></head><body>")
                        .append("<div class='kicker'>一起看 &middot; 本机服务</div>")
                        .append("<h1>扫码进房间</h1>")
                        .append("<div class='lead'>让对方用手机扫这个码，或者把下面的地址发给他。</div>");
                if (!code.isEmpty()) {
                    h.append("<div class='chip'>房间 ").append(esc(code)).append("</div>");
                }
                String mode = room == null ? "" : room.optString("mode", "");
                if (!mode.isEmpty()) {
                    h.append("<div class='chip'>通道 ").append(esc(stripNo(Rooms.label(mode)))).append("</div>");
                }
                h.append("<div class='qrbox'>").append(svg).append("</div>")
                        .append("<div class='url'>").append(esc(joinUrl)).append("</div>")
                        .append("<div class='tip'>同 WiFi 下对方直接能打开；异地请先按「连接配置」把隧道域名或组网 IP 填好，"
                                + "再回来扫这个码。</div>")
                        .append("<a class='btn' href='/local/choose'>选择建房方式</a>")
                        .append("<a class='btn2' href='/local/settings'>连接配置</a>")
                        .append("</body></html>");
                return LocalServer.Res.text(h.toString(), "text/html; charset=utf-8");
            }

            // ---------- 分享落地页 /r/<code> ----------
            // 扫码/微信里点开的那一页。只做两件事：1) 告诉人这是哪个房间；
            // 2) 给一个 yiqikan://room/{code}?addr=… 的按钮把 App 唤起。
            // 不做网页播放器（那是 B21 的另一期），所以这里不出现 <video>。
            if (p.startsWith("/r/")) {
                String code = p.substring(3);
                int qm = code.indexOf('?');
                if (qm >= 0) code = code.substring(0, qm);
                int hash = code.indexOf('#');
                if (hash >= 0) code = code.substring(0, hash);
                while (code.endsWith("/")) code = code.substring(0, code.length() - 1);
                code = code.trim().toUpperCase(Locale.US);

                JSONObject room = code.isEmpty() ? null : st.findRoom(code);
                StringBuilder h = new StringBuilder(4096);
                h.append("<!doctype html><html lang='zh-CN'><head><meta charset='utf-8'>")
                        .append("<meta name='viewport' content='width=device-width,initial-scale=1'>")
                        .append("<title>一起看 · 房间 ").append(esc(code)).append("</title>")
                        .append(CHOOSE_CSS).append("</head><body>");
                if (room == null) {
                    h.append("<div class='kicker'>一起看 &middot; 分享链接</div>")
                            .append("<h1>房间不存在或已关闭</h1>")
                            .append("<div class='lead'>这个房间码对应的房间已经不在了。让对方重新发一次分享链接，"
                                    + "或者把房间码告诉你，在 App 首页「加入房间」里手输。</div>")
                            .append("<a class='btn' href='/'>回到首页</a>")
                            .append("</body></html>");
                    return LocalServer.Res.text(h.toString(), "text/html; charset=utf-8");
                }

                // base 的取值顺序必须和 /local/qr 完全一致（同一个 shareBase()），
                // 否则落地页给的地址会和 App 里实际用的通道对不上。
                String base = shareBase(st, code, room);
                while (base.endsWith("/")) base = base.substring(0, base.length() - 1);

                String addr = android.net.Uri.encode(base);
                // 必须用 yiqikan://room/{code} 这一形：MainActivity.isRoomLink() 只放行
                // scheme=yiqikan && host=room（或 https://…/r/{code}），host 换成 join 会被
                // 静默丢掉，冷启动连 getInitialLink 都拿不到。addr 走 query 一并带过去。
                String deep = "yiqikan://room/" + code + "?addr=" + addr;
                String pageUrl = base + "/r/" + code;
                String mode = room.optString("mode", "");

                h.append("<div class='kicker'>一起看 &middot; 一起看片</div>")
                        .append("<h1>房间 ").append(esc(code)).append("</h1>")
                        .append("<div class='lead'>点下面的按钮进房间，和房主同步看片、聊天、发弹幕。</div>")
                        .append("<div class='chip'>房间 ").append(esc(code)).append("</div>");
                if (!mode.isEmpty()) {
                    h.append("<div class='chip'>通道 ").append(esc(stripNo(Rooms.label(mode)))).append("</div>");
                }
                // 落地页本身也放一张码：对方用另一台手机扫屏幕比点按钮更顺手（C-V4 要求有二维码）。
                try {
                    String svg = Qr.svg(pageUrl, 6, 4, "#0B0E14", "#FFFFFF");
                    if (svg != null && !svg.isEmpty()) {
                        h.append("<div class='qrbox'>").append(svg).append("</div>");
                    }
                } catch (Exception e) {
                    Log.w(LocalServer.TAG, "[YQK-SHARE] /r/ qr failed: " + e);
                }
                h.append("<a class='btn' href='").append(esc(deep)).append("'>打开 App 进房间</a>")
                        .append("<a class='btn2' id='cp' href='#' onclick='copyUrl();return false;'>复制链接</a>")
                        .append("<div class='url'>").append(esc(pageUrl)).append("</div>")
                        .append("<div class='tip'>没装 App 的话，让对方先装；同一 WiFi 下也可以直接用「局域网发现」。</div>")
                        .append("<script>function copyUrl(){var t=location.href;var d=document.createElement('textarea');")
                        .append("d.value=t;document.body.appendChild(d);d.select();try{document.execCommand('copy');}")
                        .append("catch(e){}document.body.removeChild(d);var b=document.getElementById('cp');")
                        .append("if(b){b.textContent='已复制';}}</script>")
                        .append("</body></html>");
                return LocalServer.Res.text(h.toString(), "text/html; charset=utf-8");
            }

            // ---------- 应用元信息 ----------
            if (p.equals("/api/app/latest")) {
                JSONObject o = ok();
                put(o, "version", VER);
                put(o, "min_version", VER_MIN);
                put(o, "is_force_update", 0);
                put(o, "system", "android");
                put(o, "release_date", releaseDate(ctx));
                put(o, "download_url", "http://" + LocalServer.lanIp() + ":" + LocalServer.PORT + "/local/apk");
                put(o, "description", "本地内置服务版本");
                return LocalServer.Res.json(o);
            }
            if (p.equals("/api/app/versions") || p.equals("/api/app/versions/")) {
                return LocalServer.Res.json(emptyList());
            }

            if (p.equals("/api/config")) {
                return LocalServer.Res.json(config(ctx, st));
            }

            if (p.equals("/api/dynamic_ui") || p.equals("/api/dynamic_ui/")) {
                // 运营位：不返回任何卡片/标签
                JSONObject o = leanEmpty();
                put(o, "sections", new JSONArray());
                put(o, "tabs", new JSONArray());
                put(o, "version", "1");
                put(o, "data", new JSONArray());
                return LocalServer.Res.json(o);
            }

            if (p.equals("/api/vip/info")) {
                // 会员：恒为永久 VIP，全部权益解锁
                JSONObject o = ok();
                put(o, "is_vip", true);
                put(o, "vip", true);
                put(o, "vip_level", 99);
                put(o, "vip_expire_at", LEAN_VIP_UNTIL);
                put(o, "expire_at", LEAN_VIP_UNTIL);
                put(o, "available_points", 99999);
                put(o, "points", 99999);
                put(o, "points_per_vip_day", 0);
                put(o, "is_forever", true);
                put(o, "need_pay", false);
                JSONArray benefits = new JSONArray();
                benefits.put("本地版：全部功能已解锁");
                benefits.put("多账号网盘：不限");
                benefits.put("一起看：不限房间/人数");
                benefits.put("Anime4K 超分：已开启");
                put(o, "benefits", benefits);
                put(o, "plans", new JSONArray());
                put(o, "products", new JSONArray());
                put(o, "detail", "本地版无需会员");
                return LocalServer.Res.json(o);
            }

            // ---------- 公告（运营位：恒空） ----------
            if (p.startsWith("/api/announcements") || p.startsWith("/announcements")) {
                return LocalServer.Res.json(leanEmpty());
            }

            // ---------- 认证（精简模式：免登录，任意输入直进固定账号） ----------
            if (p.equals("/register") || p.equals("/api/register") || p.equals("/auth/register")) {
                if (LEAN) {
                    JSONObject u = leanUser(st);
                    String t = st.issueToken(Store.str(u, "email"));
                    return LocalServer.Res.json(tokenPayload(st, u, t));
                }
                String email = Store.str(r.json, "email");
                String pwd = Store.str(r.json, "password");
                String nick = Store.str(r.json, "nickname");
                if (email.isEmpty() || pwd.isEmpty()) {
                    return LocalServer.Res.json(fail("邮箱或密码不能为空"));
                }
                if (st.findUserByEmail(email) != null) {
                    return LocalServer.Res.json(fail("该邮箱已注册"));
                }
                JSONObject u = st.createUser(email, pwd, nick);
                String t = st.issueToken(email);
                return LocalServer.Res.json(tokenPayload(st, u, t));
            }

            if (p.equals("/token") || p.equals("/auth/login") || p.equals("/api/auth/login")
                    || p.equals("/api/token") || p.equals("/login")) {
                if (LEAN) {
                    // 不校验邮箱/密码，输入什么都进同一个本地账号
                    JSONObject u = leanUser(st);
                    String dev = r.header("x-device-id");
                    if (dev != null && !dev.isEmpty()) put(u, "device_id", dev);
                    String t = st.issueToken(Store.str(u, "email"));
                    return LocalServer.Res.json(tokenPayload(st, u, t));
                }
                String email = Store.str(r.json, "email", Store.str(r.json, "username", ""));
                String pwd = Store.str(r.json, "password");
                JSONObject u = st.findUserByEmail(email);
                if (u == null) {
                    // 本地服务：首次登录自动注册，避免卡在注册页
                    if (email.isEmpty() || pwd.isEmpty()) {
                        return LocalServer.Res.json(fail("邮箱或密码不能为空"));
                    }
                    u = st.createUser(email, pwd, "");
                } else if (!pwd.equals(Store.str(u, "password"))) {
                    return LocalServer.Res.json(fail("邮箱或密码错误"));
                }
                if (u.optBoolean("banned", false)) {
                    return LocalServer.Res.json(fail("设备已被封禁: " + Store.str(u, "ban_reason")));
                }
                String dev = r.header("x-device-id");
                if (dev != null && !dev.isEmpty()) put(u, "device_id", dev);
                String t = st.issueToken(email);
                return LocalServer.Res.json(tokenPayload(st, u, t));
            }

            if (p.equals("/auth/refresh")) {
                JSONObject u = auth(st, r);
                if (u == null) return LocalServer.Res.json(fail("Not authenticated"));
                String t = st.issueToken(Store.str(u, "email"));
                return LocalServer.Res.json(tokenPayload(st, u, t));
            }

            if (p.equals("/auth/logout")) {
                st.revokeToken(bearer(r));
                return LocalServer.Res.json(ok());
            }

            if (p.equals("/send-verify-code") || p.equals("/login-with-code-request")) {
                JSONObject o = ok();
                put(o, "code", "000000");
                put(o, "verify_code", "000000");
                put(o, "detail", "本地服务：验证码固定 000000");
                return LocalServer.Res.json(o);
            }

            if (p.equals("/login-with-code") || p.equals("/api/login-with-code")) {
                String email = Store.str(r.json, "email");
                if (email.isEmpty()) return LocalServer.Res.json(fail("邮箱不能为空"));
                JSONObject u = st.findUserByEmail(email);
                if (u == null) u = st.createUser(email, "000000", "");
                String t = st.issueToken(email);
                return LocalServer.Res.json(tokenPayload(st, u, t));
            }

            if (p.equals("/reset-password")) {
                String email = Store.str(r.json, "email");
                String np = Store.str(r.json, "new_password");
                JSONObject u = st.findUserByEmail(email);
                if (u == null) return LocalServer.Res.json(fail("用户不存在"));
                put(u, "password", np);
                st.save();
                JSONObject o = ok();
                put(o, "message", "密码重置成功，请使用新密码登录");
                put(o, "detail", "密码重置成功，请使用新密码登录");
                return LocalServer.Res.json(o);
            }

            if (p.equals("/reset-password-request")) {
                JSONObject o = ok();
                put(o, "message", "验证码已发送（本地固定 000000）");
                put(o, "detail", "验证码已发送（本地固定 000000）");
                return LocalServer.Res.json(o);
            }

            // ---------- 用户 ----------
            if (p.startsWith("/users/me")) {
                JSONObject u = auth(st, r);
                if (u == null) return LocalServer.Res.json(fail("Not authenticated"));
                if (p.contains("/email/change")) {
                    if (p.endsWith("-request")) {
                        JSONObject o = ok();
                        put(o, "detail", "验证码固定 000000");
                        return LocalServer.Res.json(o);
                    }
                    String ne = Store.str(r.json, "new_email");
                    String old = Store.str(u, "email");
                    if (!ne.isEmpty()) {
                        st.users.remove(old);
                        put(u, "email", ne.toLowerCase(Locale.US));
                        st.users.put(ne.toLowerCase(Locale.US), u);
                        st.save();
                    }
                    return LocalServer.Res.json(userPayload(u));
                }
                return LocalServer.Res.json(userPayload(u));
            }

            // ---------- 番剧日历 ----------
            if (p.equals("/api/bangumi/calendar") || p.startsWith("/api/v2/bangumi")
                    || p.startsWith("/api/bangumi")) {
                JSONObject o = ok();
                JSONArray days = new JSONArray();
                String[] wd = {"Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"};
                for (String w : wd) {
                    JSONObject d = o();
                    put(d, "weekday", o());
                    JSONObject w2 = o();
                    put(w2, "en", w);
                    put(d, "weekday", w2);
                    put(d, "items", new JSONArray());
                    days.put(d);
                }
                put(o, "days", days);
                put(o, "items", new JSONArray());
                put(o, "total", 0);
                return LocalServer.Res.json(o);
            }

            // ---------- 搜索源 / 解析 ----------
            if (p.equals("/api/search_sources")) {
                JSONObject o = ok();
                JSONArray arr = new JSONArray();
                arr.put(src("demo", "本地示例流"));
                put(o, "items", arr);
                put(o, "sources", arr);
                put(o, "data", arr);
                put(o, "total", arr.length());
                return LocalServer.Res.json(o);
            }

            if (p.equals("/api/video/parse")) {
                JSONObject o = ok();
                String url = r.q("url", Store.str(r.json, "url"));
                put(o, "url", url);
                put(o, "video_url", url);
                put(o, "original_url", url);
                put(o, "headers", o());
                put(o, "success", true);
                put(o, "detail", "本地服务：直链原样返回，不做第三方解析");
                return LocalServer.Res.json(o);
            }

            if (p.equals("/rtc/ice-servers")) {
                // 全部指向内置 STUN（udp/3478），不再依赖 google 等外部 STUN
                Stun.start();
                return LocalServer.Res.text(Stun.iceServersJson(), "application/json; charset=utf-8");
            }

            // ---------- 签到 ----------
            if (p.startsWith("/api/check_in")) {
                return LocalServer.Res.json(checkIn(st, r, p));
            }

            // ---------- 支付（会员已全解锁，这里只回"无需购买"） ----------
            if (p.startsWith("/api/v2/payment") || p.startsWith("/api/orders") || p.startsWith("/api/order")) {
                JSONObject o = ok();
                put(o, "order_id", "local-0");
                put(o, "status", "paid");
                put(o, "paid_at", Store.nowIso());
                put(o, "amount", 0);
                put(o, "is_paid", true);
                put(o, "already_vip", true);
                put(o, "need_pay", false);
                put(o, "lean", true);
                JSONObject vi = ok();
                put(vi, "is_vip", true);
                put(vi, "vip_expire_at", LEAN_VIP_UNTIL);
                put(vi, "is_forever", true);
                put(o, "vip_info", vi);
                put(o, "detail", "本地版已解锁全部功能，无需购买");
                put(o, "message", "本地版已解锁全部功能，无需购买");
                put(o, "items", new JSONArray());
                put(o, "total", 0);
                return LocalServer.Res.json(o);
            }

            // ---------- 房间（一起看核心） ----------
            if (p.equals("/rooms") || p.equals("/rooms/") || p.equals("/rooms_new")
                    || p.equals("/rooms_new/") || p.equals("/api/rooms") || p.equals("/api/rooms/")) {
                if ("POST".equals(m)) {
                    // 参数缺失能 400 就别 500，更别让连接被重置（客户端分不清是网络还是参数错）
                    String vu0 = Store.str(r.json, "video_url", Store.str(r.json, "url", r.q("url", "")));
                    if (vu0 == null || vu0.trim().isEmpty()) {
                        return LocalServer.Res.json(400, "{\"ok\":false,\"error\":\"video_url 不能为空\"}");
                    }
                    // C1：审批制开关，默认关（只有显式 approval:true 才拦人）
                    r.json.put("approval", Boolean.valueOf(r.json.optBoolean("approval", false)));
                    JSONObject u = auth(st, r);
                    if (u == null) {
                        // 未登录建房：用请求里的 owner_name 兜一个，快照/成员列表要显示房主名
                        u = new JSONObject();
                        try {
                            u.put("id", Store.str(r.json, "owner_id", ""));
                            u.put("nickname", Store.str(r.json, "owner_name", Store.str(r.json, "name", "local")));
                        } catch (Throwable ignored) {
                        }
                    }
                    String code = st.newRoomCode();
                    JSONObject room = st.createRoom(code, r.json, u);

                    // 方式来源：请求显式指定 > 用户上次选择 > 未定（要提示选择）
                    String reqMode = Store.str(r.json, "mode", Store.str(r.json, "connect_mode", ""));
                    String mode = reqMode.isEmpty()
                            ? (st.defaultMode == null ? "" : st.defaultMode)
                            : Rooms.norm(reqMode);
                    boolean needsMode = mode.isEmpty() || "pending".equals(mode);

                    JSONObject body = o();
                    // E3 / I-72：未定方式时也要真的走 direct 分支（UPnP + IPv6），
                    // 否则 Rooms.startFor 的 direct|embedded 永远是死代码。
                    put(body, "mode", needsMode ? "direct" : mode);
                    JSONObject ext = Rooms.apply(ctx, st, code, body, room);
                    if (needsMode) {
                        put(room, "mode", "direct");
                        put(room, "join_url", ext.optString("join_url", ""));
                        st.save();
                    }

                    // E3：房间已落库就顺手起隧道。cloudflared 是 App 的子进程，
                    // 死了进程就没了，所以每次建房都得自己起（不能指望上次那条）。
                    try {
                        TunnelManager tm = TunnelManager.get(ctx);
                        String ts = tm.state();
                        if ("OFF".equals(ts) || "FAILED".equals(ts)) {
                            Log.i("YQK-TUN", "[YQK-TUN] auto start room=" + code
                                    + " port=" + LocalServer.PORT);
                            tm.start(LocalServer.PORT);
                        } else {
                            Log.i("YQK-TUN", "[YQK-TUN] auto start skip room=" + code
                                    + " state=" + ts);
                        }
                    } catch (Throwable t) {
                        Log.w("YQK-TUN", "[YQK-TUN] auto start fail " + t);
                    }

                    JSONObject o = ok();
                    put(o, "room", room);
                    // 房主身份：客户端拿这两个值握手就能复用 host 成员（不用再签一个 guest）
                    String hostId = room.optString("host", "");
                    put(o, "ownerMemberId", hostId);
                    String hostToken = "";
                    org.json.JSONArray hm = room.optJSONArray("members");
                    for (int hi = 0; hm != null && hi < hm.length(); hi++) {
                        org.json.JSONObject one = hm.optJSONObject(hi);
                        if (one != null && hostId.equals(one.optString("id", ""))) {
                            hostToken = one.optString("token", "");
                            break;
                        }
                    }
                    put(o, "memberToken", hostToken);
                    put(o, "data", room);
                    put(o, "room_code", code);
                    put(o, "code", code);
                    put(o, "mode", needsMode ? "direct" : ext.optString("mode", "lan"));
                    put(o, "mode_label", needsMode ? "待选择" : ext.optString("label", "① 局域网"));
                    put(o, "join_url", ext.optString("join_url", ""));
                    put(o, "join", ext.optJSONObject("join"));
                    put(o, "room_token", room.optString("room_token", ""));
                    put(o, "needs_mode", needsMode ? Boolean.TRUE : Boolean.FALSE);
                    if (needsMode) {
                        put(o, "choose_url", "http://127.0.0.1:" + LocalServer.PORT + "/local/choose");
                        put(o, "message", "房间创建成功，房间码: " + code + "（请选择建房方式）");
                        put(o, "detail", "房间创建成功，房间码: " + code + "（请选择建房方式）");
                    } else {
                        put(o, "message", "房间创建成功，房间码: " + code);
                        put(o, "detail", "房间创建成功，房间码: " + code);
                    }
                    broadcast(ctx, code, "created", room);
                    if (needsMode) {
                        try {
                            ChooseActivity.show(ctx, code);
                        } catch (Throwable ignored) {
                        }
                    }
                    return LocalServer.Res.json(o);
                }
                JSONArray arr = new JSONArray();
                for (JSONObject room : st.allRooms()) arr.put(room);
                JSONObject o = ok();
                put(o, "items", arr);
                put(o, "rooms", arr);
                put(o, "data", arr);
                put(o, "total", arr.length());
                return LocalServer.Res.json(o);
            }

            // 给已建好的房间补选/改选方式
            if ((p.startsWith("/rooms/") || p.startsWith("/api/rooms/"))
                    && (p.endsWith("/mode") || p.endsWith("/connect_mode"))) {
                String code = p.startsWith("/api/rooms/") ? p.substring(11) : p.substring(7);
                int cut = code.lastIndexOf('/');
                if (cut > 0) code = code.substring(0, cut);
                JSONObject room = st.findRoom(code);
                if (room == null) {
                    JSONObject o = o();
                    put(o, "detail", "room not found: " + code);
                    return LocalServer.Res.json(o);
                }
                String mm = Rooms.norm(Store.str(r.json, "mode", r.q("mode", "lan")));
                JSONObject b = o();
                put(b, "mode", mm);
                JSONObject ext = Rooms.apply(ctx, st, code, b, room);
                st.save();
                JSONObject out = ok();
                put(out, "mode", mm);
                put(out, "label", Rooms.label(mm));
                put(out, "join_url", ext.optString("join_url", ""));
                put(out, "join", ext.optJSONObject("join"));
                put(out, "room", room);
                broadcast(ctx, code, "mode", room);
                return LocalServer.Res.json(out);
            }

            if (p.startsWith("/rooms/") || p.startsWith("/rooms_new/") || p.startsWith("/api/rooms/")
                    || p.startsWith("/room/") || p.startsWith("/api/room/")) {
                JSONObject ro = roomOp(ctx, st, r, p);
                if (ro.optInt("code", 0) == 400) {
                    // C4：容量校验要真 400，不是 200 里带 code=400
                    return LocalServer.Res.json(400, ro.toString());
                }
                if (ro.optInt("code", 0) == 403) {
                    return LocalServer.Res.status(403, ro.optString("error", "Forbidden"));
                }
                return LocalServer.Res.json(ro);
            }

            // ---------- 社交（精简模式：整块关闭，只回合法空结构） ----------
            if (p.startsWith("/api/social")) {
                if (LEAN) {
                    return LocalServer.Res.json(leanEmpty());
                }
                return LocalServer.Res.json(social(ctx, st, r, p));
            }

            // ---------- 收藏 / 观看记录 / 评论 / 举报 ----------
            if (p.startsWith("/api/favorites")) {
                JSONObject u = auth(st, r);
                String email = u == null ? "anon" : Store.str(u, "email");
                JSONArray fav = st.favOf(email);
                JSONObject o = ok();
                put(o, "items", fav);
                put(o, "data", fav);
                put(o, "favorites", fav);
                put(o, "total", fav.length());
                if ("POST".equals(m) || "PUT".equals(m)) {
                    String vu = Store.str(r.json, "video_url", Store.str(r.json, "url", ""));
                    String title = Store.str(r.json, "title", Store.str(r.json, "name", vu));
                    if (!vu.isEmpty()) {
                        JSONObject f = o();
                        put(f, "id", fav.length() + 1);
                        put(f, "title", title);
                        put(f, "video_url", vu);
                        put(f, "url", vu);
                        put(f, "created_at", Store.nowIso());
                        fav.put(f);
                        st.save();
                        put(o, "item", f);
                    }
                }
                return LocalServer.Res.json(o);
            }

            if (p.startsWith("/api/watch")) {
                JSONObject u = auth(st, r);
                String email = u == null ? "anon" : Store.str(u, "email");
                JSONArray w = st.watchOf(email);
                String vu = Store.str(r.json, "video_url", Store.str(r.json, "url", r.q("url", "")));
                if (!vu.isEmpty() && ("POST".equals(m) || "PUT".equals(m))) {
                    JSONObject it = o();
                    put(it, "video_url", vu);
                    put(it, "url", vu);
                    put(it, "position", r.json.optInt("position", r.json.optInt("progress", 0)));
                    put(it, "duration", r.json.optInt("duration", 0));
                    put(it, "updated_at", Store.nowIso());
                    w.put(it);
                    st.save();
                }
                JSONObject o = ok();
                put(o, "items", w);
                put(o, "data", w);
                put(o, "stats", o());
                put(o, "total", w.length());
                return LocalServer.Res.json(o);
            }

            // ---------- 运营位/问卷/表情商店/卖家（精简模式全空） ----------
            if (p.startsWith("/api/reviews") || p.startsWith("/api/reports")
                    || p.startsWith("/api/survey") || p.startsWith("/api/user/answered_surveys")
                    || p.startsWith("/api/active_survey") || p.startsWith("/api/survey_answers")
                    || p.startsWith("/api/survey_dismiss") || p.startsWith("/api/survey_results")
                    || p.startsWith("/api/usage") || p.startsWith("/api/stickers")
                    || p.startsWith("/api/sellers") || p.startsWith("/api/seller")
                    || p.startsWith("/api/promotion") || p.startsWith("/admin/stickers")
                    || p.startsWith("/api/room/global-announcement")) {
                return LocalServer.Res.json(leanEmpty());
            }

            // ---------- 网盘 ----------
            if (p.startsWith("/api/netdisk")) {
                JSONObject o = ok();
                put(o, "items", new JSONArray());
                put(o, "credentials", new JSONArray());
                put(o, "files", new JSONArray());
                put(o, "total", 0);
                put(o, "detail", "本地服务未接入网盘");
                return LocalServer.Res.json(o);
            }

            // ---------- 管理端 ----------
            if (p.startsWith("/api/admin") || p.startsWith("/admin")) {
                JSONObject u = auth(st, r);
                if (u == null) {
                    LocalServer.Res res = LocalServer.Res.status(403, "Forbidden");
                    return res;
                }
                if (p.contains("config")) {
                    JSONObject o = ok();
                    put(o, "config", configMap(st));
                    return LocalServer.Res.json(o);
                }
                if (p.contains("device")) {
                    JSONObject o = ok();
                    put(o, "items", new JSONArray());
                    put(o, "bans", new JSONArray());
                    put(o, "total", 0);
                    return LocalServer.Res.json(o);
                }
                if (p.contains("rooms")) {
                    JSONArray arr = new JSONArray();
                    for (JSONObject room : st.allRooms()) arr.put(room);
                    JSONObject o = ok();
                    put(o, "items", arr);
                    put(o, "rooms", arr);
                    put(o, "total", arr.length());
                    return LocalServer.Res.json(o);
                }
                JSONObject o = ok();
                put(o, "items", new JSONArray());
                put(o, "total", 0);
                put(o, "config", configMap(st));
                put(o, "observability", o());
                return LocalServer.Res.json(o);
            }

            // ---------- 兜底 ----------
            // I-82：未实现的路径以前回 200 + local-stub，等于给扫描器一个"这里有个
            // 宽松服务"的指纹。改成标准 404（body 仍是合法 JSON，容忍的调用方不受影响）。
            JSONObject o = o();
            put(o, "success", false);
            put(o, "detail", "not found");
            put(o, "path", p);
            LocalServer.Res miss = LocalServer.Res.json(o);
            miss.code = 404;
            return miss;

        } catch (Throwable t) {
            JSONObject o = fail("local: " + t);
            LocalServer.Res res = LocalServer.Res.json(o);
            res.code = 200;
            return res;
        }
    }

    // ================================================================ 子模块

    static JSONObject stream(String title, String url, String cover) {
        JSONObject s = o();
        put(s, "title", title);
        put(s, "name", title);
        put(s, "url", url);
        put(s, "video_url", url);
        put(s, "cover", cover);
        put(s, "type", "hls");
        return s;
    }

    // --------------------------------------------------- 页面样式 / 文本助手

    static final String CHOOSE_CSS = "<style>"
            + "*{box-sizing:border-box}"
            + "html{background:#0B0E14;overflow-x:hidden}"
            + "body{margin:0 auto;max-width:640px;padding:26px 18px 40px;box-sizing:border-box;"
            + "overflow-x:hidden;"
            + "background:#0B0E14;color:#E9EDF5;"
            + "font:15px/1.6 -apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,'PingFang SC','Microsoft YaHei',sans-serif}"
            + ".kicker{font-size:11px;letter-spacing:.18em;color:#4DA3FF;font-weight:700}"
            + "h1{font-size:24px;margin:12px 0 8px;letter-spacing:-.01em}"
            + ".lead{color:#8B94A6;font-size:13px;margin:0 0 18px}"
            + ".chip{display:inline-block;padding:5px 12px;border-radius:20px;font-size:12px;font-weight:700;"
            + "color:#4DA3FF;background:rgba(77,163,255,.10);border:1px solid rgba(77,163,255,.33);margin-bottom:16px}"
            + ".chip.warn{color:#F0B45A;background:rgba(240,180,90,.10);border-color:rgba(240,180,90,.32)}"
            + "a.card{display:block;position:relative;width:auto;max-width:100%;box-sizing:border-box;overflow:hidden;text-decoration:none;color:inherit;"
            + "padding:15px 40px 15px 64px;margin-bottom:10px;border-radius:16px;border:1px solid #2E3646;"
            + "background:linear-gradient(135deg,#171C26,#131720);transition:border-color .15s,transform .15s}"
            + "a.card:hover{border-color:#3A6CFF;transform:translateY(-1px)}"
            + "a.card:active{background:linear-gradient(135deg,#1F2634,#19202C)}"
            + "a.card.on{border-color:#3A6CFF;box-shadow:0 0 0 1px rgba(58,108,255,.25)}"
            + ".badge{position:absolute;left:15px;top:50%;width:30px;height:30px;margin-top:-15px;border-radius:50%;display:flex;align-items:center;justify-content:center;"
            + "font-size:13px;font-weight:700;color:#fff;background:linear-gradient(135deg,#2A6BFF,#7B5CFF)}"
            + ".body{display:block;min-width:0}"
            + ".t{font-size:15px;font-weight:700;display:flex;align-items:center;flex-wrap:wrap;gap:8px;line-height:1.4}"
            + ".h{font-size:12px;color:#8B94A6;margin-top:5px;line-height:1.55;word-break:break-word}"
            + ".now{font-size:10px;font-weight:700;color:#4DA3FF;padding:2px 6px;border-radius:5px;"
            + "background:rgba(77,163,255,.12);border:1px solid rgba(77,163,255,.40)}"
            + ".arrow{position:absolute;right:13px;top:50%;margin-top:-13px;line-height:1;color:#6E788C;font-size:22px}"
            + "a.card.on .arrow{color:#4DA3FF}"
            + ".line{height:1px;background:#1B212C;margin:22px 0 14px}"
            + ".foot{color:#6B7486;font-size:11px}"
            + ".wrap{min-height:80vh;display:flex;flex-direction:column;justify-content:center}"
            + ".ok{text-align:center;margin-bottom:10px}"
            + ".ok .mark{width:66px;height:66px;margin:0 auto 18px;border-radius:50%;display:flex;"
            + "align-items:center;justify-content:center;font-size:32px;color:#fff;"
            + "background:linear-gradient(135deg,#2A6BFF,#7B5CFF)}"
            + ".btn{display:block;margin:22px 0 0;width:100%;box-sizing:border-box;text-align:center;text-decoration:none;"
            + "padding:13px;border-radius:14px;font-weight:700;color:#fff;"
            + "background:linear-gradient(135deg,#2A6BFF,#5B4BFF)}"
            + ".btn2{display:block;margin:10px 0 0;width:100%;box-sizing:border-box;text-align:center;text-decoration:none;"
            + "padding:13px;border-radius:14px;font-weight:700;color:#8B94A6;border:1px solid #242B39}"
            + "</style>";

    /**
     * 分享/扫码用的对外地址：隧道优先。
     *
     * <p>顺序：本房隧道地址 → 建房时记下的 join_url → joinInfo 现算的地址 → 内网。
     * 隧道排第一是因为分享链接是发给「不在同一个网里」的人：内网地址和 IPv6 直连
     * 对端多半打不开，只有 https://xxx.trycloudflare.com 是公网可达的。
     * 隧道没起来（tunnelUrl 为空）时逐级回落，行为和以前一致。
     */
    static String shareBase(Store st, String code, JSONObject room) {
        // E7：配了 DDNS 就用固定域名 —— quick tunnel 每启动一次就换 URL，
        // 域名才是能长期发出去的那个地址。
        String ddns = st == null ? "" : or(st.ddnsHost, "").trim();
        if (!ddns.isEmpty()) return "https://" + Rooms.trimSlash(ddns);
        String base = or(st.tunnelUrl, "").trim();
        if (!base.isEmpty()) return base;
        if (room == null) return "http://" + NetInfo.lan() + ":" + LocalServer.PORT;
        base = room.optString("join_url", "");
        if (!base.isEmpty()) return base;
        JSONObject ji = null;
        try {
            ji = Rooms.joinInfo(st, room.optString("mode", ""), code, room);
        } catch (Exception e) {
            Log.w(LocalServer.TAG, "[YQK-SHARE] shareBase joinInfo failed: " + e);
        }
        base = ji == null ? "" : ji.optString("url", "");
        if (!base.isEmpty()) return base;
        return "http://" + NetInfo.lan() + ":" + LocalServer.PORT;
    }

    static String esc(String s) {
        if (s == null) return "";
        return s.replace("&", "&amp;").replace("<", "&lt;")
                .replace(">", "&gt;").replace("\"", "&quot;");
    }

    /** 去掉「① 局域网」的前导圈号，序号交给徽标显示 */
    static String stripNo(String s) {
        if (s == null) return "";
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            if (Character.isLetter(c) || Character.isDigit(c)) return s.substring(i).trim();
        }
        return s;
    }

    // ------------------------------------------------------------ 配置中心

    static final String FORM_CSS = "<style>"
            + ".fld{margin-bottom:16px}"
            + ".fld .lb{font-size:13px;color:#C9D2E2;font-weight:600;margin-bottom:4px;display:block}"
            + ".fld .hp{font-size:11.5px;color:#7C8598;line-height:1.5;margin-bottom:7px}"
            + "input,select{width:100%;box-sizing:border-box;background:#12161F;color:#E9EDF5;"
            + "border:1px solid #2E3646;border-radius:11px;padding:12px 13px;font-size:14px;"
            + "font-family:inherit;outline:none;-webkit-appearance:none;appearance:none}"
            + "input:focus,select:focus{border-color:#3A6CFF;background:#151A25}"
            + "input::placeholder{color:#5C6478}"
            + "select{background-image:linear-gradient(45deg,transparent 50%,#6E788C 50%),"
            + "linear-gradient(135deg,#6E788C 50%,transparent 50%);"
            + "background-position:calc(100% - 18px) 16px,calc(100% - 13px) 16px;"
            + "background-size:5px 5px,5px 5px;background-repeat:no-repeat;padding-right:38px}"
            + ".ok2{border:1px solid rgba(58,180,120,.4);background:rgba(58,180,120,.10);"
            + "color:#5FD39A;border-radius:11px;padding:11px 13px;font-size:13px;margin-bottom:18px}"
            + ".info{border:1px solid #2E3646;background:#12161F;border-radius:12px;padding:13px 14px;"
            + "font-size:12px;color:#8B94A6;line-height:1.7;margin-bottom:20px}"
            + ".info b{color:#C9D2E2;font-weight:600}"
            + ".actions{display:flex;gap:10px;margin-top:22px}"
            + ".actions .btn,.actions .btn2{flex:1;margin:0;text-align:center}"
            + "</style>";

    static JSONObject formObj(LocalServer.Req r) {
        JSONObject o = new JSONObject();
        try {
            String ct = r.header("content-type");
            if (ct == null || ct.toLowerCase(java.util.Locale.US).indexOf("form") < 0) return o;
            String body = r.body == null ? "" : r.body;
            for (String pair : body.split("&")) {
                if (pair.isEmpty()) continue;
                int eq = pair.indexOf('=');
                String k = eq < 0 ? pair : pair.substring(0, eq);
                String v = eq < 0 ? "" : pair.substring(eq + 1);
                o.put(urlDec(k), urlDec(v));
            }
        } catch (Throwable ignored) {
        }
        return o;
    }

    static String urlDec(String s) {
        try {
            return java.net.URLDecoder.decode(s, "UTF-8");
        } catch (Throwable t) {
            return s;
        }
    }

    static JSONObject mergeJson(JSONObject a, JSONObject b) {
        JSONObject out = new JSONObject();
        try {
            if (a != null) {
                java.util.Iterator<String> it = a.keys();
                while (it.hasNext()) {
                    String k = it.next();
                    out.put(k, a.opt(k));
                }
            }
            if (b != null) {
                java.util.Iterator<String> it = b.keys();
                while (it.hasNext()) {
                    String k = it.next();
                    out.put(k, b.opt(k));
                }
            }
        } catch (Throwable ignored) {
        }
        return out;
    }

    static String field(String label, String hint, String name, String value, String placeholder) {
        return "<div class='fld'><label class='lb'>" + esc(label) + "</label>"
                + "<div class='hp'>" + esc(hint) + "</div>"
                + "<input name='" + esc(name) + "' value='" + esc(value) + "' placeholder='"
                + esc(placeholder) + "' autocomplete='off' autocapitalize='off' spellcheck='false'></div>";
    }

    static String settingsHtml(Store st, boolean saved) {
        StringBuilder h = new StringBuilder();
        h.append("<!DOCTYPE html><html lang='zh-CN'><head><meta charset='utf-8'>")
                .append("<meta name='viewport' content='width=device-width,initial-scale=1,viewport-fit=cover'>")
                .append("<title>本机服务设置</title>")
                .append(CHOOSE_CSS)
                .append(FORM_CSS)
                .append("</head><body>")
                .append("<div class='kicker'>一起看 &middot; 本机服务</div>")
                .append("<h1>连接配置</h1>")
                .append("<div class='lead'>房主填这边的地址，客人填「加入别人的房间」。留空就用内网地址。</div>");

        if (saved) {
            h.append("<div class='ok2'>已保存。下次建房按新配置算地址。</div>");
        }

        h.append("<div class='info'>")
                .append("<b>本机监听</b> http://").append(esc(or(NetInfo.lan(), "127.0.0.1")))
                .append(":").append(LocalServer.PORT)
                .append(" &middot; STUN udp/").append(Stun.PORT)
                .append(" &middot; 发现 udp/").append(Discovery.PORT)
                .append("<br><b>当前地址</b> ")
                .append(esc(or(NetInfo.lan(), "-"))).append(" / ")
                .append(esc(or(NetInfo.primaryV6(), "无 IPv6")))
                .append("</div>");

        h.append("<form method='post' action='/local/settings'>");

        // 默认建房方式
        h.append("<div class='fld'><label class='lb'>默认建房方式</label>")
                .append("<div class='hp'>建房时不再逐个问，直接用这个。</div>")
                .append("<select name='default_mode'>")
                .append("<option value=''").append(st.defaultMode.isEmpty() ? " selected" : "")
                .append(">未选择（首次建房会弹选择页）</option>");
        for (int i = 0; i < Rooms.MODES.length; i++) {
            String md = Rooms.MODES[i];
            h.append("<option value='").append(md).append("'")
                    .append(md.equals(st.defaultMode) ? " selected" : "").append(">")
                    .append(esc(Rooms.LABELS[i])).append("</option>");
        }
        h.append("</select></div>");

        h.append(field("加入别人的房间（对方地址）", "填房主给你的地址，如 192.168.1.5:8080 或 https://xxx.trycloudflare.com。填了之后所有请求都转给对方。",
                "peer", st.peer, "192.168.1.5:8080"));
        h.append(field("云房间中继地址", "③ 云房间用。你没部署中继就留空，会自动回落内网地址。",
                "relay", st.relay, "http://relay.example.com:9000"));
        h.append(field("SSH 隧道域名", "⑥ 隧道用。cloudflared / ssh -R 给你的那个域名。",
                "tunnel_url", st.tunnelUrl, "https://xxx.trycloudflare.com"));
        h.append(field("外部后端地址", "④ 后端房间用。你自己部署的后端根地址。",
                "external_backend", st.externalBackend, "http://backend.example.com:8080"));
        h.append(field("组网虚拟 IP", "⑦ 组网用。Tailscale/ZeroTier 分配给你的 100.x 地址；留空自动探测。",
                "mesh_ip", st.meshIp, "100.101.102.103"));

        h.append("<div class='actions'>")
                .append("<button class='btn' type='submit'>保存</button>")
                .append("<a class='btn2' href='/local/choose'>选建房方式</a>")
                .append("</div>");
        h.append("</form>");

        h.append("<div class='line'></div>")
                .append("<div class='foot'>清空全部配置：")
                .append("<a href='/local/settings?clear=1' style='color:#4DA3FF'>点这里</a>")
                .append(" &middot; 机器可读：<a href='/local/settings?json=1' style='color:#4DA3FF'>JSON</a></div>")
                .append("</body></html>");
        return h.toString();
    }

    static String or(String a, String b) {
        return a == null || a.trim().isEmpty() ? b : a;
    }

    static JSONObject src(String key, String name) {
        JSONObject s = o();
        put(s, "key", key);
        put(s, "name", name);
        put(s, "value", key);
        put(s, "enabled", true);
        return s;
    }

    static JSONObject platformFeatures() {
        JSONObject p = o();
        put(p, "ads_enabled", false);
        put(p, "announcements_count", 0);
        put(p, "announcements_enabled", false);
        put(p, "annual_report", false);
        put(p, "public_rooms", false);
        put(p, "room_global_announcement_enabled", false);
        put(p, "room_global_announcement_text", "");
        put(p, "vip", true);
        put(p, "voice_call", false);
        return p;
    }

    static JSONObject featuresObj() {
        JSONObject f = o();

        put(f, "android", platformFeatures());
        put(f, "ios", platformFeatures());

        put(f, "anime_search", true);
        put(f, "bilibili_parser", true);
        put(f, "code_login", true);
        put(f, "emby", true);
        put(f, "iptv", false);
        put(f, "live_parser", true);
        put(f, "pan_search", true);
        put(f, "profile", true);
        put(f, "promotion", "off");
        put(f, "resource_hall", true);
        put(f, "room", true);
        put(f, "smart_analyse", false);
        put(f, "social", false);
        put(f, "sticker_discover", false);
        JSONObject ss = o();
        put(ss, "bases", new JSONArray());
        put(ss, "headers", o());
        put(ss, "keyword_blocklist", new JSONArray());
        put(f, "sticker_source", ss);
        put(f, "universal_spider", true);
        put(f, "user_reviews", false);
        put(f, "video", true);
        put(f, "video_parser", true);
        put(f, "vip", true);
        return f;
    }

    static JSONObject configMap(Store st) {
        JSONObject c = o();
        put(c, "ads_enabled", false);
        put(c, "maintenance_mode", false);
        put(c, "allow_registration", false);
        put(c, "allow_search", true);
        put(c, "allow_summon", false);
        put(c, "local_mode", true);
        put(c, "lean", true);
        put(c, "lean_mode", true);
        put(c, "login_required", false);
        put(c, "vip_required", false);
        put(c, "social_enabled", false);
        put(c, "promotion_enabled", false);
        put(c, "announcement_enabled", false);
        put(c, "survey_enabled", false);
        put(c, "sticker_store_enabled", false);
        put(c, "ad_enabled", false);
        put(c, "banner_enabled", false);
        put(c, "channel_enabled", false);
        put(c, "room_global_announcement_text", "");
        put(c, "local_port", LocalServer.PORT);
        put(c, "local_lan", LocalServer.lanIp());
        return c;
    }

    static JSONObject config(Context ctx, Store st) {
        JSONObject o = ok();
        JSONObject cm = configMap(st);
        put(o, "config", cm);
        Iterator<String> it = cm.keys();
        while (it.hasNext()) {
            String k = it.next();
            put(o, k, cm.opt(k));
        }

        put(o, "features", featuresObj());
        put(o, "watch_card_enabled", true);
        put(o, "maintenance_mode", false);
        put(o, "maintenance_message", "");
        put(o, "app_download_url", "");

        JSONArray pl = new JSONArray();
        pl.put(stream("Big Buck Bunny", "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8", ""));
        pl.put(stream("Sintel", "https://bitdash-a.akamaihd.net/content/sintel/hls/playlist.m3u8", ""));
        put(o, "starter_playlist", pl);
        put(o, "danmu_api_base_url", "http://127.0.0.1:" + LocalServer.PORT + "/danmu");
        put(o, "danmu_api_token", "local");
        put(o, "custom_danmu_sources", new JSONArray());
        return o;
    }

    static JSONObject checkIn(Store st, LocalServer.Req r, String p) {
        JSONObject u = auth(st, r);
        if (u == null) return fail("Not authenticated");

        if (p.contains("status")) {
            JSONObject o = ok();
            put(o, "checked_in_today", u.optBoolean("checked_in_today", false));
            put(o, "check_in_count", u.optInt("check_in_count", 0));
            put(o, "points", u.optInt("points", 0));
            put(o, "available_points", u.optInt("points", 0));
            put(o, "today_points", 10);
            return o;
        }
        if (p.contains("daily")) {
            boolean done = u.optBoolean("checked_in_today", false);
            JSONObject o = ok();
            if (!done) {
                put(u, "checked_in_today", true);
                put(u, "check_in_count", u.optInt("check_in_count", 0) + 1);
                put(u, "points", u.optInt("points", 0) + 10);
                put(u, "last_check_in", Store.nowIso());
                st.save();
                put(o, "points_awarded", 10);
                put(o, "message", "签到成功，+10 积分");
            } else {
                put(o, "points_awarded", 0);
                put(o, "message", "今日已签到");
            }
            put(o, "checked_in_today", true);
            put(o, "check_in_count", u.optInt("check_in_count", 0));
            put(o, "points", u.optInt("points", 0));
            put(o, "available_points", u.optInt("points", 0));
            return o;
        }
        if (p.contains("leaderboard")) {
            JSONObject o = ok();
            put(o, "items", new JSONArray());
            put(o, "leaderboard", new JSONArray());
            put(o, "total", 0);
            return o;
        }
        if (p.contains("transactions")) {
            JSONObject o = ok();
            put(o, "items", new JSONArray());
            put(o, "total", 0);
            return o;
        }
        JSONObject o = ok();
        put(o, "points", u.optInt("points", 0));
        return o;
    }

    static JSONObject roomOp(Context ctx, Store st, LocalServer.Req r, String p) {
        String code = seg(p, p.startsWith("/api/") ? 2 : 1);
        JSONObject room = st.findRoom(code);
        if (room == null) {
            JSONObject o = fail("房间不存在: " + code);
            put(o, "room", JSONObject.NULL);
            return o;
        }

        String sub = "";
        String[] a = p.split("/");
        for (int i = 0; i < a.length; i++) {
            if (a[i].equals(code) && i + 1 < a.length) {
                sub = a[i + 1];
                break;
            }
        }

        if ("state".equals(sub) || "status".equals(sub) || "".equals(sub)) {
            JSONObject o = ok();
            JSONObject snap = Store.get(ctx).roomSnapshot(code, null);
            JSONObject view = snap != null ? snap : room;
            put(o, "room", view);
            put(o, "data", view);
            put(o, "playback", room.optJSONObject("playback"));
            put(o, "members", view.optJSONArray("members"));
            put(o, "online", LocalServer.get(ctx).wsList.size());
            // D26：详情接口也下发通道列表，客户端进房前靠它选路（原来只有建房/分享才带，
            // 结果客户端每次拿到空表只能走兜底，多通道选路等于没生效）。
            JSONArray addrs = Rooms.buildAddrs(st);
            put(o, "addrs", addrs);
            Log.i(LocalServer.TAG, "[YQK-CH] detail addrs code=" + code + " n=" + addrs.length());
            // E8：六层优先级。addrs 是老字段，原样保留（老客户端还在用），
            // primary/ranked/skipped 并行下发，客户端认哪个都行。
            JSONObject pick = Rooms.pickAddr(st, code, st.defaultMode);
            put(o, "primary", pick.opt("primary"));
            put(o, "ranked", pick.optJSONArray("ranked"));
            put(o, "skipped", pick.optJSONArray("skipped"));
            return o;
        }

        if ("kick".equals(sub)) {
            // M7 P0：踢人。标记 kicked（重连带旧 memberToken 会被 4005 拒）+ 当场断开
            String mid = Store.str(r.json, "memberId", Store.str(r.json, "id", ""));
            if (mid == null || mid.trim().isEmpty()) {
                // 空 id 会把「踢人」变成空操作却回 ok，调用方以为踢掉了
                JSONObject e = new JSONObject();
                put(e, "ok", false);
                put(e, "code", 400);
                put(e, "error", "memberId 不能为空");
                put(e, "detail", "memberId 不能为空");
                return e;
            }
            if (mid.equals(Store.hostIdOf(room))) {
                // 踢了房主之后 room.host 指向被踢的 id，房间变没主的死局
                JSONObject e = new JSONObject();
                put(e, "ok", false);
                put(e, "code", 403);
                put(e, "error", "不能踢房主");
                put(e, "detail", "不能踢房主");
                return e;
            }
            st.markKicked(room, mid);
            st.dropProgress(code, mid);
            int closed = 0;
            for (LocalServer.Ws w : new ArrayList<LocalServer.Ws>(LocalServer.get(ctx).wsList)) {
                if (w.memberId.equals(mid)) {
                    w.close(4005, "kicked");
                    closed++;
                }
            }
            JSONObject o = ok();
            put(o, "memberId", mid);
            put(o, "closed", closed);
            // 别把 room.members 原样吐出去：里面有每个成员的 memberToken
            java.util.Set<String> online = new java.util.HashSet<>();
            for (LocalServer.Ws w : LocalServer.get(ctx).wsList) {
                if (w.memberId != null) online.add(w.memberId);
            }
            JSONObject snap = st.roomSnapshot(code, online);
            put(o, "members", snap == null ? new JSONArray() : snap.optJSONArray("members"));
            return o;
        }

        if ("join".equals(sub) || "members".equals(sub)) {
            JSONObject u = auth(st, r);
            // C4：进房前校验容量；GET members 只是读列表，不该被满员挡住
            if ("POST".equals(r.method) && Store.liveMembers(room) >= Store.maxMembers(room)) {
                JSONObject full = o();
                put(full, "ok", false);
                put(full, "success", false);
                put(full, "code", 400);
                put(full, "error", "房间已满");
                put(full, "detail", "房间已满");
                return full;
            }
            // 成员创建只有 Store.addMember 一条路径（带 id/token/role，online 才匹配得上）
            // D28：join 也认 ?name= 与 ?bot=1（探针从这条 HTTP join 进房；WS 握手那条同名参数在 LocalServer）
            String jName = r.q("name", "");
            boolean jBot = "1".equals(r.q("bot", "")) || "true".equalsIgnoreCase(r.q("bot", ""));
            JSONObject m = st.addMember(room,
                    jName.isEmpty()
                            ? (u == null ? "guest" : Store.str(u, "nickname", "guest"))
                            : jName,
                    false, jBot);
            if (u != null) put(m, "user_id", u.opt("id"));
            st.save();
            broadcast(ctx, code, "joined", m);
            JSONObject o = ok();
            put(o, "room", room);
            put(o, "member", m);
            put(o, "data", room);
            return o;
        }

        if ("sync".equals(sub) || "playback".equals(sub) || "progress".equals(sub)) {
            // HTTP 这条路没有 WS 鉴权，必须自己从 auth() 找 memberId；
            // 找不到成员就只更新自己的 progress（非权威），不写 playback、不广播 state。
            if ("POST".equals(r.method)) {
                JSONObject u = auth(st, r);
                String mid = memberIdOf(room, u);
                if (mid == null) {
                    JSONObject err = o();
                    put(err, "ok", false);
                    put(err, "code", 403);
                    put(err, "error", "先加入房间再同步进度");
                    return err;
                }
                JSONObject pb = applyPlayback(ctx, code, r.json, mid);
                JSONObject o = ok();
                put(o, "playback", pb);
                put(o, "room", room);
                return o;
            }
            JSONObject pb = applyPlayback(ctx, code, r.json);
            JSONObject o = ok();
            put(o, "playback", pb);
            put(o, "room", room);
            return o;
        }

        if ("chat".equals(sub) || "messages".equals(sub)) {
            JSONArray chat = room.optJSONArray("chat");
            if (chat == null) {
                chat = new JSONArray();
                put(room, "chat", chat);
            }
            if ("POST".equals(r.method)) {
                JSONObject u = auth(st, r);
                JSONObject msg = o();
                put(msg, "id", chat.length() + 1);
                put(msg, "text", Store.str(r.json, "text", Store.str(r.json, "message", "")));
                put(msg, "nickname", u == null ? "guest" : Store.str(u, "nickname", "guest"));
                put(msg, "user_id", u == null ? 0 : u.opt("id"));
                put(msg, "created_at", Store.nowIso());
                chat.put(msg);
                st.save();
                broadcast(ctx, code, "chat", msg);
                JSONObject o = ok();
                put(o, "message_obj", msg);
                put(o, "item", msg);
                return o;
            }
            JSONObject o = ok();
            put(o, "items", chat);
            put(o, "messages", chat);
            put(o, "total", chat.length());
            return o;
        }

        JSONObject o = ok();
        put(o, "room", room);
        put(o, "data", room);
        return o;
    }

    /**
     * 播放帧：拆成两路（m09136）。
     * - 权威来源（房主 / control 持有者）→ 写 room.playback 并广播 `state`（带 seq）
     * - 其他人 → 只写 room.progress 并广播 `progress`（幂等，可合并）
     * memberId 一律服务端填，不信客户端传的 by。
     */
    public static JSONObject applyPlayback(Context ctx, String code, JSONObject src) {
        return applyPlayback(ctx, code, src, "");
    }

    public static JSONObject applyPlayback(Context ctx, String code, JSONObject src, String memberId) {
        return applyPlayback(ctx, code, src, memberId, false);
    }

    /**
     * @param force 跳过准入检查：房主批准 claim 时用。批准不等于「权威源变了」，
     *              by 仍然是发起者（客户端靠它做防自激与显示）。
     */
    public static JSONObject applyPlayback(Context ctx, String code, JSONObject src, String memberId, boolean force) {
        Store st = Store.get(ctx);
        JSONObject room = st.findRoom(code);
        JSONObject pb = o();
        if (room == null) return pb;

        String by = memberId == null ? "" : memberId;
        double pos = src.optDouble("position", src.optDouble("progress", 0));
        boolean playing = src.optBoolean("playing", src.optBoolean("is_playing", false));

        // 每个人自己的进度：内存 Map，覆盖式更新；不参与 save()（掉电丢进度可接受）
        JSONObject prog = st.progressOf(code);
        if (!by.isEmpty()) {
            JSONObject mine = o();
            put(mine, "position", pos);
            put(mine, "playing", playing);
            put(mine, "at", System.currentTimeMillis());
            put(prog, by, mine);
        }

        boolean authoritative = force || Store.isAuthoritative(room, by);
        boolean throttled = false;
        if (authoritative && "free".equals(Store.controlModeOf(room))) {
            // 自由共控：两端抢控时 300ms 内只让第一次生效（房主在 host 模式不受此限）
            long nowMs = System.currentTimeMillis();
            long lastMs = room.optLong("last_control_at", 0L);
            if (nowMs - lastMs < 300L) {
                throttled = true;
                android.util.Log.i("YiqikanLocal", "[YQK-WS] control throttled by=" + by
                        + " gap=" + (nowMs - lastMs));
            } else {
                put(room, "last_control_at", nowMs);
            }
        }
        JSONObject cur = room.optJSONObject("playback");
        if (authoritative && !throttled) {
            if (cur == null) {
                cur = o();
                put(room, "playback", cur);
            }
            long prevAt = cur.optLong("updated_at", 0);
            // patch 语义：src 里没有的字段一律不动，绝不写默认值把已有状态抹平
            if (src.has("position") || src.has("progress")) put(cur, "position", pos);
            if (src.has("duration")) put(cur, "duration", src.optDouble("duration", 0));
            if (src.has("playing") || src.has("is_playing")) put(cur, "playing", playing);
            if (src.has("episode") || src.has("current_episode")) {
                put(cur, "episode", src.optInt("episode", src.optInt("current_episode", 0)));
            }
            if (src.has("speed") || src.has("rate")) {
                put(cur, "speed", src.optDouble("speed", src.optDouble("rate", 1)));
            }
            long nowAt = System.currentTimeMillis();
            put(cur, "updated_at", nowAt);
            put(cur, "by", by);
            pb = cur;
            // 只有权威播放真变化、且距上次落盘 >1s 才写盘（否则 10 人房每秒十几次全量写）
            if (nowAt - prevAt > 1000) st.save();
        }

        LocalServer srv = LocalServer.get(ctx);
        if (authoritative && !throttled) {
            JSONObject snap = cur != null ? cur : room.optJSONObject("playback");
            if (snap == null) snap = o();
            JSONObject state = o();
            put(state, "type", "state");
            put(state, "room", code);
            JSONObject inner = o();
            // 广播读 cur（patch 之后的权威状态），不读 src —— 否则 rate 动作会广播缺省的 playing
            put(inner, "playing", snap.optBoolean("playing", false));
            put(inner, "position", snap.optDouble("position", 0));
            put(inner, "rate", snap.optDouble("speed", 1));
            put(inner, "duration", snap.optDouble("duration", 0));
            put(inner, "episode", snap.optInt("episode", 0));
            put(inner, "by", by);
            put(inner, "updatedAt", System.currentTimeMillis());
            put(state, "state", inner);
            put(state, "seq", st.nextRoomSeq(code));
            srv.broadcastRoom(code, state.toString());
        }
        JSONObject pr = o();
        put(pr, "type", "progress");
        put(pr, "room", code);
        put(pr, "memberId", by);
        put(pr, "position", pos);
        put(pr, "playing", playing);
        put(pr, "t", System.currentTimeMillis());
        srv.broadcastRoom(code, pr.toString());
        return pb;
    }

    static void broadcast(Context ctx, String room, String type, Object payload) {
        JSONObject msg = o();
        put(msg, "type", type);
        put(msg, "room", room);
        put(msg, "payload", payload);
        put(msg, "t", System.currentTimeMillis());
        LocalServer.get(ctx).broadcastRoom(room, msg.toString());
    }

    static JSONObject social(Context ctx, Store st, LocalServer.Req r, String p) {
        if (p.contains("users/search")) {
            String email = Store.str(r.json, "email", r.q("email", ""));
            JSONObject u = st.findUserByEmail(email);
            JSONObject o = ok();
            JSONArray arr = new JSONArray();
            if (u != null) arr.put(pub(u));
            put(o, "items", arr);
            put(o, "users", arr);
            put(o, "total", arr.length());
            return o;
        }
        if (p.contains("couple")) {
            JSONObject me = auth(st, r);
            String key = me == null ? "anon" : Store.str(me, "email");
            JSONObject c = st.couples.get(key);
            if (c == null) c = o();
            if ("POST".equals(r.method) && p.contains("request")) {
                put(c, "status", "pending");
                put(c, "requested_to", Store.str(r.json, "target_email"));
                put(c, "message", Store.str(r.json, "message"));
                put(c, "requested_at", Store.nowIso());
                st.couples.put(key, c);
                st.save();
                JSONObject o = ok();
                put(o, "couple", c);
                put(o, "data", c);
                put(o, "detail", "已发起邀请（本地服务不校验对方是否存在）");
                return o;
            }
            JSONObject o = ok();
            put(o, "couple", c);
            put(o, "data", c);
            put(o, "info", c);
            put(o, "status", c.optString("status", "none"));
            put(o, "companion_count", 0);
            put(o, "anniversary_date", c.optString("anniversary_date", ""));
            return o;
        }
        if (p.contains("chat")) {
            JSONObject o = ok();
            put(o, "items", new JSONArray());
            put(o, "messages", new JSONArray());
            put(o, "chats", new JSONArray());
            put(o, "total", 0);
            put(o, "unread_count", 0);
            return o;
        }
        if (p.contains("rankings")) {
            JSONObject o = ok();
            put(o, "items", new JSONArray());
            put(o, "rankings", new JSONArray());
            put(o, "total", 0);
            return o;
        }
        JSONObject o = ok();
        put(o, "items", new JSONArray());
        put(o, "users", new JSONArray());
        put(o, "total", 0);
        put(o, "unread_count", 0);
        return o;
    }
}
