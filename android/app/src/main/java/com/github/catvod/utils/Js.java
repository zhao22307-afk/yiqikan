package com.github.catvod.utils;

/**
 * 最小实现（本仓库自写，不替换 FongMi 原文件——原 Js.java 依赖 com.fongmi.quickjs 运行时，本工程没有该模块）。
 *
 * Spider 里 `public final Js js = new Js();` 与 `close()` 会用到；具体 Spider 如果真要用 JS，
 * 本类会明确返回空字符串，不做静默假成功。
 */
public class Js {

    public String call(String name, Object... args) {
        return "";
    }

    public String call(String name) {
        return "";
    }

    public String call(String name, Object arg) {
        return "";
    }

    public String call(String name, Object arg1, Object arg2) {
        return "";
    }

    public String eval(String js) {
        return "";
    }

    public void close() {
    }
}
