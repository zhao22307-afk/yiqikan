package top.yiqikan.app.server;

import android.app.Application;
import android.content.Context;

/**
 * 进程级启动器：App 一启动就把机内 HTTP/WS 服务拉起来。
 * 因为 libapp.so 里的全部官方 URL 已被等长改写成 http://127.0.0.1:8080，
 * 服务一就绪，App 的所有请求都落在本机，不再触达外部服务器。
 */
public class LocalApp extends Application {

    private static Context appCtx;

    @Override
    public void onCreate() {
        super.onCreate();
        appCtx = this;
        try {
            LocalServer.get(this).start();
        } catch (Throwable t) {
            android.util.Log.e(LocalServer.TAG, "LocalServer start failed", t);
        }
        try {
            // 局域网发现常驻：别人能看到你，你也能看到别人（七种建房里的 ① 局域网）
            Discovery.get().start();
        } catch (Throwable t) {
            android.util.Log.e(LocalServer.TAG, "Discovery start failed", t);
        }
        try {
            // 内置 STUN：给 App 内的 WebRTC 一个不依赖外网的 STUN 端点（P2P 打洞的第一步）
            Stun.start();
        } catch (Throwable t) {
            android.util.Log.e(LocalServer.TAG, "Stun start failed", t);
        }
    }

    public static Context ctx() {
        return appCtx;
    }
}
