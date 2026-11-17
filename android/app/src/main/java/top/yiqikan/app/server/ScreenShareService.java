package top.yiqikan.app.server;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.os.Build;
import android.os.IBinder;
import android.util.Log;

/**
 * D20 屏幕共享的前台服务（第44轮实验用，先不推流）。
 *
 * 为什么要有它：Android 在 MediaProjectionManager.getMediaProjection() 里就检查
 * 进程是否已有 foregroundServiceType=mediaProjection 的前台服务，没有就抛
 * SecurityException（第43轮真机栈：OrientationAwareScreenCapturer.startCapture:131）。
 *
 * 本轮要回答的问题：**没有 MediaProjection 授权时**调用 startForeground(...,
 * FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION) 到底抛不抛。所以这里把异常吃掉并打日志，
 * 绝不 throw、也不返回 START_STICKY —— 结论只看那两条日志。
 */
public class ScreenShareService extends Service {

    public static final String TAG = "YQK-SCREEN";
    public static final int NOTIF_ID = 0x5C01;
    public static final String CH_ID = "yqk_screen";

    /**
     * 第46轮：startForeground(...MEDIA_PROJECTION) 到底成没成，要让 Dart 侧知道。
     *
     * Android 14+ 首次（从未授权过 MediaProjection）会抛 SecurityException，
     * 走过一次授权流程后就永久 ok —— 所以 Dart 需要这个标记来决定要不要先 warmup。
     * volatile 是因为它跨线程写（service 线程）读（channel 线程）用。
     */
    public static volatile boolean FG_OK = false;

    public static boolean isFgOk() {
        return FG_OK;
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    @Override
    public void onCreate() {
        super.onCreate();
        try {
            if (Build.VERSION.SDK_INT >= 26) {
                NotificationManager nm = (NotificationManager) getSystemService(NOTIFICATION_SERVICE);
                if (nm.getNotificationChannel(CH_ID) == null) {
                    NotificationChannel ch = new NotificationChannel(
                            CH_ID, "屏幕共享", NotificationManager.IMPORTANCE_LOW);
                    nm.createNotificationChannel(ch);
                }
            }
        } catch (Throwable t) {
            Log.w(TAG, "[YQK-SCREEN] channel fail " + t);
        }
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        Notification n = new Notification.Builder(this, CH_ID)
                .setContentTitle("一起看")
                .setContentText("正在共享屏幕")
                .setSmallIcon(android.R.drawable.ic_menu_view)
                .setOngoing(true)
                .build();
        try {
            if (Build.VERSION.SDK_INT >= 29) {
                startForeground(NOTIF_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION);
            } else {
                startForeground(NOTIF_ID, n);
            }
            Log.i(TAG, "[YQK-SCREEN] fg start ok sdk=" + Build.VERSION.SDK_INT);
            FG_OK = true;
        } catch (Throwable t) {
            FG_OK = false;
            Log.e(TAG, "[YQK-SCREEN] fg start fail " + t);
        }
        return START_NOT_STICKY;
    }

    @Override
    public void onDestroy() {
        FG_OK = false;
        try {
            stopForeground(true);
        } catch (Throwable t) {
            // 停的时候出错不影响结论，忽略
        }
        Log.i(TAG, "[YQK-SCREEN] fg stop");
        super.onDestroy();
    }
}
