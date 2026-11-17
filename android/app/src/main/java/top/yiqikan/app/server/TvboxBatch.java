package top.yiqikan.app.server;

import android.content.Context;
import android.os.SystemClock;
import android.util.Log;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.lang.reflect.Field;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.lang.reflect.Modifier;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.TreeMap;

import dalvik.system.DexClassLoader;

/**
 * TVBox 源批量探测器（P0c 之后的统计轮）。
 *
 * 只做一件事：把 dianshi.json 里 type=3 且 api=csp_xxx 的源顺序跑一遍，
 * 每个源 10 秒硬超时，把结果逐条打进 logcat，最后打一行汇总。
 *
 * 约束（按任务书）：
 *  - 必须由调用方放在工作线程执行（源一 search 就发 HTTP，主线程必崩）
 *  - 顺序执行，不并行（并行会串源状态）
 *  - 每个源新建实例，不复用
 *  - 异常分类：ClassNotFound / NoSuchMethod / InvocationTargetException(取 cause) / 超时 / 其他
 */
public final class TvboxBatch {

    private static final String TAG = "YQK-TVBOX";
    private static final String ASSET = "tvbox/dianshi.json";
    private static final String KEYWORD = "流浪地球";
    private static final long PER_SOURCE_MS = 10_000L;
    private static final String JAR_NAME = "spider.jar";
    private static final String DEX_OUT = "tvbox_dex";

    private TvboxBatch() {
    }

    /** 入口：读配置 → 逐个源跑 → 返回汇总字符串。调用方负责工作线程。 */
    public static String runAll(Context ctx) {
        final long t0 = SystemClock.elapsedRealtime();
        int total = 0, ok = 0, empty = 0, err = 0, timeout = 0;
        final List<String> okList = new ArrayList<>();
        final Map<String, Integer> errKinds = new TreeMap<>();

        File jar = null;
        DexClassLoader loader = null;
        String loadErr = null;
        try {
            jar = prepareJar(ctx);
            if (jar == null) {
                loadErr = "jar not found";
            } else {
                File out = new File(ctx.getCacheDir(), DEX_OUT);
                if (!out.exists()) out.mkdirs();
                loader = new DexClassLoader(jar.getAbsolutePath(), out.getAbsolutePath(), null,
                        ctx.getClassLoader());
            }
        } catch (Throwable t) {
            loadErr = t.getClass().getSimpleName() + ": " + msg(t);
        }
        if (loadErr != null) {
            Log.i(TAG, "SUMMARY total=0 ok=0 empty=0 err=0 timeout=0 load=" + loadErr);
            return "ERR load=" + loadErr;
        }

        JSONArray sites;
        try {
            sites = readSites(ctx);
        } catch (Throwable t) {
            Log.i(TAG, "SUMMARY total=0 ok=0 empty=0 err=0 timeout=0 config=" + msg(t));
            return "ERR config=" + msg(t);
        }

        final List<JSONObject> targets = new ArrayList<>();
        int type3 = 0, csp = 0;
        for (int i = 0; i < sites.length(); i++) {
            JSONObject s = sites.optJSONObject(i);
            if (s == null) continue;
            if (s.optInt("type", -1) != 3) continue;
            type3++;
            String api = s.optString("api", "");
            if (!api.startsWith("csp_")) continue;
            csp++;
            targets.add(s);
        }
        Log.i(TAG, "config sites=" + sites.length() + " type3=" + type3 + " csp=" + csp);

        for (JSONObject s : targets) {
            total++;
            final String key = s.optString("key", "?");
            final String api = s.optString("api", "");
            final String ext = s.optString("ext", "");
            final String cls = "com.github.catvod.spider." + api.substring(4);

            final Object[] box = new Object[1];
            final Context appCtx = ctx.getApplicationContext();
            final DexClassLoader cl = loader;
            Thread worker = new Thread(new Runnable() {
                @Override
                public void run() {
                    box[0] = runOne(appCtx, cl, key, cls, ext);
                }
            }, "tvbox-src");
            long st = SystemClock.elapsedRealtime();
            worker.start();
            try {
                worker.join(PER_SOURCE_MS);
            } catch (InterruptedException ie) {
                Thread.currentThread().interrupt();
            }
            long ms = SystemClock.elapsedRealtime() - st;

            if (worker.isAlive()) {
                worker.interrupt();
                timeout++;
                bump(errKinds, "Timeout");
                Log.i(TAG, "site=" + key + " cls=" + cls + " fail Timeout: >" + PER_SOURCE_MS + "ms");
                continue;
            }
            String r = box[0] == null ? "fail Other: no result" : String.valueOf(box[0]);
            if (r.startsWith("ok ")) {
                int n = Integer.parseInt(r.substring(3).trim());
                if (n > 0) {
                    ok++;
                    okList.add(key + "(" + n + ")");
                } else {
                    empty++;
                }
                Log.i(TAG, "site=" + key + " cls=" + cls + " ok n=" + n + " ms=" + ms);
            } else {
                err++;
                String kind = r.startsWith("fail ") ? r.substring(5) : r;
                int colon = kind.indexOf(':');
                bump(errKinds, colon > 0 ? kind.substring(0, colon).trim() : kind.trim());
                Log.i(TAG, "site=" + key + " cls=" + cls + " " + (r.startsWith("fail ") ? r : "fail Other: " + r));
            }
        }

        long all = SystemClock.elapsedRealtime() - t0;
        Log.i(TAG, "SUMMARY total=" + total + " ok=" + ok + " empty=" + empty + " err=" + err
                + " timeout=" + timeout + " ms=" + all);
        StringBuilder sb = new StringBuilder();
        sb.append("total=").append(total).append(" ok=").append(ok).append(" empty=").append(empty)
                .append(" err=").append(err).append(" timeout=").append(timeout).append(" ms=").append(all);
        sb.append(" | ok=").append(okList);
        sb.append(" | errors=").append(errKinds);
        return sb.toString();
    }

