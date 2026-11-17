import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of L
/// returned by `L.of(context)`.
///
/// Applications need to include `L.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'gen/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: L.localizationsDelegates,
///   supportedLocales: L.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the L.supportedLocales
/// property.
abstract class L {
  L(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static L of(BuildContext context) {
    return Localizations.of<L>(context, L)!;
  }

  static const LocalizationsDelegate<L> delegate = _LDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// 应用名，显示在桌面标题与关于页
  ///
  /// In zh, this message translates to:
  /// **'一起看'**
  String get appName;

  /// 首页右上角图标按钮：作为房主建房
  ///
  /// In zh, this message translates to:
  /// **'一起看（建房）'**
  String get homeCreateRoom;

  /// 首页图标按钮：输入房间码进房
  ///
  /// In zh, this message translates to:
  /// **'加入房间'**
  String get homeJoinRoom;

  /// 首页图标按钮：扫二维码进房
  ///
  /// In zh, this message translates to:
  /// **'扫码加房'**
  String get homeScan;

  /// 首页图标按钮 + 片源页标题
  ///
  /// In zh, this message translates to:
  /// **'片源'**
  String get homeSources;

  /// 首页图标按钮：进入设置页
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get homeSettings;

  /// 房间页按钮：打开成员列表
  ///
  /// In zh, this message translates to:
  /// **'成员'**
  String get roomMembers;

  /// 成员角色标识：房主
  ///
  /// In zh, this message translates to:
  /// **'房主'**
  String get roomHost;

  /// 成员角色标识：客人
  ///
  /// In zh, this message translates to:
  /// **'客人'**
  String get roomGuest;

  /// 房间内退出按钮
  ///
  /// In zh, this message translates to:
  /// **'离开房间'**
  String get roomLeave;

  /// 房主菜单项：生成分享链接/二维码
  ///
  /// In zh, this message translates to:
  /// **'分享房间'**
  String get roomShare;

  /// 房主菜单项：配置房间机器人
  ///
  /// In zh, this message translates to:
  /// **'房间 Bot'**
  String get roomBot;

  /// 房主菜单项：弹幕开关、字号、速度
  ///
  /// In zh, this message translates to:
  /// **'弹幕设置'**
  String get roomDanmaku;

  /// 房主菜单项：把自己的屏幕共享给房间
  ///
  /// In zh, this message translates to:
  /// **'共享屏幕'**
  String get roomScreenShare;

  /// 播放器按钮无障碍标签
  ///
  /// In zh, this message translates to:
  /// **'播放'**
  String get playerPlay;

  /// 播放器按钮无障碍标签
  ///
  /// In zh, this message translates to:
  /// **'暂停'**
  String get playerPause;

  /// 播放器进度条无障碍标签
  ///
  /// In zh, this message translates to:
  /// **'拖动进度'**
  String get playerSeek;

  /// 播放器底部按钮：码率/画质选择
  ///
  /// In zh, this message translates to:
  /// **'画质'**
  String get playerQuality;

  /// 播放器底部按钮：字幕轨与外挂字幕
  ///
  /// In zh, this message translates to:
  /// **'字幕'**
  String get playerSubtitle;

  /// 播放器底部按钮：进入全屏
  ///
  /// In zh, this message translates to:
  /// **'全屏'**
  String get playerFullscreen;

  /// 播放器底部按钮：弹幕开关
  ///
  /// In zh, this message translates to:
  /// **'弹幕'**
  String get playerDanmaku;

  /// 播放器/房间底部按钮：加入语音
  ///
  /// In zh, this message translates to:
  /// **'语音'**
  String get playerVoice;

  /// 底部导航第一个 tab
  ///
  /// In zh, this message translates to:
  /// **'首页'**
  String get tabHome;

  /// 片源相关页面的短标题
  ///
  /// In zh, this message translates to:
  /// **'片源'**
  String get tabSources;

  /// 底部导航第二个 tab：收藏/历史/下载
  ///
  /// In zh, this message translates to:
  /// **'我的'**
  String get tabLibrary;

  /// 设置页标题
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get tabSettings;

  /// 「我的」第一个 tab：收藏列表
  ///
  /// In zh, this message translates to:
  /// **'收藏'**
  String get libFavorites;

  /// 「我的」tab：观看历史时间线
  ///
  /// In zh, this message translates to:
  /// **'历史'**
  String get libHistory;

  /// 「我的」tab：下载队列
  ///
  /// In zh, this message translates to:
  /// **'下载'**
  String get libDownload;

  /// 收藏卡片菜单项：加入追番
  ///
  /// In zh, this message translates to:
  /// **'追番'**
  String get libFollow;

  /// 设置页：主题（跟随系统/浅色/深色）
  ///
  /// In zh, this message translates to:
  /// **'外观'**
  String get setTheme;

  /// 设置页：字体缩放三档
  ///
  /// In zh, this message translates to:
  /// **'字号'**
  String get setFont;

  /// 设置页：界面语言（跟随系统/中文/English）
  ///
  /// In zh, this message translates to:
  /// **'语言'**
  String get setLanguage;

  /// 设置页：电池优化白名单与后台行为说明
  ///
  /// In zh, this message translates to:
  /// **'省电与后台'**
  String get setPower;

  /// 设置页：版本/端口/通道/房间/最近错误
  ///
  /// In zh, this message translates to:
  /// **'诊断'**
  String get setDiagnose;

  /// 设置页：自建更新源检查新版本
  ///
  /// In zh, this message translates to:
  /// **'检查更新'**
  String get setUpdate;

  /// 设置页：导出/导入 JSON 备份
  ///
  /// In zh, this message translates to:
  /// **'备份与恢复'**
  String get setBackup;

  /// 设置页：通知/相册/相机/麦克风/安装未知应用
  ///
  /// In zh, this message translates to:
  /// **'权限'**
  String get setPermission;

  /// 设置页：版本号与开源声明
  ///
  /// In zh, this message translates to:
  /// **'关于'**
  String get setAbout;

  /// 设置页：选路策略（自动/仅隧道/仅内网/仅 IPv6）
  ///
  /// In zh, this message translates to:
  /// **'优先通道'**
  String get setChannel;
}

class _LDelegate extends LocalizationsDelegate<L> {
  const _LDelegate();

  @override
  Future<L> load(Locale locale) {
    return SynchronousFuture<L>(lookupL(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_LDelegate old) => false;
}

L lookupL(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return LEn();
    case 'zh':
      return LZh();
  }

  throw FlutterError(
    'L.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
