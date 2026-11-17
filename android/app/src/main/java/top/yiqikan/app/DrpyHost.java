package top.yiqikan.app;

import android.util.Log;

import org.json.JSONArray;
import org.json.JSONObject;
import org.jsoup.Jsoup;
import org.jsoup.nodes.Element;

import java.net.URI;
import java.util.Iterator;
import java.util.concurrent.TimeUnit;

import okhttp3.MediaType;
import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.RequestBody;
import okhttp3.Response;
import okhttp3.ResponseBody;

/**
 * drpy2 宿主实现：req / pdfh / pdfa / pd。
 *
 * 全部方法 catch(Throwable) 返回空字符串或空数组，绝不把异常抛给 JS。
 * req 是同步的（execute()），drpy2 跑在 yqk-drpy2 工作线程里，不会碰主线程网络限制。
 */
public final class DrpyHost {

    private static final String TAG = "YQK-QJS";
    private static final String[] RULE_PREFIXES = {"json:", "jsp:", "jq:"};

    /** 规则里的 host，用于把 "/search?t=**" 这种相对地址补全。 */
    public static volatile String base = "";

    private DrpyHost() {}

    private static void log(String s) {
        Log.i(TAG, "[YQK-DRPY] " + s);
    }

    // ---------------- req ----------------

    public static String req(String url, String optsJson) {
        long t0 = System.currentTimeMillis();
        String code = "-";
        String body = "";
        try {
            if (url == null || url.isEmpty()) return "";
            String u = url;
            if (u.startsWith("/")) {
                String b = base;
                if (b != null && !b.isEmpty()) u = b.endsWith("/") ? b.substring(0, b.length() - 1) + u : b + u;
            }
            url = u;
            JSONObject opts = new JSONObject();
            if (optsJson != null && !optsJson.trim().isEmpty()) {
                try {
                    opts = new JSONObject(optsJson);
                } catch (Throwable ignored) {
                }
            }
            String method = opts.optString("method", "GET").toUpperCase();
            int timeout = opts.optInt("timeout", 5000);
            if (timeout <= 0) timeout = 5000;

            OkHttpClient client = new OkHttpClient.Builder()
                    .connectTimeout(timeout, TimeUnit.MILLISECONDS)
                    .readTimeout(timeout, TimeUnit.MILLISECONDS)
                    .writeTimeout(timeout, TimeUnit.MILLISECONDS)
                    .followRedirects(true)
                    .retryOnConnectionFailure(true)
                    .build();

            Request.Builder rb = new Request.Builder().url(url);
            JSONObject headers = opts.optJSONObject("headers");
            if (headers != null) {
                Iterator<String> it = headers.keys();
                while (it.hasNext()) {
                    String k = it.next();
                    try {
                        rb.addHeader(k, headers.optString(k, ""));
                    } catch (Throwable ignored) {
                    }
                }
            }
            String reqBody = opts.optString("body", "");
            if ("POST".equals(method)) {
                RequestBody rbdy = RequestBody.create(reqBody, MediaType.parse("application/json; charset=utf-8"));
                rb.post(rbdy);
            } else if ("PUT".equals(method)) {
                rb.put(RequestBody.create(reqBody, MediaType.parse("application/json; charset=utf-8")));
            } else {
                rb.get();
            }

            try (Response resp = client.newCall(rb.build()).execute()) {
                code = String.valueOf(resp.code());
                ResponseBody rb2 = resp.body();
                body = rb2 == null ? "" : rb2.string();
            }
        } catch (Throwable t) {
            log("req err " + t.getClass().getSimpleName() + ": " + (t.getMessage() == null ? "" : t.getMessage()));
            body = "";
        }
        log("req url=" + url + " code=" + code + " len=" + body.length() + " ms=" + (System.currentTimeMillis() - t0));
        return body;
    }

    // ---------------- pdfh / pdfa ----------------

    private static boolean unsupported(String rule) {
        for (String p : RULE_PREFIXES) {
            if (rule.startsWith(p)) {
                log("rule unsupported " + rule.substring(0, Math.min(8, rule.length())) + "…");
                return true;
            }
        }
        return false;
    }