    // ---------------- 单源 ----------------

    private static String runOne(Context ctx, DexClassLoader cl, String key, String cls, String ext) {
        try {
            Class<?> c = Class.forName(cls, true, cl);
            Object o = c.getDeclaredConstructor().newInstance();
            inject(o, c);
            try {
                Method init = c.getMethod("init", Context.class, String.class);
                init.invoke(o, ctx, ext == null ? "" : ext);
            } catch (NoSuchMethodException ignore) {
                // 有些源没有 init(Context,String)，直接 search 也行
            }
            Method search = c.getMethod("searchContent", String.class, boolean.class);
            Object r = search.invoke(o, KEYWORD, false);
            String text = r == null ? "" : String.valueOf(r);
            return "ok " + countVodId(text);
        } catch (Throwable t) {
            Throwable e = real(t);
            String kind;
            if (e instanceof ClassNotFoundException) kind = "ClassNotFound";
            else if (e instanceof NoSuchMethodException) kind = "NoSuchMethod";
            else if (e instanceof InvocationTargetException) kind = "InvocationTarget";
            else if (e instanceof NoClassDefFoundError) kind = "NoClassDefFound";
            else if (e instanceof NoSuchFieldException) kind = "NoSuchField";
            else kind = e.getClass().getSimpleName();
            return "fail " + kind + ": " + msg(e);
        }
    }

    private static int countVodId(String text) {
        int n = 0, idx = 0;
        while ((idx = text.indexOf("vod_id", idx)) >= 0) {
            n++;
            idx += 6;
        }
        return n;
    }

    /** spider.jar 里的源由 TVBox 的 loader 注入 net/local，这里补齐（与探针一致）。 */
    private static void inject(Object o, Class<?> c) {
        try {
            c.getField("net").set(o, new com.github.catvod.net.Net());
        } catch (Throwable ignored) {
        }
        try {
            c.getField("local").set(o, new com.github.catvod.utils.Local());
        } catch (Throwable ignored) {
        }
    }

    private static Throwable real(Throwable t) {
        Throwable e = t;
        while (e instanceof InvocationTargetException && e.getCause() != null) e = e.getCause();
        return e;
    }

    private static String msg(Throwable t) {
        String m = t.getMessage();
        if (m == null) m = t.toString();
        m = m.replace('\n', ' ');
        return m.length() > 80 ? m.substring(0, 80) : m;
    }

    // ---------------- 配置与 jar ----------------

    private static JSONArray readSites(Context ctx) throws Exception {
        String text = readAsset(ctx, ASSET);
        JSONObject root = new JSONObject(text);
        JSONArray arr = root.optJSONArray("sites");
        return arr == null ? new JSONArray() : arr;
    }

    private static String readAsset(Context ctx, String name) throws Exception {
        InputStream in = ctx.getAssets().open(name);
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        byte[] buf = new byte[8192];
        int n;
        while ((n = in.read(buf)) > 0) out.write(buf, 0, n);
        in.close();
        return new String(out.toByteArray(), "UTF-8");
    }

