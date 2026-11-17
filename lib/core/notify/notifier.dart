import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// G9 通知：下载完成 / 房间邀请 / 后台播放控制。
///
/// 选型：pubspec 里**已经有** `flutter_local_notifications: ^22.3.3`，
/// 所以不自己写 MethodChannel 的 NotificationManager（少一份原生代码，
/// 三个 channel 的创建 / 权限 / action 回调都由插件处理）。
///
/// 三条链路都是「尽力而为」：初始化失败、权限被拒都只打日志，不打断业务。
class AppNotifier {
  AppNotifier._();

  static final AppNotifier instance = AppNotifier._();

  static const String channelDownload = 'download';
  static const String channelRoom = 'room';
  static const String channelPlayback = 'playback';

  static const int idDownload = 1001;
  static const int idRoom = 1002;
  static const int idPlayback = 1003;

  /// 通知被点 / 按钮被点：`(actionId, payload)`
  /// - 房间：actionId `open`，payload `room:<code>`
  /// - 播放：actionId `prev` / `toggle` / `next`，payload 为空
  static void Function(String action, String? payload)? handler;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _ready = false;
  bool _permAsked = false;

  bool get ready => _ready;

  Future<void> init() async {
    if (_ready) return;
    const AndroidInitializationSettings android =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings settings =
        InitializationSettings(android: android);
    try {
      final bool? ok = await _plugin.initialize(
        settings: settings,
        onDidReceiveNotificationResponse: (NotificationResponse r) {
          debugPrint('[YQK-NOTIFY] tap action=${r.actionId} payload=${r.payload}');
          handler?.call(r.actionId ?? 'open', r.payload);
        },
      );
      final AndroidFlutterLocalNotificationsPlugin? androidImpl =
          _plugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      // 三个 channel 在这里一次性建好：不建的话 Android 8+ 通知直接不显示。
      await androidImpl?.createNotificationChannel(const AndroidNotificationChannel(
        channelDownload,
        '下载完成',
        description: '片子下载完成时提醒',
        importance: Importance.low,
      ));
      await androidImpl?.createNotificationChannel(const AndroidNotificationChannel(
        channelRoom,
        '房间邀请',
        description: '有人进了你的房间',
        importance: Importance.high,
      ));
      await androidImpl?.createNotificationChannel(const AndroidNotificationChannel(
        channelPlayback,
        '后台播放',
        description: '在通知栏控制播放 / 暂停 / 上下集',
        importance: Importance.low,
      ));
      _ready = true;
      debugPrint('[YQK-NOTIFY] init ok=$ok channels=3');
    } catch (e) {
      debugPrint('[YQK-NOTIFY] init fail $e');
    }
  }

  /// Android 13+ 首次触发前要 POST_NOTIFICATIONS。拒绝之后不再骚扰。
  /// 纯逻辑，便于单测：只有「系统没开」且「本进程没问过」时才去请求。
  /// 问过一次之后，即使仍没开也不再弹（避免每次下载都打扰用户）。
  @visibleForTesting
  static bool shouldRequest({required bool enabled, required bool asked}) =>
      !enabled && !asked;

  Future<bool> _ensurePermission() async {
    final AndroidFlutterLocalNotificationsPlugin? impl = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (impl == null) return true;
    try {
      final bool? enabled = await impl.areNotificationsEnabled();
      if (enabled == true) return true;
      if (!shouldRequest(enabled: enabled ?? false, asked: _permAsked)) {
        debugPrint('[YQK-NOTIFY] permission denied earlier, skip');
        return false;
      }
      _permAsked = true;
      final bool? granted = await impl.requestNotificationsPermission();
      debugPrint('[YQK-NOTIFY] permission granted=$granted');
      return granted ?? false;
    } catch (e) {
      debugPrint('[YQK-NOTIFY] permission error $e');
      return false;
    }
  }

  Future<void> showDownloadDone(String name, String path) async {
    if (!_ready || !await _ensurePermission()) return;
    await _show(
      id: idDownload,
      title: '下载完成',
      body: name,
      payload: path,
      details: const NotificationDetails(
        android: AndroidNotificationDetails(
          channelDownload,
          '下载完成',
          channelDescription: '片子下载完成时提醒',
          importance: Importance.low,
          priority: Priority.low,
          onlyAlertOnce: true,
        ),
      ),
    );
    debugPrint('[YQK-NOTIFY] download done name=$name');
  }

  Future<void> showRoomInvite(String code, String hostName) async {
    if (!_ready || !await _ensurePermission()) return;
    await _show(
      id: idRoom,
      title: '有人进了你的房间',
      body: '$hostName 正在房间 $code 里等你',
      payload: 'room:$code',
      details: const NotificationDetails(
        android: AndroidNotificationDetails(
          channelRoom,
          '房间邀请',
          channelDescription: '有人进了你的房间',
          importance: Importance.high,
          priority: Priority.high,
          actions: <AndroidNotificationAction>[
            AndroidNotificationAction(
              'open',
              '进入房间',
              showsUserInterface: true,
              // 点按钮直接拉起 App（不用等用户再点通知本体）
              cancelNotification: true,
            ),
          ],
        ),
      ),
    );
    debugPrint('[YQK-NOTIFY] room invite code=$code host=$hostName');
  }

  Future<void> showPlayback(String title, bool isPlaying) async {
    if (!_ready || !await _ensurePermission()) return;
    await _show(
      id: idPlayback,
      title: title,
      body: isPlaying ? '正在播放' : '已暂停',
      details: NotificationDetails(
        android: AndroidNotificationDetails(
          channelPlayback,
          '后台播放',
          channelDescription: '在通知栏控制播放 / 暂停 / 上下集',
          importance: Importance.low,
          priority: Priority.low,
          onlyAlertOnce: true,
          ongoing: true,
          autoCancel: false,
          showWhen: false,
          actions: <AndroidNotificationAction>[
            // showsUserInterface: true → 点按钮把 App 拉回前台，回调走主 isolate
            // （后台 isolate 拿不到播放页状态，按钮就成了哑巴）
            const AndroidNotificationAction('prev', '上一集',
                showsUserInterface: true),
            AndroidNotificationAction('toggle', isPlaying ? '暂停' : '播放',
                showsUserInterface: true),
            const AndroidNotificationAction('next', '下一集',
                showsUserInterface: true),
          ],
        ),
      ),
    );
  }

  Future<void> _show({
    required int id,
    required String title,
    required String body,
    NotificationDetails? details,
    String? payload,
  }) async {
    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: details,
        payload: payload,
      );
    } catch (e) {
      debugPrint('[YQK-NOTIFY] show fail id=$id $e');
    }
  }

  Future<void> cancel(int id) async {
    try {
      await _plugin.cancel(id: id);
    } catch (e) {
      debugPrint('[YQK-NOTIFY] cancel fail id=$id $e');
    }
  }

  Future<void> cancelAll() async {
    try {
      await _plugin.cancelAll();
    } catch (e) {
      debugPrint('[YQK-NOTIFY] cancelAll fail $e');
    }
  }
}

/// 通知栏按钮 → 播放页的桥。
///
/// 播放页活着时把自己的处理器塞进来（`onAction`），通知栏的
/// prev / toggle / next 就落到它身上；页面销毁时置空，点按钮只打日志。
class PlayerRemote {
  PlayerRemote._();
  static void Function(String action)? onAction;
}