    public static String pdfh(String html, String rule) {
        try {
            if (html == null || rule == null) return "";
            String r = rule.trim();
            if (r.isEmpty() || unsupported(r)) return "";

            String suffix = "Text";
            int sp = r.lastIndexOf(' ');
            if (sp > 0) {
                String tail = r.substring(sp + 1).trim();
                if (tail.equalsIgnoreCase("Text") || tail.equalsIgnoreCase("Html") || tail.equalsIgnoreCase("OuterHtml")) {
                    suffix = tail;
                    r = r.substring(0, sp).trim();
                }
            }
            String attr = null;
            int at = r.lastIndexOf('@');
            if (at > 0) {
                attr = r.substring(at + 1).trim();
                r = r.substring(0, at).trim();
            }
            if (r.isEmpty()) return "";
            Element el = Jsoup.parse(html).select(r).first();
            if (el == null) return "";
            if (attr != null && !attr.isEmpty()) return el.attr(attr);
            if (suffix.equalsIgnoreCase("Html")) return el.html();
            if (suffix.equalsIgnoreCase("OuterHtml")) return el.outerHtml();
            return el.text();
        } catch (Throwable t) {
            log("pdfh err " + t.getClass().getSimpleName() + ": " + (t.getMessage() == null ? "" : t.getMessage()));
            return "";
        }
    }

    public static String pdfa(String html, String rule) {
        try {
            if (html == null || rule == null) return "[]";
            String r = rule.trim();
            if (r.isEmpty() || unsupported(r)) return "[]";
            // 去掉可能的空格后缀
            int sp = r.lastIndexOf(' ');
            if (sp > 0) {
                String tail = r.substring(sp + 1).trim();
                if (tail.equalsIgnoreCase("Text") || tail.equalsIgnoreCase("Html") || tail.equalsIgnoreCase("OuterHtml")) {
                    r = r.substring(0, sp).trim();
                }
            }
            JSONArray arr = new JSONArray();
            for (Element e : Jsoup.parse(html).select(r)) {
                arr.put(e.outerHtml());
            }
            return arr.toString();
        } catch (Throwable t) {
            log("pdfa err " + t.getClass().getSimpleName() + ": " + (t.getMessage() == null ? "" : t.getMessage()));
            return "[]";
        }
    }

    // ---------------- pd（JSONPath 子集：$.a.b[0].c） ----------------

    public static String pd(String html, String rule, String base) {
        try {
            if (html == null || rule == null) return "";
            String path = rule.trim();
            if (!path.startsWith("$")) return "";
            path = path.substring(1);
            if (path.startsWith(".")) path = path.substring(1);

            Object cur = new JSONObject(html);
            String[] segs = path.split("\\.");
            for (String seg : segs) {
                if (seg.isEmpty()) continue;
                String name = seg;
                int idx = -1;
                int lb = seg.indexOf('[');
                if (lb >= 0) {
                    name = seg.substring(0, lb);
                    String num = seg.substring(lb + 1, seg.indexOf(']'));
                    try {
                        idx = Integer.parseInt(num.trim());
                    } catch (Throwable ignored) {
                        idx = -1;
                    }
                }
                if (!name.isEmpty()) {
                    if (!(cur instanceof JSONObject)) return "";
                    cur = ((JSONObject) cur).opt(name);
                }
                if (idx >= 0) {
                    if (!(cur instanceof JSONArray)) return "";
                    cur = ((JSONArray) cur).opt(idx);
                }
                if (cur == null || cur == JSONObject.NULL) return "";
            }
            String out = String.valueOf(cur);
            if (base != null && !base.isEmpty() && !out.startsWith("http")) {
                try {
                    out = new URI(base).resolve(out).toString();
                } catch (Throwable ignored) {
                }
            }
            return out;
        } catch (Throwable t) {
            log("pd err " + t.getClass().getSimpleName() + ": " + (t.getMessage() == null ? "" : t.getMessage()));
            return "";
        }
    }
}
