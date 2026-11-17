package top.yiqikan.app.server;

import android.content.Context;
import android.util.Log;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.nio.charset.Charset;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * 本地数据仓库。全部落在 App 私有目录，卸载即清。
 *
 * 文件：
 *   users.json    账号 + token
 *   rooms.json    一起看房间
 *   misc.json     情侣/收藏/公告/观看记录
 */
public class Store {

    public static final Charset UTF8 = Charset.forName("UTF-8");

    private static Store INSTANCE;

    public static synchronized Store get(Context ctx) {
        if (INSTANCE == null) {
            INSTANCE = new Store(ctx.getApplicationContext());
        }
        return INSTANCE;
    }

    private final File dir;

    /** email -> user */
    public final Map<String, JSONObject> users = new LinkedHashMap<String, JSONObject>();
    /** token -> email */
    public final Map<String, String> tokens = new LinkedHashMap<String, String>();
    /** room code -> room */
    public final Map<String, JSONObject> rooms = new LinkedHashMap<String, JSONObject>();
    /** email -> JSONArray of favorite */
    public final Map<String, JSONArray> favorites = new LinkedHashMap<String, JSONArray>();
    /** email -> JSONArray of watch history */
    public final Map<String, JSONArray> watches = new LinkedHashMap<String, JSONArray>();
    /** email pair -> couple object */
    public final Map<String, JSONObject> couples = new LinkedHashMap<String, JSONObject>();

    public JSONArray announcements = new JSONArray();

    /** 一起看：转发目标（另一台手机的内置服务 IP）。空 = 纯本机。 */
    public volatile String peer = "";

    /** M7 房间握手 token 的 HMAC 密钥（32 字节 hex），落 misc.json */
    public volatile String roomSecret = "";

    /** ③ 云房间：外部中继地址（不填则回落内网） */
    public volatile String relay = "";
    /** ④ 后端房间：外部后端地址 */
    public volatile String externalBackend = "";
    /** ⑥ SSH 隧道：对外域名（如 https://xxx.trycloudflare.com） */
    public volatile String tunnelUrl = "";

    /** E7 DDNS：域名（如 abc.duckdns.org）。非空时分享链接优先用它。 */
    public volatile String ddnsHost = "";
    /** E7 DDNS：provider（duckdns / noip / custom，本轮只实现 duckdns） */
    public volatile String ddnsProvider = "";
    /** E7 DDNS：token。日志里一律打 ***，不许明文。 */
    public volatile String ddnsToken = "";
    /** E7 DDNS：上一次更新用的公网 IP */
    public volatile String ddnsLastIp = "";
    /** E7 DDNS：上一次更新的时间（epoch ms，0 = 还没跑过） */
    public volatile long ddnsLastAt = 0L;
    /** E7 DDNS：上一次结果 ok / nochange / fail:... */
    public volatile String ddnsLastResult = "";

    /** E9 relay：中继 token（URL 复用上面的 relay 字段） */
    public volatile String relayToken = "";

    /** 语音总开关：/local/features 可读可写；与 VOICE 同属内存态，重启回默认 true。 */
    volatile boolean voiceEnabled = true;

    /** ⑦ 组网：Tailscale / ZeroTier 虚拟 IP（100.x），空 = 自动探测 */
    public volatile String meshIp = "";

    /** 用户选定的默认建房方式；空 = 还没选过，建房时提示选择 */
    public volatile String defaultMode = "";

    private Store(Context ctx) {
        File base = ctx.getFilesDir();
        if (base == null) {
            base = new File("/data/data/" + ctx.getPackageName() + "/files");
        }
        dir = new File(base, "localserver");
        if (!dir.exists()) {
            //noinspection ResultOfMethodCallIgnored
            dir.mkdirs();
        }
        announcements = defaultAnnouncements();
        load();
    }

    // ---------------------------------------------------------------- 默认数据

    private JSONArray defaultAnnouncements() {
        JSONArray arr = new JSONArray();
        try {
            JSONObject a = new JSONObject();
            a.put("id", 1);
            a.put("title", "本地服务已启动");
            a.put("content", "当前版本由机内服务提供数据，不访问任何外部服务器。");
            a.put("is_popup", true);
            a.put("created_at", nowIso());
            arr.put(a);
        } catch (Exception ignored) {
        }
        return arr;
    }

    // ---------------------------------------------------------------- 账号

    public JSONObject findUserByEmail(String email) {
        if (email == null) return null;
        return users.get(email.trim().toLowerCase());
    }

