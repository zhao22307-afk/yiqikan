package top.yiqikan.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Build
import androidx.core.app.NotificationCompat
import io.flutter.plugin.common.MethodChannel

/**
 * 锁屏 / 通知栏播放控制。
 * 仅在 Android 5+ 可用；动作通过 MethodChannel 回传给 Flutter。
 */
class MediaSessionHelper(private val context: Context, private val channel: MethodChannel) {
    private var session: MediaSession? = null
    private var playing = false
    private var position = 0L

    // 平台 MediaSession 没有 metadata getter，自己留一份最近一次的元数据用于通知栏文案。
    private var lastMetadata: MediaMetadata? = null

    fun start() {
        if (session != null) return
        session = MediaSession(context, "yiqikan").apply {
            setCallback(object : MediaSession.Callback() {
                override fun onPlay() = send("play", 0)
                override fun onPause() = send("pause", 0)
                override fun onSkipToNext() = send("next", 0)
                override fun onSkipToPrevious() = send("prev", 0)
                override fun onStop() = send("stop", 0)
                override fun onSeekTo(pos: Long) = send("seek", pos.toInt())
            })
            isActive = true
        }
        createChannel()
        pushNotification()
    }

    fun stop() {
        session?.isActive = false
        session?.release()
        session = null
        val mgr = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        mgr.cancel(NOTIF_ID)
    }

    fun setMetadata(title: String, artist: String, duration: Long) {
        val b = MediaMetadata.Builder()
            .putString(MediaMetadata.METADATA_KEY_TITLE, title)
            .putString(MediaMetadata.METADATA_KEY_ARTIST, artist)
            .putLong(MediaMetadata.METADATA_KEY_DURATION, duration)
        val meta = b.build()
        lastMetadata = meta
        session?.setMetadata(meta)
        pushNotification()
    }

    fun setState(p: Boolean, pos: Long) {
        playing = p
        position = pos
        val state = if (p) PlaybackState.STATE_PLAYING else PlaybackState.STATE_PAUSED
        session?.setPlaybackState(
            PlaybackState.Builder()
                .setActions(
                    PlaybackState.ACTION_PLAY or PlaybackState.ACTION_PAUSE or
                        PlaybackState.ACTION_PLAY_PAUSE or PlaybackState.ACTION_SEEK_TO or
                        PlaybackState.ACTION_SKIP_TO_NEXT or PlaybackState.ACTION_SKIP_TO_PREVIOUS
                )
                .setState(state, pos, if (p) 1f else 0f)
                .build()
        )
        pushNotification()
    }

    private fun send(action: String, value: Int) {
        channel.invokeMethod("action", mapOf("action" to action, "value" to value))
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val mgr = context.getSystemService(NotificationManager::class.java)
            if (mgr.getNotificationChannel(CHANNEL_ID) == null) {
                mgr.createNotificationChannel(
                    NotificationChannel(CHANNEL_ID, "播放控制", NotificationManager.IMPORTANCE_LOW)
                )
            }
        }
    }

    private fun pushNotification() {
        val notif = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle(lastMetadata?.getString(MediaMetadata.METADATA_KEY_TITLE) ?: "正在播放")
            .setContentText(lastMetadata?.getString(MediaMetadata.METADATA_KEY_ARTIST) ?: "")
            .setOngoing(playing)
            .build()
        val mgr = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        mgr.notify(NOTIF_ID, notif)
    }

    companion object {
        const val CHANNEL_ID = "yiqikan_media"
        const val NOTIF_ID = 4102
    }
}
