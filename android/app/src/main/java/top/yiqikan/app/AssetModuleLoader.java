package top.yiqikan.app;

import android.content.Context;
import android.content.res.AssetManager;

import com.fongmi.quickjs.ModuleLoader;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;

/**
 * 从 APK 的 assets/tvbox/ 解析 ESM 依赖（drpy2 引擎用）。
 *
 * 只做一件事：把 import 说明符规整成 assets 里的文件名并读出来。
 * 方法签名以 javap 结果为准：
 *   abstract boolean isBytecodeMode();
 *   abstract byte[] getModuleBytecode(String);
 *   abstract String getModuleStringCode(String);
 *   String moduleNormalizeName(String, String);   // 可覆盖
 */
public class AssetModuleLoader extends ModuleLoader {

    private static final String DIR = "tvbox";

    private final AssetManager am;

    public AssetModuleLoader(AssetManager am) {
        this.am = am;
    }

    @Override
    public boolean isBytecodeMode() {
        return false;
    }

    @Override
    public byte[] getModuleBytecode(String name) {
        return null;
    }

    @Override
    public String getModuleStringCode(String name) {
        String base = (name == null ? "" : name);
        String[] candidates = new String[] { base + ".js", base + ".min.js" };
        for (String file : candidates) {
            try (InputStream in = am.open(DIR + "/" + file)) {
                ByteArrayOutputStream out = new ByteArrayOutputStream(Math.max(1024, in.available()));
                byte[] buf = new byte[8192];
                int n;
                while ((n = in.read(buf)) > 0) {
                    out.write(buf, 0, n);
                }
                return new String(out.toByteArray(), "UTF-8");
            } catch (Throwable ignored) {
                // try next candidate
            }
        }
        return null;
    }

    /** "./drpy-core-lite.min.js" -> "drpy-core-lite.min"（取最后一段、去 .js） */
    @Override
    public String moduleNormalizeName(String base, String name) {
        String s = (name == null ? "" : name).trim();
        int slash = Math.max(s.lastIndexOf('/'), s.lastIndexOf('\\'));
        if (slash >= 0) {
            s = s.substring(slash + 1);
        }
        if (s.endsWith(".js")) {
            s = s.substring(0, s.length() - 3);
        }
        return s;
    }
}
