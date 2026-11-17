package com.github.catvod.crawler;

import android.content.Context;
import android.util.Log;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;

import org.json.JSONArray;
import org.json.JSONObject;

import okhttp3.MediaType;
import okhttp3.Request;
import okhttp3.RequestBody;
import okhttp3.Response;
import top.yiqikan.app.server.LocalServer;

/**
 * 改写版（本仓库自写，不拷 FongMi 原版）。
 *
 * 原版 SpiderApi 的 getAddress/getPort 依赖 ControlManager（本工程没有），
 * 其余方法是 okhttp 直连。这里按 dexdump 抓到的引用签名逐个实现：
 *   getAddress:(Z)Ljava/lang/String;      invoke-virtual
 *   getPort:()Ljava/lang/String;          invoke-virtual
 *   log:(Ljava/lang/String;)V             invoke-virtual
 *   multiReq:(Lcom/google/gson/JsonArray;)Ljava/lang/String;   invoke-virtual
 *   webParse:(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String; invoke-virtual
 *
 * 方法体未实现的会在方法上标 STUB，交付报告里逐条列出。
 */
public class SpiderApi {

    private static final String TAG = "YQK-SPIDER";

    public SpiderApi() {
    }

    public SpiderApi(Context context) {
    }

    /** 原版靠 ControlManager 拿局域网地址；本工程直接用内置服务。 */
    public String getAddress(boolean local) {
        try {
            JSONArray a = LocalServer.lanAddrs(8080);
            if (a == null || a.length() == 0) return "";
            String host = a.getJSONObject(0).optString("host", "127.0.0.1");
            return "http://" + host + ":" + getPort();
        } catch (Throwable t) {
            return "";
        }
    }

    public String getPort() {
        return "8080";
    }

    public void log(String msg) {
        Log.i(TAG, msg == null ? "" : msg);
    }

    /** 并发/批量请求：入参每一项 {url, method, headers{}, body}，回 [{url, content}]。 */
    public String multiReq(JsonArray array) {
        JSONArray out = new JSONArray();
        if (array == null) return out.toString();
        for (int i = 0; i < array.size(); i++) {
            String url = "";
            try {
                JsonObject o = array.get(i).getAsJsonObject();
                url = o.has("url") ? o.get("url").getAsString() : "";
                String method = o.has("method") ? o.get("method").getAsString() : "GET";
                String body = o.has("body") && !o.get("body").isJsonNull() ? o.get("body").getAsString() : null;
                Request.Builder b = new Request.Builder().url(url);
                if (o.has("headers") && o.get("headers").isJsonObject()) {
                    JsonObject h = o.getAsJsonObject("headers");
                    for (String k : h.keySet()) {
                        b.addHeader(k, h.get(k).getAsString());
                    }
                }
                if ("POST".equalsIgnoreCase(method)) {
                    b.post(RequestBody.create(body == null ? "" : body,
                            MediaType.parse("application/json; charset=utf-8")));
                }
                String content = "";
                Response r = null;
                try {
                    r = com.github.catvod.net.OkHttp.client().newCall(b.build()).execute();
                    content = r.body() == null ? "" : r.body().string();
                } finally {
                    if (r != null) r.close();
                }
                JSONObject one = new JSONObject();
                one.put("url", url);
                one.put("content", content);
                out.put(one);
            } catch (Throwable t) {
                Log.w(TAG, "multiReq fail url=" + url + " " + t);
            }
        }
        return out.toString();
    }

    /** STUB：按 dexdump 签名补，方法体未实现（原版走外部 web 解析服务）。 */
    public String webParse(String flag, String url) {
        Log.i(TAG, "webParse STUB flag=" + flag + " url=" + url);
        return "";
    }
}
