package com.orhanobut.logger;

import android.util.Log;

/**
 * 最小 stub：catvod 只用到 `Logger.t(tag).d(...)` 这一种链式写法。
 * 真库是 jcenter 上的 com.orhanobut:logger，这里不引依赖，直接转 android.util.Log。
 * 只补签名，不含原库的格式化/落盘等逻辑。
 */
public final class Logger {

    private static String tag = "catvod";

    private Logger() {
    }

    public static Logger t(String t) {
        Logger inst = new Logger();
        tag = t == null ? "catvod" : t;
        return inst;
    }

    public Logger d(String msg, Object... args) {
        Log.d(tag, fmt(msg, args));
        return this;
    }

    public Logger e(String msg, Object... args) {
        Log.e(tag, fmt(msg, args));
        return this;
    }

    public Logger i(String msg, Object... args) {
        Log.i(tag, fmt(msg, args));
        return this;
    }

    public Logger v(String msg, Object... args) {
        Log.v(tag, fmt(msg, args));
        return this;
    }

    public Logger w(String msg, Object... args) {
        Log.w(tag, fmt(msg, args));
        return this;
    }

    public Logger e(Throwable th, String msg, Object... args) {
        Log.e(tag, fmt(msg, args), th);
        return this;
    }

    public Logger json(String json) {
        Log.d(tag, json == null ? "null" : json);
        return this;
    }

    private static String fmt(String msg, Object... args) {
        if (msg == null) return "null";
        if (args == null || args.length == 0) return msg;
        try {
            return String.format(msg, args);
        } catch (Throwable t) {
            return msg;
        }
    }
}