    public JSONObject findUserById(Object id) {
        if (id == null) return null;
        String s = String.valueOf(id);
        for (JSONObject u : users.values()) {
            if (s.equals(str(u, "id"))) return u;
        }
        return null;
    }

    public JSONObject findUserByToken(String token) {
        if (token == null) return null;
        String email = tokens.get(token);
        if (email == null) return null;
        return users.get(email);
    }

    public JSONObject createUser(String email, String password, String nickname) {
        String key = email.trim().toLowerCase();
        JSONObject u = new JSONObject();
        try {
            u.put("id", users.size() + 1);
            u.put("email", key);
            u.put("password", password);
            u.put("nickname", nickname == null || nickname.isEmpty() ? key.split("@")[0] : nickname);
            u.put("avatar", "");
            u.put("is_vip", false);
            u.put("vip_expire_at", "");
            u.put("points", 100);
            u.put("check_in_count", 0);
            u.put("checked_in_today", false);
            u.put("last_check_in", "");
            u.put("banned", false);
            u.put("ban_reason", "");
            u.put("created_at", nowIso());
            u.put("device_id", "");
        } catch (Exception ignored) {
        }
        users.put(key, u);
        save();
        return u;
    }

    public String issueToken(String email) {
        String t = UUID.randomUUID().toString().replace("-", "");
        tokens.put(t, email.trim().toLowerCase());
        save();
        return t;
    }

    public void revokeToken(String token) {
        if (token != null) {
            tokens.remove(token);
            save();
        }
    }

    // ---------------------------------------------------------------- 房间

    public JSONObject createRoom(String code, JSONObject body, JSONObject owner) {
        JSONObject r = new JSONObject();
        try {
            r.put("code", code);
            r.put("name", str(body, "name", str(body, "title", "一起看")));
            r.put("video_url", str(body, "video_url", str(body, "url", "")));
            r.put("video_urls", body.optJSONArray("video_urls") == null ? new JSONArray() : body.optJSONArray("video_urls"));
            r.put("tag", str(body, "tag", ""));
            r.put("emby", str(body, "emby", ""));
            r.put("current_episode", body.optInt("current_episode", 0));
            // C4：容量默认 20，clamp 到 1..50（0 或负数会让房间一建就满）
            int cap = body.optInt("max_members", 20);
            if (cap < 1) cap = 1;
            if (cap > 50) cap = 50;
            r.put("max_members", cap);
            r.put("is_private", body.optBoolean("is_private", false));
        r.put("approval", body.optBoolean("approval", false));
            r.put("control_mode", "free".equals(str(body, "control_mode", "host")) ? "free" : "host");
            r.put("video_avatar", str(body, "video_avatar", ""));
            r.put("subtitles", str(body, "subtitles", ""));
            r.put("owner_id", owner == null ? JSONObject.NULL : owner.opt("id"));
            r.put("owner_name", owner == null ? "local" : str(owner, "nickname", "local"));
            r.put("created_at", nowIso());

            JSONArray members = new JSONArray();
            // 房主走跟客人同一条成员路径：一条完整 member 记录 + 一个 memberToken，
            // `host` 字段只存 memberId（名字在 members[].nickname）
            String ownerMemberId = "m_" + randId(10);
            JSONObject om = new JSONObject();
            om.put("id", ownerMemberId);
            om.put("token", java.util.UUID.randomUUID().toString());
            om.put("nickname", owner == null ? "房主" : str(owner, "nickname", "房主"));
            om.put("name", om.optString("nickname", "房主"));
            om.put("role", "host");
            om.put("approved", true);
            om.put("muted", false);
            om.put("kicked", false);
            om.put("joined_at", nowIso());
            members.put(om);
            r.put("host", ownerMemberId);
            r.put("members", members);

            JSONObject pb = new JSONObject();
            pb.put("position", 0);
            pb.put("duration", 0);
            pb.put("playing", false);
            pb.put("episode", 0);
            pb.put("updated_at", System.currentTimeMillis());
            r.put("playback", pb);
            r.put("chat", new JSONArray());
            r.put("room_token", roomTokenFor(code));
        } catch (Exception ignored) {
        }
        rooms.put(code, r);
        save();
        return r;
    }

    // ================================================================ 房间鉴权与成员（M7 P0）

