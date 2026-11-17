package com.github.catvod.parser;

import java.util.HashMap;

/**
 * STUB：按 dexdump 签名补，方法体未实现。
 *
 * 签名来源（spider.jar 的 method 引用）：
 *   Lcom/github/catvod/parser/JsonBasic;.getReqHeader:(Ljava/lang/String;)Ljava/util/HashMap;
 *   -> invoke-static，即 public static HashMap<String,String> getReqHeader(String)
 *
 * 本仓库没有 TVBoxOS 的 JsonBasic 原文件；这里只保证方法存在且可链接。
 * 当前实现直接复用 JsonParallel 的 getReqHeader（同一套 cat_ext 头解析），
 * 不是空实现 —— 报告里按“非空”记录。
 */
public final class JsonBasic {

    private JsonBasic() {
    }

    public static HashMap<String, String> getReqHeader(String url) {
        return JsonParallel.getReqHeader(url);
    }
}
