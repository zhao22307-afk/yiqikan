package com.github.catvod.parser;

import java.util.HashMap;

/**
 * STUB：按 dexdump 签名补，方法体未实现。
 *
 * 签名来源（spider.jar 的引用）：
 *   Lcom/github/catvod/parser/MixDemo;.a:Ljava/util/HashMap;    -> sget-object（静态字段）
 *   Lcom/github/catvod/parser/MixDemo;.b:Ljava/util/HashMap;    -> sget-object（静态字段）
 *   Lcom/github/catvod/parser/MixDemo;.c:(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;
 *                                                               -> invoke-static
 *
 * 空方法：c(...) 恒返回 ""。
 */
public final class MixDemo {

    public static HashMap<String, String> a = new HashMap<>();
    public static HashMap<String, String> b = new HashMap<>();

    private MixDemo() {
    }

    /** STUB：按 dexdump 签名补，方法体未实现。 */
    public static String c(String arg1, String arg2) {
        return "";
    }
}
