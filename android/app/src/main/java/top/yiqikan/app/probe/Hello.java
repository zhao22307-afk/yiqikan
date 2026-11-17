package top.yiqikan.app.probe;

import android.content.Context;
import android.os.Handler;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.io.PrintWriter;
import java.io.StringWriter;
import java.lang.reflect.Field;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.lang.reflect.Modifier;
import java.util.function.Consumer;

import dalvik.system.DexClassLoader;

/**
 * 探针：只为验证 Java 源集与 TVBox 兼容层是否通（P-1 / P0a / P0b / P0c）。
 * 不参与业务逻辑，验收完可以整目录删掉。
 */
public class Hello {

    private static final String JAR_IN_CACHE = "spider.jar";
    private static final String DEX_OUT = "tvbox_dex";

    private static final String[] CANDIDATES = new String[]{
            "Douban", "Bili", "AmuBiliV2", "Kugou", "Kuwo", "RenRen", "Gulu", "Hxq",
            "Feiyu", "SP360", "MeijuMi", "Djuu", "YGP", "XingChen", "New6v", "Sou4K",
            "JianPian", "HDmoli", "SeedHub", "TingTingyou", "YST", "Wogg"
    };

    public static String ping() {
        return "hello-from-java";
    }

    public static String netGet(String url) {
        try {
            String body = new com.github.catvod.net.Net().get(url);
            String head = body == null ? "null" : body.substring(0, Math.min(60, body.length())).replace('\n', ' ');
            return "OK len=" + (body == null ? -1 : body.length()) + " head=" + head;
        } catch (Throwable t) {
            Throwable e = real(t);
            return "ERR " + e.getClass().getName() + ": " + e.getMessage();
        }
    }

    public static String loadSpider() {
        try {
            Class<?> c = Class.forName("com.github.catvod.crawler.Spider");
            Object o = Class.forName("com.github.catvod.crawler.SpiderNull")
                    .getDeclaredConstructor().newInstance();
            return "OK " + c.getName() + " / " + o.getClass().getSimpleName();
        } catch (Throwable t) {
            return "ERR " + t.getClass().getName() + ": " + t.getMessage();
        }
    }

    public static String newAlist() {
        try {
            Class<?> c = Class.forName("com.github.catvod.spider.AList");
            Object o = c.getDeclaredConstructor().newInstance();
            return "OK " + o.getClass().getName();
        } catch (Throwable t) {
            return "ERR " + t.getClass().getName() + ": " + t.getMessage();
        }
    }

    /** P0c 主线程版：完全按任务书——DexClassLoader 与 searchContent 都在主线程。 */
    public static void probeJar(Context ctx, String jarPath, String cls, String key,
                                Handler main, Consumer<String> done) {
        main.post(() -> done.accept(probeOne(ctx, jarPath, cls, key, "")));
    }

    /** P0c 主线程扫描版：只试不耗时，同样在主线程，所以 HTTP 会被 NetworkOnMainThreadException 拦。 */
    public static void probeJarScan(Context ctx, String jarPath, String key,
                                    Handler main, Consumer<String> done) {
        main.post(() -> done.accept(scanOnThisThread(ctx, jarPath, key)));
    }

    /**
     * P0c 后台调用版：DexClassLoader 仍在主线程装载（任务书要求），
     * 但真正会发 HTTP 的 searchContent 放到工作线程——Android 不允许主线程做网络。
     */
    public static void probeJarBg(Context ctx, String jarPath, String key,
                                  Handler main, Consumer<String> done) {
        main.post(() -> {
            File jar = null;
            DexClassLoader cl = null;
            String loadErr = null;
            try {
                jar = prepareJar(ctx, jarPath);
                if (jar == null) loadErr = "ERR java.io.FileNotFoundException: no such jar " + jarPath;
                else cl = newLoader(ctx, jar);
            } catch (Throwable t) {
                loadErr = "ERR " + real(t).getClass().getName() + ": " + real(t).getMessage();
            }
            final DexClassLoader loader = cl;
            final String err = loadErr;
            new Thread(() -> {
                final String r = loader == null ? err : scanWithLoader(ctx, loader, key);
                main.post(() -> done.accept(r));
            }, "yqk-spider-probe").start();
        });
    }

    // ---------------- 内部实现 ----------------

    private static String scanOnThisThread(Context ctx, String jarPath, String key) {
        try {
            File jar = prepareJar(ctx, jarPath);
            if (jar == null) return "ERR java.io.FileNotFoundException: no such jar " + jarPath;
            return scanWithLoader(ctx, newLoader(ctx, jar), key);
        } catch (Throwable t) {
            Throwable e = real(t);
            return "ERR " + e.getClass().getName() + ": " + e.getMessage();
        }
    }