    /**
     * 房间快照：hello / 重连时一次给全，客户端不自己拼状态（11 号 §4.1）。
     *
     * 结构：
     * { code, name, host{id,name}, approval, settings{},
     *   media{url,title,duration,epIndex},
     *   state{playing,position,rate,updatedAt,seq},
     *   members[{id,nickname,role,muted,online}] }
     */
    public synchronized JSONObject roomSnapshot(String code, java.util.Set<String> onlineIds) {
        JSONObject room = rooms.get(code);
        if (room == null) return null;
        JSONObject out = new JSONObject();
        try {
            out.put("code", room.optString("code", code));
            out.put("name", room.optString("name", ""));

            // host 存的是 memberId（老数据回落到 members 里 role=host/owner 的那条）
            String hid = hostIdOf(room);

            out.put("approval", room.optBoolean("approval", false));
            out.put("control_mode", controlModeOf(room));

            JSONObject settings = new JSONObject();
            settings.put("maxMembers", room.optInt("max_members", 20));
            settings.put("tag", room.optString("tag", ""));
            out.put("settings", settings);

            JSONObject pb = room.optJSONObject("playback");
            JSONObject media = new JSONObject();
            media.put("url", room.optString("video_url", ""));
            // 片名只取 media 自己的，没有就是空串；房间名是 out.name，两者不许混
            String mtitle = room.optString("video_title", "");
            if (mtitle.isEmpty() && pb != null) mtitle = pb.optString("title", "");
            media.put("title", mtitle);
            media.put("duration", pb == null ? 0 : pb.optDouble("duration", 0));
            media.put("epIndex", room.optInt("current_episode", 0));
            out.put("media", media);

            JSONObject state = new JSONObject();
            state.put("playing", pb != null && pb.optBoolean("playing", false));
            state.put("position", pb == null ? 0 : pb.optDouble("position", 0));
            state.put("rate", pb == null ? 1.0 : pb.optDouble("rate", 1.0));
            state.put("updatedAt", pb == null ? 0 : pb.optLong("updated_at", 0));
            out.put("state", state);

            JSONArray ms = new JSONArray();
            JSONArray raw = room.optJSONArray("members");
            for (int i = 0; raw != null && i < raw.length(); i++) {
                JSONObject m = raw.optJSONObject(i);
                if (m == null) continue;
                if (m.optBoolean("kicked", false)) continue;
                if (!m.optBoolean("approved", true)) continue;
                JSONObject one = new JSONObject();
                String id = m.optString("id", m.optString("user_id", ""));
                if (id.isEmpty() && hid.isEmpty()) hid = id;
                one.put("id", id);
                String nick = m.optString("nickname", m.optString("name", ""));
                one.put("nickname", nick);
                // 角色只有两种：host / guest；老数据 owner/member 就地映射
                String role = m.optString("role", "");
                boolean isHost = "host".equals(role) || "owner".equals(role) || m.optBoolean("isHost", false);
                one.put("role", isHost ? "host" : "guest");
                one.put("muted", m.optBoolean("muted", false));
                one.put("online", onlineIds != null && onlineIds.contains(id));
                // D28：快照是白名单投影，成员对象里的 bot 必须在这里显式带出去
                one.put("bot", m.optBoolean("bot", false));
                // 每个人自己的进度（内存 roomProgress 是唯一来源，成员条目只做投影）
                JSONObject prog = progressOf(code);
                JSONObject mine = prog.optJSONObject(id);
                JSONObject pj = new JSONObject();
                pj.put("position", mine == null ? 0 : mine.optDouble("position", 0));
                pj.put("playing", mine != null && mine.optBoolean("playing", false));
                one.put("progress", pj);
                ms.put(one);
            }
            if (hid.isEmpty() && ms.length() > 0) {
                // 极老数据：没有 host 字段，取第一条 host 角色的成员
                for (int i = 0; i < ms.length(); i++) {
                    JSONObject one = ms.optJSONObject(i);
                    if (one != null && "host".equals(one.optString("role", ""))) {
                        hid = one.optString("id", "");
                        break;
                    }
                }
            }
            out.put("host", hid);
            out.put("members", ms);
            // 弹幕点赞数全量：客户端重进房靠这份恢复（M8 点赞，2026-11-08）
            JSONObject likes = room.optJSONObject("danmaku_likes");
            out.put("danmaku_likes", likes == null ? new JSONObject() : likes);
        } catch (Throwable ignored) {
        }
        return out;
    }


    /**
     * 弹幕点赞 +1（M8 点赞，2026-11-08）。返回累加后的值，房间不存在返回 -1。
     *
     * 放在 Store 里而不是在 LocalServer 的分支里直接改：rooms 是共享可变 JSONObject，
     * 递增必须和落盘走同一把锁（synchronized），否则两条 danmaku-like 并发会丢计数。
     */
    public synchronized int bumpDanmakuLike(String code, String id) {
        JSONObject room = rooms.get(code);
        if (room == null || id == null || id.isEmpty()) return -1;
        try {
            JSONObject counts = room.optJSONObject("danmaku_likes");
            if (counts == null) {
                counts = new JSONObject();
                room.put("danmaku_likes", counts);
            }
            int n = counts.optInt(id, 0) + 1;
            counts.put(id, n);
            save();
            return n;
        } catch (Throwable ignored) {
            return -1;
        }
    }

