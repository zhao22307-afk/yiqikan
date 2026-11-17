# Flutter / Dart
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# media_kit / libmpv JNI
-keep class com.alexmercerind.** { *; }
-keep class dev.media_kit.** { *; }

# WebRTC / LiveKit（大量反射与 JNI）
-keep class org.webrtc.** { *; }
-dontwarn org.webrtc.**
-keep class io.livekit.** { *; }
-dontwarn io.livekit.**

# 本站原生桥
-keep class top.syncwe.offline.** { *; }

# 通知 / 媒体会话
-keep class androidx.media.** { *; }
-keep class androidx.core.app.NotificationCompat** { *; }

# 保留行号便于看崩溃栈
-keepattributes SourceFile,LineNumberTable