    /**
     * 找 spider.jar：优先外部 cache（adb push 的放置点），其次内部 cache，
     * 目标文件必须落在内部 cache 且置只读（Android 14+ 拒绝从可写目录加载 dex）。
     */
    private static File prepareJar(Context ctx) throws Exception {
        // 自检：jar 在不在、多大、cache 指哪 —— 源静默 n=0 时先看这一行
        File jarProbe = new File(ctx.getCacheDir(), JAR_NAME);
        Log.i(TAG, "[YQK-TVBOX] jar=" + (jarProbe.exists() ? jarProbe.length() : -1) + " cache=" + ctx.getCacheDir());
        File[] candidates = new File[]{
                new File(ctx.getExternalCacheDir(), JAR_NAME),
                new File(ctx.getCacheDir(), JAR_NAME),
                new File("/sdcard/Android/data/top.yiqikan.app.debug/cache/" + JAR_NAME),
                new File("/sdcard/Android/data/top.yiqikan.app/cache/" + JAR_NAME),
        };
        File src = null;
        for (File f : candidates) {
            if (f != null && f.isFile() && f.length() > 0) {
                src = f;
                break;
            }
        }
        if (src == null) return null;

        File dst = new File(ctx.getCacheDir(), JAR_NAME);
        if (src.getAbsolutePath().equals(dst.getAbsolutePath())) {
            if (dst.canWrite()) {
                dst.setWritable(false, false);
                dst.setReadOnly();
            }
            return dst;
        }
        boolean needCopy = !dst.isFile() || dst.length() != src.length();
        if (needCopy) {
            if (dst.exists()) {
                dst.setWritable(true, false);
                dst.delete();
            }
            try (InputStream in = new FileInputStream(src);
                 OutputStream out = new FileOutputStream(dst)) {
                byte[] buf = new byte[8192];
                int n;
                while ((n = in.read(buf)) > 0) out.write(buf, 0, n);
            }
            dst.setWritable(false, false);
            dst.setReadOnly();
        }
        return dst;
    }

    private static void bump(Map<String, Integer> m, String k) {
        Integer v = m.get(k);
        m.put(k, v == null ? 1 : v + 1);
    }

    /** 备用：按名字列一下 jar 里的源类（调试用，未在验收路径上）。 */
    static String describe(Class<?> c) {
        StringBuilder sb = new StringBuilder(c.getName()).append(" fields=");
        for (Field f : c.getDeclaredFields()) {
            if (Modifier.isStatic(f.getModifiers())) continue;
            sb.append(f.getName()).append(',');
        }
        return sb.toString();
    }

    static String fmtMs(long ms) {
        return String.format(Locale.US, "%.1fs", ms / 1000.0);
    }

    // ---------------- P1：单源 搜索 / 详情 / 播放 ----------------

    /** 单次调用总超时（不是每源 15 秒 × 113，是这一调 15 秒）。 */
    private static final long CALL_TIMEOUT_MS = 15_000L;

    /** DexClassLoader 单例：同一个 jar 只 new 一次，避免每源重复加载 dex。 */
    private static DexClassLoader LOADER;
    private static long LOADER_LEN = -1L;

    private interface Call {
        Object run(Object spider) throws Throwable;
    }

    public static String searchOne(android.content.Context ctx, String api, String ext, String kw) {
        return call(ctx, api, ext, "search", spider -> {
            Method m = spider.getClass().getMethod("searchContent", String.class, boolean.class);
            return m.invoke(spider, kw == null ? "" : kw, false);
        });
    }

    public static String detailOne(android.content.Context ctx, String api, String ext, String id) {
        return call(ctx, api, ext, "detail", spider -> {
            Method m = spider.getClass().getMethod("detailContent", List.class);
            List<String> ids = new ArrayList<>();
            ids.add(id == null ? "" : id);
            return m.invoke(spider, ids);
        });
    }

    public static String playOne(android.content.Context ctx, String api, String ext,
                                 String flag, String pid) {
        return call(ctx, api, ext, "play", spider -> {
            Method m = spider.getClass().getMethod("playerContent", String.class, String.class, List.class);
            return m.invoke(spider, flag == null ? "" : flag, pid == null ? "" : pid,
                    new ArrayList<String>());
        });
    }