    private static String scanWithLoader(Context ctx, DexClassLoader cl, String key) {
        StringBuilder sb = new StringBuilder();
        for (String name : CANDIDATES) {
            String r = callOne(ctx, cl, "com.github.catvod.spider." + name, key, "");
            if (r.startsWith("OK ") && r.contains("\"list\"") && r.length() > 60 && !r.startsWith("OK {\"list\":[]")) {
                return "FIRST=" + name + " => " + r;
            }
            sb.append(name).append(": ").append(r.length() > 70 ? r.substring(0, 70) + "…" : r).append(" || ");
        }
        return "NONE " + sb;
    }

    private static String probeOne(Context ctx, String jarPath, String cls, String key, String extend) {
        try {
            File jar = prepareJar(ctx, jarPath);
            if (jar == null) return "ERR java.io.FileNotFoundException: no such jar " + jarPath;
            return callOne(ctx, newLoader(ctx, jar), cls, key, extend);
        } catch (Throwable t) {
            return errorText(t);
        }
    }

    private static String callOne(Context ctx, DexClassLoader cl, String cls, String key, String extend) {
        try {
            Class<?> c = Class.forName(cls, true, cl);
            Object o = c.getDeclaredConstructor().newInstance();
            inject(o, c);
            try {
                Method init = c.getMethod("init", Context.class, String.class);
                init.invoke(o, ctx, extend);
            } catch (Throwable ignored) {
            }
            Method m = c.getMethod("searchContent", String.class, boolean.class);
            Object r;
            try {
                r = m.invoke(o, key, false);
            } catch (Throwable t) {
                throw new RuntimeException("fields{" + dumpFields(o, c) + "}", real(t));
            }
            return r == null ? "null" : r.toString();
        } catch (Throwable t) {
            return errorText(t);
        }
    }

    private static String errorText(Throwable t) {
        Throwable e = real(t);
        StringWriter sw = new StringWriter();
        e.printStackTrace(new PrintWriter(sw));
        String[] lines = sw.toString().split("\n");
        StringBuilder sb = new StringBuilder("ERR " + e.getClass().getName() + ": " + e.getMessage());
        for (int i = 0; i < Math.min(8, lines.length); i++) sb.append(" | ").append(lines[i].trim());
        return sb.toString();
    }

    private static Throwable real(Throwable t) {
        Throwable e = t;
        while (e instanceof InvocationTargetException && e.getCause() != null) e = e.getCause();
        return e;
    }

    /** 外部目录的 jar 先拷进内部 cache 并置只读（Android 14+ 拒绝加载可写目录里的 dex）。 */
    private static File prepareJar(Context ctx, String jarPath) throws Exception {
        File src = new File(jarPath);
        if (!src.isFile()) return null;
        if (src.getAbsolutePath().startsWith(ctx.getCacheDir().getAbsolutePath())) {
            src.setReadOnly();
            return src;
        }
        File dst = new File(ctx.getCacheDir(), JAR_IN_CACHE);
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
        }
        dst.setWritable(false, false);
        dst.setReadOnly();
        return dst;
    }

    private static DexClassLoader newLoader(Context ctx, File jar) {
        File out = new File(ctx.getCacheDir(), DEX_OUT);
        if (!out.exists()) out.mkdirs();
        return new DexClassLoader(jar.getAbsolutePath(), out.getAbsolutePath(), null, ctx.getClassLoader());
    }

    /** spider.jar 里的源原本由 TVBox 的 loader 注入 net/local，这里补齐。 */
    private static void inject(Object o, Class<?> c) {
        try {
            c.getField("net").set(o, new com.github.catvod.net.Net());
            c.getField("local").set(o, new com.github.catvod.utils.Local());
        } catch (Throwable ignored) {
        }
    }

    private static String dumpFields(Object o, Class<?> c) {
        StringBuilder dump = new StringBuilder();
        for (Class<?> k = c; k != null && k != Object.class; k = k.getSuperclass()) {
            for (Field f : k.getDeclaredFields()) {
                if (Modifier.isStatic(f.getModifiers())) continue;
                try {
                    f.setAccessible(true);
                    Object v = f.get(o);
                    String s = v == null ? "null" : String.valueOf(v);
                    if (s.length() > 40) s = s.substring(0, 40) + "…";
                    dump.append(f.getName()).append('=').append(s).append("; ");
                } catch (Throwable ignored) {
                }
            }
        }
        return dump.toString();
    }
}
