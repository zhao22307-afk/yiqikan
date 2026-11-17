# 一起看

**多人同步看片。** 房主建房，把房间码发出去，所有人看到的是同一帧画面——暂停、快进、调倍速都是同步的，还能边看边发弹幕、聊天、开语音、共享屏幕。

安卓端，Flutter UI + 内嵌 Java 本地服务（`127.0.0.1:8080`）。没有中心服务器：房主的手机就是服务器，其他人直连或经隧道连过来。房间码六位数字，扫码/深链/手输三种进房方式。

---

## 功能

### 一起看
- **共控同步**：播放/暂停/快进/倍速/切集，房主操作全房跟随；三档跟随策略（<300ms 不动 / 300–700ms 调速率 / >700ms 硬 seek）
- **房间协议**：24 种帧（`hello` / `state` / `control` / `chat` / `danmaku` / `members` …），客户端单调 `seq` + 丢旧帧 + gap 补扫
- **发弹幕**：8 秒穿屏，按 `pos` 落位（不是按收到时间），房主关掉后新房间默认关
- **弹幕过滤**：过短/过长/刷屏/剧透四类规则，自己的弹幕永远放行
- **房间回放**：服务端保留最近 2000 帧，退出后能重看这场房间里发生过什么
- **成员管理**：禁言 / 移出 / 移交房主；房主申请制（`claim` + 8 秒超时）
- **房间机器人**：19 字段配置 + aliases + 每小时配额，Bot 不占人数
- **语音**：WebRTC Mesh（4 人为宜，5–6 人上限），进语音自动压低视频音量、切通话路由
- **屏幕共享**：MediaProjection 抓屏 → WebRTC 推流，客人端全屏渲染，弹幕压在上面

### 找片看片
- **多源聚合**：MacCMS 采集站 / TVBox 108 个 Spider 源 / drpy2 JS 规则 / B 站 / 网页嗅探 / 网盘（WebDAV·Emby·AList）
- **TVBox 兼容层**：DexClassLoader 加载第三方 `spider.jar`，反射调用 `searchContent` / `detailContent` / `playerContent`
- **drpy2 引擎**：QuickJS 跑 TVBox 的 JS 规则（24 份内置规则）
- **导入配置**：贴 URL / 粘 JSON / 单个源，三条路都进同一张表
- **片源嗅探**：WebView 注入钩子抓 `m3u8` / `mp4`，六层嗅探链
- **播放器**：mpv（libmpv）+ fvp（MDK）双内核，可切换；字幕内嵌抽取（MKV/PGS/ASS）、音轨切换、章节与片头片尾跳过
- **投屏**：DLNA 发送端（M-SEARCH + SOAP AVTransport）+ 接收端（本机当 renderer）
- **下载**：队列 ×2 并发、`Range` 断点续传、暂停/继续/删除

### 内容管理与个性化
- 收藏 / 追番 / 稍后看 / 播放历史 / 观看统计（全部 SQL 聚合）
- 弹幕库（FNV-1a 去重收藏）、字幕库（扫描 + 手动导入）
- 标签、片源评分、备份恢复（导出 JSON，不含任何凭据）
- 深色/浅色主题、字号缩放、中英双语（40 key l10n）
- 诊断页、崩溃日志、权限引导、电池优化白名单

---

## 技术栈

| 层 | 用什么 |
|---|---|
| UI | Flutter 3 / Dart 3，`go_router`，`ValueNotifier` + `ValueListenableBuilder` |
| 本地库 | Drift（SQLite，7 表 → 10 表，`schemaVersion = 7`） |
| 播放 | `media_kit`（libmpv）+ `fvp`（MDK），双内核可切换 |
| 网络 | `dio`、`web_socket_channel`、`flutter_inappwebview` |
| 实时音视频 | `flutter_webrtc`（Mesh，非 SFU） |
| 本地服务 | 纯 Java（无框架），`com.sun.net.httpserver` + 手写 WebSocket |
| JS 运行时 | QuickJS（`com.fongmi.quickjs`，native + WASM 双实现） |
| 隧道 | `cloudflared`（PIE 二进制放 jniLibs，`--edge` 绕开 Go resolver） |
| 其他 | `dartssh2`（SSH 反向隧道）、`flutter_secure_storage`、`permission_handler` |

---

## 项目结构

```
lib/
├── core/          常量、prefs、错误类型、工具        19 文件
├── domain/        实体 + 纯逻辑（跟随规则、解析器）   10 文件
├── data/          源解析、DB、播放器控制器          39 文件
├── platform/      房间客户端、语音、屏幕共享、TVBox  23 文件
├── features/      页面（播放/房间/片源/我的…）       45 文件
├── l10n/          中英 ARB + 生成代码
├── routing/       go_router 路由表
└── theme/         配色与排版

android/app/src/main/java/top/yiqikan/app/
├── server/        本地服务：Api / LocalServer / Store / Rooms / Tunnel / Relay / DLNA / TvboxBatch
├── DrpyHost.java  drpy2 宿主（req / pdfh / pdfa / pd）
└── MainActivity.kt  MethodChannel 桥

android/app/src/main/assets/tvbox/
├── lib/drpy2.min.js + drpy-core-lite.min.js   JS 引擎（改过 import/export，见下）
├── rules/*.js                                  24 份内置规则
└── dianshi.json                                163 个源配置
```

---

## 构建

### 环境
- Flutter 3.24+ / Dart 3.5+
- Android SDK：`compileSdk 37` / `minSdk 24` / `targetSdk 36`
- JDK 17
- 只打 `arm64-v8a`

### 步骤

