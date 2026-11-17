package com.github.catvod.net;

import java.util.concurrent.TimeUnit;

import okhttp3.ConnectionPool;
import okhttp3.Dns;
import okhttp3.OkHttpClient;

/**
 * 最小实现（本仓库自写，不属于 FongMi 原文件）。
 *
 * FongMi 的 catvod 原版 net 层依赖 OkHttp 5.x + Java 21，本工程是 OkHttp 4.12 + Java 17，
 * 因此这里只提供 Spider / AList / Decoder / Util 实际用到的那几个符号：
 * client() / dns() / VERSION。
 */
public class OkHttp {

    public static final String VERSION = "4.12.0";

    private static volatile OkHttpClient client;

    public static OkHttpClient client() {
        if (client == null) {
            synchronized (OkHttp.class) {
                if (client == null) {
                    client = new OkHttpClient.Builder()
                            .connectTimeout(15, TimeUnit.SECONDS)
                            .readTimeout(30, TimeUnit.SECONDS)
                            .writeTimeout(30, TimeUnit.SECONDS)
                            .followRedirects(true)
                            .followSslRedirects(true)
                            .retryOnConnectionFailure(true)
                            .connectionPool(new ConnectionPool(8, 5, TimeUnit.MINUTES))
                            .build();
                }
            }
        }
        return client;
    }

    public static Dns dns() {
        return Dns.SYSTEM;
    }
}
