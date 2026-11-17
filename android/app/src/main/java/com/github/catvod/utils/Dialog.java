package com.github.catvod.utils;

import org.json.JSONObject;

/**
 * 最小实现（本仓库自写，不替换 FongMi 原文件——原 Dialog.java 依赖 Android 弹窗 UI 与 Runtime.activity()）。
 *
 * Spider 只需要 show(Callback)/close() 两个符号。没有界面时直接回一个「已取消」的 JSON，
 * 让调用方自己能判空，而不是伪造用户输入。
 */
public class Dialog {

    public interface Callback {
        void onResult(JSONObject json);
    }

    public JSONObject show(JSONObject options, Callback callback) throws Exception {
        JSONObject cancel = new JSONObject();
        cancel.put("action", "cancel");
        if (callback != null) callback.onResult(cancel);
        return cancel;
    }

    public void close() {
    }
}
