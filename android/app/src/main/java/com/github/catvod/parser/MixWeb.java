package com.github.catvod.parser;

import java.util.HashMap;

/**
 * STUB：按 dexdump 签名补，方法体未实现。
 *
 * 签名来源（spider.jar 的引用）：
 *   Lcom/github/catvod/parser/MixWeb;.a:Ljava/util/HashMap;    -> sget-object（静态字段）
 *   Lcom/github/catvod/parser/MixWeb;.b:Ljava/util/HashMap;    -> sget-object（静态字段）
 *   Lcom/github/catvod/parser/MixWeb;.loadHtml:(Ljava/lang/String;Ljava/lang/String;)[Ljava/lang/Object;
 *                                                              -> invoke-static
 *
 * 空方法：loadHtml(...) 恒返回空数组（原本要带 WebView 加载页面再嗅探，
 * 本工程不做 WebView 同步嗅探，这里只保证方法存在且可链接）。
 */
public final class MixWeb {

    public static HashMap<String, String> a = new HashMap<>();
    public static HashMap<String, String> b = new HashMap<>();

    private MixWeb() {
    }

    /** STUB：按 dexdump 签名补，方法体未实现。 */
    public static Object[] loadHtml(String html, String baseUrl) {
        return new Object[0];
    }
}
