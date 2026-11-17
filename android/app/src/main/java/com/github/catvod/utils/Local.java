package com.github.catvod.utils;

/**
 * 最小实现（本仓库自写，不替换 FongMi 原文件——原 Local.java 依赖 Runtime 与 OkHttp 5 的 LocalServer）。
 *
 * Spider 里 `public Local local;` 只用其类型；这里给几个空方法，保证引用它的源能编译。
 */
public class Local {

    public String getUrl() {
        return "";
    }

    public void stop() {
    }
}