    private static String call(Context ctx, String api, String ext, String what, Call op) {
        final long t0 = SystemClock.elapsedRealtime();
        String cls = clsOf(api);
        final Object[] box = new Object[2];
        Thread t = new Thread(() -> {
            try {
                DexClassLoader cl = loader(ctx);
                Class<?> c = Class.forName(cls, true, cl);
                Object spider = c.getDeclaredConstructor().newInstance();
                inject(spider, c);
                try {
                    Method init = c.getMethod("init", Context.class, String.class);
                    init.invoke(spider, ctx, ext == null ? "" : ext);
                } catch (NoSuchMethodException ignore) {
                    // 部分源没有 init(Context,String)
                }
                box[0] = op.run(spider);
            } catch (Throwable e) {
                box[1] = real(e);
            }
        }, "yqk-tvbox-" + what);
        t.start();
        try {
            t.join(CALL_TIMEOUT_MS);
        } catch (InterruptedException ie) {
            Thread.currentThread().interrupt();
        }
        long ms = SystemClock.elapsedRealtime() - t0;
        if (t.isAlive()) {
            return "{\"error\":\"" + esc(cls.substring(cls.lastIndexOf('.') + 1)) + ": " + what
                    + " 超时 " + (CALL_TIMEOUT_MS / 1000) + "s\"}";
        }
        if (box[1] != null) {
            Throwable e = (Throwable) box[1];
            String m = msg(e);
            return "{\"error\":\"" + esc(e.getClass().getSimpleName() + ": " + m) + "\"}";
        }
        String text = box[0] == null ? "" : String.valueOf(box[0]);
        Log.i(TAG, what + " api=" + api + " ms=" + ms + " len=" + text.length());
        return text;
    }

    /** "csp_Gulu" → "com.github.catvod.spider.Gulu"。 */
    static String clsOf(String api) {
        String a = api == null ? "" : api.trim();
        if (a.startsWith("csp_")) return "com.github.catvod.spider." + a.substring(4);
        if (a.startsWith(".")) return "com.github.catvod.spider" + a;
        if (a.contains(".")) return a;
        return "com.github.catvod.spider." + a;
    }

    static synchronized DexClassLoader loader(Context ctx) throws Exception {
        File jar = prepareJar(ctx);
        if (jar == null) throw new IllegalStateException("spider.jar 未就绪（先 adb push 到 cache）");
        if (LOADER != null && LOADER_LEN == jar.length()) {
            bindInit(ctx, LOADER);
            return LOADER;
        }
        File out = new File(ctx.getCacheDir(), DEX_OUT);
        if (!out.exists()) out.mkdirs();
        LOADER = new DexClassLoader(jar.getAbsolutePath(), out.getAbsolutePath(), null,
                ctx.getClassLoader());
        LOADER_LEN = jar.length();
        bindInit(ctx, LOADER);
        return LOADER;
    }

    /**
     * 把 Application 塞进 jar 里的 com.github.catvod.spider.Init。
     *
     * csp 源大量直接调 `Init.context().getPackageName()` / `Init.context().getExternalCacheDir()`，
     * 不注入就必报 `NullPointerException: Attempt to invoke virtual method ... Context.getPackageName()`。
     * Init 的实例字段是 `c`（android.app.Application），静态入口是 `Init.get()`。
     */
    private static void bindInit(Context ctx, DexClassLoader cl) {
        try {
            Class<?> ic = Class.forName("com.github.catvod.spider.Init", true, cl);
            Object inst = null;
            try {
                inst = ic.getMethod("get").invoke(null);
            } catch (Throwable ignored) {
            }
            if (inst == null) {
                try {
                    inst = ic.getDeclaredConstructor().newInstance();
                } catch (Throwable ignored) {
                }
            }
            Object app = ctx.getApplicationContext();
            int set = 0;
            for (Field f : ic.getDeclaredFields()) {
                Class<?> t = f.getType();
                if (t != android.app.Application.class && t != Context.class) continue;
                try {
                    f.setAccessible(true);
                    if (Modifier.isStatic(f.getModifiers())) f.set(null, app);
                    else if (inst != null) f.set(inst, app);
                    else continue;
                    set++;
                } catch (Throwable ignored) {
                }
            }
            Log.i(TAG, "bindInit fields=" + set);
        } catch (Throwable t) {
            Log.i(TAG, "bindInit skip " + msg(t));
        }
    }

    /** JSON 字符串最小转义：够用来包异常文案。 */
    private static String esc(String s) {
        if (s == null) return "";
        StringBuilder sb = new StringBuilder(s.length() + 8);
        for (int i = 0; i < s.length(); i++) {
            char ch = s.charAt(i);
            switch (ch) {
                case '"': sb.append("\\\""); break;
                case '\\': sb.append("\\\\"); break;
                case '\n': sb.append(' '); break;
                case '\r': sb.append(' '); break;
                case '\t': sb.append(' '); break;
                default:
                    if (ch < 0x20) sb.append(' ');
                    else sb.append(ch);
            }
        }
        return sb.toString();
    }
}
