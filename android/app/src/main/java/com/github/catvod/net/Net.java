package com.github.catvod.net;

import java.util.Collections;
import java.util.Map;
import java.util.concurrent.TimeUnit;

import okhttp3.MediaType;
import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.RequestBody;
import okhttp3.Response;
import okhttp3.ResponseBody;

/**
 * 最小实现（本仓库自写，不属于 FongMi 原文件）。
 *
 * 提供 Spider / AList / Drive 用到的 get(req/json) 三件套，底层走 OkHttp 4.12。
 * 签名与 FongMi 原版一致：不抛受检异常（原版也是 unchecked），失败抛 RuntimeException。
 * 不做原版的缓存、DnsOverHttps、代理重定向那一套。
 */
public class Net implements AutoCloseable {

    private static final MediaType JSON_TYPE = MediaType.get("application/json; charset=utf-8");
    private static final MediaType FORM_TYPE = MediaType.get("application/x-www-form-urlencoded; charset=utf-8");

    private static final String UA = "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36";

    public String get(String url) {
        return get(url, Collections.<String, String>emptyMap());
    }

    public String get(String url, Map<String, String> headers) {
        Request.Builder builder = new Request.Builder().url(url).get().header("User-Agent", UA);
        if (headers != null) for (Map.Entry<String, String> e : headers.entrySet()) builder.header(e.getKey(), e.getValue());
        return execute(builder.build());
    }

    public String req(String url, String body) {
        return post(url, body, JSON_TYPE);
    }

    public String json(String url, String body) {
        return post(url, body, JSON_TYPE);
    }

    public String text(String url, String body) {
        return post(url, body, FORM_TYPE);
    }

    public String post(String url, String body, MediaType type) {
        RequestBody rb = RequestBody.create(body == null ? "" : body, type);
        Request request = new Request.Builder().url(url).post(rb).header("User-Agent", UA).build();
        return execute(request);
    }

    public String form(String url, String body) {
        return post(url, body, FORM_TYPE);
    }

    private String execute(Request request) {
        OkHttpClient client = OkHttp.client().newBuilder()
                .connectTimeout(15, TimeUnit.SECONDS)
                .readTimeout(30, TimeUnit.SECONDS)
                .callTimeout(45, TimeUnit.SECONDS)
                .build();
        try (Response response = client.newCall(request).execute()) {
            ResponseBody body = response.body();
            return body == null ? "" : body.string();
        } catch (Throwable t) {
            throw new RuntimeException("Net " + request.method() + " " + request.url() + " failed: " + t, t);
        }
    }

    @Override
    public void close() {
        // OkHttp 的连接池由 OkHttp.client() 单例持有，这里不需要释放。
    }

    /** spider.jar 里会调 Net.sleep(ms) 做限速。 */
    public static void sleep(long ms) {
        try {
            Thread.sleep(ms);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }
}