    /** 房间内 state/sync 帧的服务端统一编号（客户端只读，不自己写 seq）。 */
    public synchronized int nextRoomSeq(String code) {
        JSONObject room = rooms.get(code);
        if (room == null) return 0;
        int seq = room.optInt("seq", 0) + 1;
        try {
            room.put("seq", seq);
        } catch (Throwable ignored) {
        }
        return seq;
    }

    /** 服务端随机 secret：首次用到时生成并落盘 misc.json */
    public synchronized String ensureSecret() {
        if (roomSecret == null || roomSecret.isEmpty()) {
            byte[] b = new byte[32];
            new java.security.SecureRandom().nextBytes(b);
            StringBuilder sb = new StringBuilder();
            for (byte x : b) sb.append(String.format("%02x", x));
            roomSecret = sb.toString();
            // 不在这里 save()：save() 自己会调用本方法，递归。secret 由下一次 save 落盘
        }
        return roomSecret;
    }

    /** 房间握手 token = HMAC-SHA256(secret, "room:" + code) 的前 32 位 hex（建房时签发，随房间落库） */
    public String roomTokenFor(String code) {
        try {
            String secret = ensureSecret();
            javax.crypto.Mac mac = javax.crypto.Mac.getInstance("HmacSHA256");
            mac.init(new javax.crypto.spec.SecretKeySpec(secret.getBytes(UTF8), "HmacSHA256"));
            byte[] d = mac.doFinal(("room:" + code).getBytes(UTF8));
            StringBuilder sb = new StringBuilder();
            for (byte x : d) sb.append(String.format("%02x", x));
            return sb.substring(0, 32);
        } catch (Throwable t) {
            Log.w("YiqikanLocal", "roomTokenFor failed: " + t);
            return "";
        }
    }

    /** 按 memberToken 找成员（重连复用 memberId 用） */
    public synchronized JSONObject memberByToken(JSONObject room, String token) {
        if (room == null || token == null || token.isEmpty()) return null;
        JSONArray mem = room.optJSONArray("members");
        if (mem == null) return null;
        for (int i = 0; i < mem.length(); i++) {
            JSONObject m = mem.optJSONObject(i);
            if (m != null && token.equals(m.optString("token", ""))) return m;
        }
        return null;
    }

    /**
     * I-81：摘掉「同名 + 已离线 + 非房主」的幽灵成员。
     *
     * 客人 force-stop 后用同一条深链重进，HTTP /join 会给他建一条新 member（新 id），
     * 上一次那条留在 members 里就成了幽灵条（members=3 / online=2）。同名的记录如果
     * 此刻没有任何活连接，只可能是同一台设备上一次进房留下的 —— 直接摘掉，
     * 否则成员条永远多一个人。正连着的那条在 onlineIds 里，不动。
     *
     * @return 摘掉的条数
     */
    public synchronized int dropOfflineGuestsNamed(JSONObject room, String name,
                                                   java.util.Set<String> onlineIds) {
        if (room == null) return 0;
        String n = name == null ? "" : name.trim();
        if (n.isEmpty()) return 0;
        JSONArray mem = room.optJSONArray("members");
        if (mem == null) return 0;
        String code = room.optString("code", "");
        int removed = 0;
        for (int i = mem.length() - 1; i >= 0; i--) {
            JSONObject m = mem.optJSONObject(i);
            if (m == null) continue;
            if (m.optBoolean("isHost", false) || "host".equals(m.optString("role", ""))) continue;
            if (m.optBoolean("bot", false)) continue;
            String id = m.optString("id", "");
            if (id.isEmpty()) continue;
            if (onlineIds != null && onlineIds.contains(id)) continue;
            String mn = m.optString("nickname", m.optString("name", ""));
            if (!n.equals(mn)) continue;
            mem.remove(i);
            if (!code.isEmpty()) dropProgress(code, id);
            removed++;
        }
        if (removed > 0) save();
        return removed;
    }