```bash
git clone <repo>
cd yiqikan

# 1. 本地 SDK 路径（这个文件不进仓库）
cat > android/local.properties <<EOF
sdk.dir=/path/to/Android/Sdk
flutter.sdk=/path/to/flutter
EOF

# 2. 依赖
flutter pub get

# 3. 数据库代码生成（只跑 db 这一组，全量会崩）
dart run build_runner build --delete-conflicting-outputs \
  --build-filter="lib/data/db/**"

# 4. 构建
flutter build apk --debug      # 开发用，走 debug 签名
flutter build apk --release    # 发版，见下
```

### release 签名

`android/local.properties` 里加四个键（**不要提交这个文件**）：

```properties
RELEASE_STORE_FILE=../keystore/yiqikan.jks
RELEASE_STORE_PASSWORD=<你的密码>
RELEASE_KEY_ALIAS=yiqikan
RELEASE_KEY_PASSWORD=<你的密码>
```

没有这四个键时，`release` 会回落到 debug 签名——**能装能跑，但扫码不会直接唤起 App**（`assetlinks.json` 里的 SHA-256 对不上）。

自建证书：

```bash
keytool -genkey -v -keystore android/keystore/yiqikan.jks -keyalg RSA \
  -keysize 2048 -validity 10000 -alias yiqikan

# 拿证书指纹 —— assetlinks.json 里的 sha256_cert_fingerprints 填这个
keytool -list -v -keystore android/keystore/yiqikan.jks -alias yiqikan
# 输出里找 "SHA256:" 那一行，去掉冒号、转小写即是
```

`assetlinks.json` 必须放在**固定域名**的 `/.well-known/assetlinks.json` 下，系统才会让扫码链接直接唤起 App。用 quick tunnel（每次 URL 都变）时这一步无法生效，需要 named tunnel 或自有域名。

### cloudflared

`android/app/src/main/jniLibs/arm64-v8a/libcloudflared.so` 需要自己准备：

- 必须是 **PIE / ET_DYN**（`e_type @0x10 == 03 00`）。官方 `cloudflared-linux-arm64` 是 ET_EXEC，Android 10+ 会报 `unexpected e_type: 2`
- 参考编译命令：

```bash
CGO_ENABLED=1 GOOS=android GOARCH=arm64 CC=aarch64-linux-android23-clang \
  go build -trimpath -buildmode=pie \
  -ldflags="-s -w -linkmode=external -extldflags=-Wl,-z,max-page-size=16384" \
  -o libcloudflared.so ./cmd/cloudflared
```

放进去后，`build.gradle.kts` 的 `jniLibs.useLegacyPackaging = true` 会把它真正解压到 `nativeLibraryDir`——Android 10+ 起 `filesDir` 是 noexec，只有 `nativeLibraryDir` 能 exec。

Android 上没有 `/etc/resolv.conf`，Go 的 DNS 解析器会失败，所以启动时必须传 `--edge <ip>:7844`（IP 由 Java 侧 `InetAddress.getAllByName("region1.v2.argotunnel.com")` 解析出 IPv4 再传进去）。

### drpy2 引擎

`assets/tvbox/lib/drpy2.min.js` 与 `drpy-core-lite.min.js` 是**改动过的版本**：QuickJS 的 `evaluateModule` 在这版 wrapper 里拿不到模块导出对象（`wrap(null, result)`），只能走 `evaluate` script 模式，因此把 ES module 的 `import`/`export` 换成了 `globalThis` 挂载。

如果你要升级 drpy2，需要重做这两处替换：
- `drpy-core-lite` 末行 `export{...}` → `globalThis.__core={...}`
- `drpy2.min.js` 头 `import { cheerio, 模板 } from "./drpy-core-lite.min.js"` → `const { cheerio, 模板 } = globalThis.__core`，尾 `export default X` → `globalThis.__drpyExport = X`

---

## 第三方与许可

本项目 **GPL-3.0**。原因：`android/app/src/main/java/com/github/catvod/` 下的 Spider 兼容层来自 [FongMi/TV](https://github.com/FongMi/TV)（GPL-3.0），并且以源码形式编入。

| 组件 | 许可 |
|---|---|
| [FongMi/TV](https://github.com/FongMi/TV) 的 `catvod` | GPL-3.0 |
| [QuickJS](https://bellard.org/quickjs/) | MIT |
| [flutter_webrtc](https://github.com/flutter-webrtc/flutter-webrtc) | MIT |
| [media_kit](https://github.com/media-kit/media-kit) / libmpv | LGPL-2.1+ / GPL-2.0+ |
| [drpy2](https://github.com/hjdhnx/drpy-node) 规则引擎 | 见 `assets/tvbox/lib/` 文件头 |
| [cloudflared](https://github.com/cloudflare/cloudflared) | Apache-2.0 |

`assets/tvbox/rules/` 下的 24 份规则来自公开的 TVBox 配置集合（`qist/tvbox`），版权归各规则作者。**这些只是站点适配脚本，不含任何影视内容。**

---

## 免责声明

- 本项目**不提供、不存储、不分发任何影视内容**。所有片源由使用者自行添加，播放的是第三方站点的公开链接。
- 房间功能是**点对点直连**，没有中心服务器，不上传任何观看记录。
- 请遵守你所在地区的法律法规与各站点的服务条款。使用本项目产生的任何后果由使用者承担。

---

## 状态

功能基本完整，仍在打磨。已知限制：

- 语音 4 人为宜，Mesh 拓扑，人多了上行扛不住
- 屏幕共享无系统音频（Android 上 `AudioPlaybackCapture` 需要目标 App 配合，`getDisplayMedia({audio:true})` 在本工程用的 wrapper 里返回空轨）
- 隧道模式下 WebRTC 媒体不通（cloudflared 是 TCP 隧道），跨网络要媒体只能走 TURN 或 IPv6 直连
- 加壳的 Spider（`.guard` 解密）不支持