    /** 握手后 hello 里才有昵称：补写成员名（快照/成员列表要显示真名）。 */
    public synchronized void renameMember(String code, String memberId, String name) {
        JSONObject room = rooms.get(code);
        if (room == null || memberId == null || memberId.isEmpty()) return;
        if (name == null || name.trim().isEmpty()) return;
        JSONArray mem = room.optJSONArray("members");
        for (int i = 0; mem != null && i < mem.length(); i++) {
            JSONObject m = mem.optJSONObject(i);
            if (m == null || !memberId.equals(m.optString("id", ""))) continue;
            try {
                m.put("name", name.trim());
                m.put("nickname", name.trim());
            } catch (Throwable ignored) {
            }
            return;
        }
    }

    /**
     * 谁是权威播放来源：房主或 control 持有者；memberId 为空（HTTP 老路径）也算权威。
     */
    /** 每人的播放进度只在内存里（不落 rooms.json，否则 10 人房每秒 10 次全量写盘） */
    private final Map<String, JSONObject> roomProgress = new java.util.concurrent.ConcurrentHashMap<String, JSONObject>();

    public JSONObject progressOf(String code) {
        JSONObject p = roomProgress.get(code);
        if (p == null) {
            p = new JSONObject();
            roomProgress.put(code, p);
        }
        return p;
    }

    public void dropProgress(String code, String memberId) {
        JSONObject p = roomProgress.get(code);
        if (p != null) p.remove(memberId);
    }

    public void clearProgress(String code) {
        roomProgress.remove(code);
    }

    /** 房间控制模式：'host'（房主权威，默认）/ 'free'（自由共控）。 */
    public static String controlModeOf(JSONObject room) {
        String m = str(room, "control_mode", "host");
        return "free".equals(m) ? "free" : "host";
    }

    public static boolean isAuthoritative(JSONObject room, String memberId) {
        if (room == null) return false;
        if (memberId == null || memberId.isEmpty()) return false;
        // 自由共控：谁操作谁权威（限流在 Api.applyPlayback 里做）。
        if ("free".equals(controlModeOf(room))) return true;
        if (memberId.equals(hostIdOf(room))) return true;
        // 同一登录用户换设备/重开 App：memberId 是进程内的，新 id 不等于 host，
        // 但它仍然是房主本人（owner_id 相同）→ 仍算权威，否则房里没人能控播放。
        // 没登录的房间（owner_id 为空）行为不变。
        String ownerId = str(room, "owner_id", "");
        if (!ownerId.isEmpty()) {
            JSONArray list = room.optJSONArray("members");
            if (list != null) {
                for (int i = 0; i < list.length(); i++) {
                    JSONObject m = list.optJSONObject(i);
                    if (m == null) continue;
                    if (memberId.equals(str(m, "id", ""))
                            && ownerId.equals(str(m, "user_id", ""))) {
                        return true;
                    }
                }
            }
        }
        String ctrl = str(room, "control", "");
        return !ctrl.isEmpty() && ctrl.equals(memberId);
    }

    /**
     * 房间的房主 memberId：优先 host 字段（必须是 "m_" 开头的 id），
     * 老数据 host 存的是名字时，回落到 members 里 role=host/owner 的第一条 id。
     */
    public static String hostIdOf(JSONObject room) {
        if (room == null) return "";
        String hid = str(room, "host", "");
        if ("null".equals(hid)) hid = "";
        if (!hid.isEmpty() && hid.startsWith("m_")) return hid;
        if ("".equals(hid)) {
            String oid = str(room, "owner_id", "");
            if (!"null".equals(oid) && !oid.isEmpty() && oid.startsWith("m_")) return oid;
        }
        JSONArray mem = room.optJSONArray("members");
        for (int i = 0; mem != null && i < mem.length(); i++) {
            JSONObject m = mem.optJSONObject(i);
            if (m == null) continue;
            String role = str(m, "role", "");
            if ("host".equals(role) || "owner".equals(role) || m.optBoolean("isHost", false)) {
                String id = str(m, "id", "");
                if (!id.isEmpty()) return id;
            }
        }
        return "";
    }

    /**
     * 签一个新成员：memberId 是房间内的身份，和 user_id 不是一回事
     * （同一个人可以多端进同一房，每端一个 memberId）。
     */
    public synchronized JSONObject addMember(JSONObject room, String name, boolean isHost) {
        return addMember(room, name, isHost, false);
    }

    public synchronized JSONObject addMember(JSONObject room, String name, boolean isHost, boolean bot) {
        JSONObject m = new JSONObject();
        JSONArray mem = room == null ? null : room.optJSONArray("members");
        if (mem == null) {
            mem = new JSONArray();
            try {
                if (room != null) room.put("members", mem);
            } catch (Throwable ignored) {
            }
        }
        try {
            m.put("id", "m_" + Long.toString(System.currentTimeMillis(), 36)
                    + Integer.toString((int) (Math.random() * 1296), 36));
            m.put("token", java.util.UUID.randomUUID().toString());
            m.put("name", name == null || name.isEmpty() ? "guest" : name);
            m.put("isHost", isHost);
            m.put("role", isHost ? "host" : "guest");
            // D28：纯显示标记（🤖），不参与任何权限判断；房间快照原样序列化会自动带出去
            m.put("bot", bot);
        // C1：审批制房间的成员默认未批准；房主与非审批房间直接批准
        m.put("approved", Boolean.valueOf(isHost || !room.optBoolean("approval", false)));
            m.put("muted", false);
            m.put("kicked", false);
            m.put("joinedAt", System.currentTimeMillis());
            mem.put(m);
            save();
        } catch (Throwable ignored) {
        }
        return m;
    }

    /** 踢人：标记 kicked 并保留记录，重连带旧 memberToken 会被 4005 拒 */
    public synchronized JSONObject memberById(String code, String memberId) {
        JSONObject room = rooms.get(code);
        JSONArray mem = room == null ? null : room.optJSONArray("members");
        for (int i = 0; mem != null && i < mem.length(); i++) {
            JSONObject mm = mem.optJSONObject(i);
            if (mm != null && memberId.equals(mm.optString("id", ""))) return mm;
        }
        return null;
    }

    public synchronized void markKicked(JSONObject room, String memberId) {
        if (room == null || memberId == null) return;
        JSONArray mem = room.optJSONArray("members");
        if (mem == null) return;
        for (int i = 0; i < mem.length(); i++) {
            JSONObject m = mem.optJSONObject(i);
            if (m != null && memberId.equals(m.optString("id", ""))) {
                try {
                    m.put("kicked", true);
                    save();
                } catch (Throwable ignored) {
                }
                return;
            }
        }
    }

    /** 禁言开关：只改成员的 muted 字段（房主校验在调用方做） */
    public static void setMuted(JSONObject room, String memberId, boolean muted) {
        if (room == null || memberId == null) return;
        JSONArray mem = room.optJSONArray("members");
        if (mem == null) return;
        for (int i = 0; i < mem.length(); i++) {
            JSONObject m = mem.optJSONObject(i);
            if (m == null) continue;
            if (memberId.equals(m.optString("id", ""))) {
                try {
                    m.put("muted", muted);
                } catch (Throwable ignored) {
                }
                return;
            }
        }
    }

    /**
     * 移交房主：原房主降成 guest、新成员升成 host，并把 room.host / room.host_id
     * 两个字段都改成新的 memberId（roomSnapshot 读 host，Api 的 GET 也读 host，
     * 老数据里还有 host_id 这一份，三个一起改才不会出现「两个房主」）。
     */
    public synchronized void setHost(String code, String newHostId) {
        JSONObject room = code == null ? null : rooms.get(code);
        if (room == null || newHostId == null || newHostId.isEmpty()) return;
        String oldHost = hostIdOf(room);
        JSONArray mem = room.optJSONArray("members");
        boolean found = false;
        for (int i = 0; mem != null && i < mem.length(); i++) {
            JSONObject m = mem.optJSONObject(i);
            if (m == null) continue;
            String id = m.optString("id", "");
            if (id.isEmpty()) continue;
            try {
                if (id.equals(newHostId)) {
                    m.put("role", "host");
                    m.put("isHost", true);
                    found = true;
                } else if (id.equals(oldHost)) {
                    // 只降原房主一个人，别把其他人也顺手改了
                    m.put("role", "guest");
                    m.put("isHost", false);
                }
            } catch (Throwable ignored) {
            }
        }
        if (!found) return;
        try {
            room.put("host", newHostId);
            room.put("host_id", newHostId);
            save();
        } catch (Throwable ignored) {
        }
    }

    /** C3：审批结果写回成员记录（房主校验在调用方做） */
    public synchronized void setApproved(String code, String memberId, boolean approved) {
        JSONObject room = rooms.get(code);
        if (room == null || memberId == null) return;
        JSONArray mem = room.optJSONArray("members");
        if (mem == null) return;
        for (int i = 0; i < mem.length(); i++) {
            JSONObject m = mem.optJSONObject(i);
            if (m == null) continue;
            if (memberId.equals(m.optString("id", ""))) {
                try {
                    m.put("approved", approved);
                    save();
                } catch (Throwable ignored) {
                }
                return;
            }
        }
    }

    /** C4：live 人数 = 未踢出 且 已批准；pending 不占名额 */
    public static int liveMembers(JSONObject room) {
        if (room == null) return 0;
        JSONArray mem = room.optJSONArray("members");
        int n = 0;
        for (int i = 0; mem != null && i < mem.length(); i++) {
            JSONObject m = mem.optJSONObject(i);
            if (m == null) continue;
            if (m.optBoolean("kicked", false)) continue;
            if (!m.optBoolean("approved", false)) continue;
            n++;
        }
        return n;
    }

    /** C4：容量上限，默认 20，读不到就按 20 */
    public static int maxMembers(JSONObject room) {
        return room == null ? 20 : room.optInt("max_members", 20);
    }

    public JSONObject findRoom(String code) {
        if (code == null) return null;
        return rooms.get(code.trim());
    }

    public String newRoomCode() {
        for (int i = 0; i < 5000; i++) {
            int n = 100000 + (int) (Math.random() * 900000);
            String c = String.valueOf(n);
            if (!rooms.containsKey(c)) return c;
        }
        return String.valueOf(System.currentTimeMillis() % 1000000);
    }

    // ---------------------------------------------------------------- 收藏 / 历史

    public JSONArray favOf(String email) {
        JSONArray a = favorites.get(email);
        if (a == null) {
            a = new JSONArray();
            favorites.put(email, a);
        }
        return a;
    }

    public JSONArray watchOf(String email) {
        JSONArray a = watches.get(email);
        if (a == null) {
            a = new JSONArray();
            watches.put(email, a);
        }
        return a;
    }

    // ---------------------------------------------------------------- 工具

    /** 房间内随机 id（base36，10 位）。 */
    public static String randId(int n) {
        StringBuilder sb = new StringBuilder();
        String alphabet = "0123456789abcdefghijklmnopqrstuvwxyz";
        java.util.Random rnd = new java.util.Random();
        for (int i = 0; i < n; i++) sb.append(alphabet.charAt(rnd.nextInt(alphabet.length())));
        return sb.toString();
    }

    public static String nowIso() {        return new java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", java.util.Locale.US)
                .format(new java.util.Date());
    }

    public static String str(JSONObject o, String k) {
        return str(o, k, "");
    }

    public static String str(JSONObject o, String k, String def) {
        if (o == null) return def;
        Object v = o.opt(k);
        if (v == null || v == JSONObject.NULL) return def;
        String s = String.valueOf(v);
        return s.isEmpty() ? def : s;
    }

    // ---------------------------------------------------------------- 持久化

    private File f(String name) {
        return new File(dir, name);
    }

    public synchronized void save() {
        try {
            JSONObject u = new JSONObject();
            for (Map.Entry<String, JSONObject> e : users.entrySet()) {
                u.put(e.getKey(), e.getValue());
            }
            JSONObject t = new JSONObject();
            for (Map.Entry<String, String> e : tokens.entrySet()) {
                t.put(e.getKey(), e.getValue());
            }
            JSONObject root = new JSONObject();
            root.put("users", u);
            root.put("tokens", t);
            write(f("users.json"), root.toString());

            JSONObject r = new JSONObject();
            for (Map.Entry<String, JSONObject> e : rooms.entrySet()) {
                r.put(e.getKey(), e.getValue());
            }
            write(f("rooms.json"), r.toString());

            JSONObject m = new JSONObject();
            m.put("announcements", announcements);
            JSONObject fav = new JSONObject();
            for (Map.Entry<String, JSONArray> e : favorites.entrySet()) fav.put(e.getKey(), e.getValue());
            JSONObject w = new JSONObject();
            for (Map.Entry<String, JSONArray> e : watches.entrySet()) w.put(e.getKey(), e.getValue());
            JSONObject c = new JSONObject();
            for (Map.Entry<String, JSONObject> e : couples.entrySet()) c.put(e.getKey(), e.getValue());
            m.put("favorites", fav);
            m.put("watches", w);
            m.put("couples", c);
            m.put("peer", peer);
            m.put("relay", relay);
            m.put("externalBackend", externalBackend);
            m.put("tunnelUrl", tunnelUrl);
            m.put("ddnsHost", ddnsHost);
            m.put("ddnsProvider", ddnsProvider);
            m.put("ddnsToken", ddnsToken);
            m.put("ddnsLastIp", ddnsLastIp);
            m.put("ddnsLastAt", ddnsLastAt);
            m.put("ddnsLastResult", ddnsLastResult);
            m.put("relayToken", relayToken);
            m.put("meshIp", meshIp);
            m.put("defaultMode", defaultMode);
            m.put("roomSecret", ensureSecret());
            write(f("misc.json"), m.toString());
        } catch (Throwable ignored) {
        }
    }

    private void load() {
        try {
            JSONObject root = new JSONObject(read(f("users.json")));
            JSONObject u = root.optJSONObject("users");
            if (u != null) {
                java.util.Iterator<String> it = u.keys();
                while (it.hasNext()) {
                    String k = it.next();
                    JSONObject v = u.optJSONObject(k);
                    if (v != null) users.put(k, v);
                }
            }
            JSONObject t = root.optJSONObject("tokens");
            if (t != null) {
                java.util.Iterator<String> it = t.keys();
                while (it.hasNext()) {
                    String k = it.next();
                    tokens.put(k, t.optString(k));
                }
            }
        } catch (Throwable ignored) {
        }
        try {
            JSONObject r = new JSONObject(read(f("rooms.json")));
            java.util.Iterator<String> it = r.keys();
            while (it.hasNext()) {
                String k = it.next();
                JSONObject v = r.optJSONObject(k);
                if (v != null) rooms.put(k, v);
            }
        } catch (Throwable ignored) {
        }
        try {
            JSONObject m = new JSONObject(read(f("misc.json")));
            peer = m.optString("peer", "");
            relay = m.optString("relay", "");
            externalBackend = m.optString("externalBackend", "");
            tunnelUrl = m.optString("tunnelUrl", "");
            ddnsHost = m.optString("ddnsHost", "");
            ddnsProvider = m.optString("ddnsProvider", "");
            ddnsToken = m.optString("ddnsToken", "");
            ddnsLastIp = m.optString("ddnsLastIp", "");
            ddnsLastAt = m.optLong("ddnsLastAt", 0L);
            ddnsLastResult = m.optString("ddnsLastResult", "");
            relayToken = m.optString("relayToken", "");
            meshIp = m.optString("meshIp", "");
            defaultMode = m.optString("defaultMode", "");
            roomSecret = m.optString("roomSecret", "");
            JSONArray a = m.optJSONArray("announcements");
            if (a != null && a.length() > 0) announcements = a;
            JSONObject fav = m.optJSONObject("favorites");
            if (fav != null) {
                java.util.Iterator<String> it = fav.keys();
                while (it.hasNext()) {
                    String k = it.next();
                    JSONArray v = fav.optJSONArray(k);
                    if (v != null) favorites.put(k, v);
                }
            }
            JSONObject w = m.optJSONObject("watches");
            if (w != null) {
                java.util.Iterator<String> it = w.keys();
                while (it.hasNext()) {
                    String k = it.next();
                    JSONArray v = w.optJSONArray(k);
                    if (v != null) watches.put(k, v);
                }
            }
            JSONObject c = m.optJSONObject("couples");
            if (c != null) {
                java.util.Iterator<String> it = c.keys();
                while (it.hasNext()) {
                    String k = it.next();
                    JSONObject v = c.optJSONObject(k);
                    if (v != null) couples.put(k, v);
                }
            }
        } catch (Throwable ignored) {
        }
        // E3 / A1：cloudflared 是 App 的子进程，进程一死旧隧道 URL 必然失效。
        // 启动时无条件清掉，否则 addrs 会一直挂着一条连不上的死链。
        String oldTunnel = tunnelUrl == null ? "" : tunnelUrl;
        tunnelUrl = "";
        android.util.Log.i("YQK-TUN", "[YQK-TUN] boot clear tunnelUrl old=" + oldTunnel);
        if (!oldTunnel.isEmpty()) {
            try {
                save();
            } catch (Throwable t) {
                android.util.Log.w("YQK-TUN", "[YQK-TUN] boot clear save fail " + t);
            }
        }
    }

    private static void write(File f, String s) throws Exception {
        FileOutputStream fo = new FileOutputStream(f);
        try {
            fo.write(s.getBytes(UTF8));
            fo.flush();
        } finally {
            try {
                fo.close();
            } catch (Throwable ignored) {
            }
        }
    }

    private static String read(File f) throws Exception {
        if (!f.exists()) return "{}";
        FileInputStream fi = new FileInputStream(f);
        try {
            ByteArrayOutputStream bo = new ByteArrayOutputStream();
            byte[] buf = new byte[4096];
            int n;
            while ((n = fi.read(buf)) > 0) bo.write(buf, 0, n);
            return new String(bo.toByteArray(), UTF8);
        } finally {
            try {
                fi.close();
            } catch (Throwable ignored) {
            }
        }
    }

    public synchronized List<JSONObject> allRooms() {
        return new ArrayList<JSONObject>(rooms.values());
    }
}
