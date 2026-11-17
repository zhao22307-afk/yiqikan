/// M6 第一段「真 HTTP」验收（不是单测，手动跑）。
///
/// 先在本机起 mock：
///   python scripts/m6_mock.py 8768
/// 再跑：
///   flutter test test/manual/m6_accept_test.dart
///
/// 它会真的发 PROPFIND / POST，不是喂 fixture —— 用来证明协议层能通。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yiqikan/core/errors/app_exception.dart';
import 'package:yiqikan/core/utils/redact.dart';
import 'package:yiqikan/data/local/secure_store.dart';
import 'package:yiqikan/data/netdisk/alist_adapter.dart';
import 'package:yiqikan/data/netdisk/emby_adapter.dart';
import 'package:yiqikan/data/netdisk/netdisk_adapter.dart';
import 'package:yiqikan/data/netdisk/webdav_adapter.dart';

const String _base = 'http://127.0.0.1:8768';

Future<bool> _up() async {
  try {
    final Socket s = await Socket.connect('127.0.0.1', 8768,
        timeout: const Duration(milliseconds: 600));
    s.destroy();
    return true;
  } catch (_) {
    return false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // flutter_test 默认把 HttpClient 换成「永远 400」的假实现，这里要真联网
    HttpOverrides.global = null;
    final bool ok = await _up();
    if (!ok) {
      // ignore: avoid_print
      print('[M6] mock 没起，先跑 python scripts/m6_mock.py 8768');
    }
    expect(ok, isTrue, reason: 'mock server 必须在 8768 上跑着');
  });

  test('WebDAV：PROPFIND 207 真解析（跳过自己 / 中文 / + 号 / 目录判定）', () async {
    final WebDavAdapter dav = WebDavAdapter(
      account: const NetdiskAccountInfo(
        kind: NetdiskKind.webdav,
        displayName: 'mock-dav',
        endpoint: '$_base/dav',
      ),
      username: 'm6',
      password: 'm6pass',
      store: SecureStore(),
    );
    expect(await dav.verify(), isTrue);
    final List<RemoteEntry> rows = await dav.list('/');
    for (final RemoteEntry e in rows) {
      // ignore: avoid_print
      print('[M6-WEBDAV] ${e.isDir ? "DIR " : "FILE"} ${e.name} size=${e.size} id=${e.id}');
    }
    final List<String> names = rows.map((RemoteEntry e) => e.name).toList();
    expect(names.contains('dav'), isFalse);
    expect(names, contains('movies'));
    expect(names, contains('中文 片名.mp4'));
    expect(names, contains('a+b.mp4'));
    expect(rows.first.name, 'movies');
    expect(rows.first.isDir, isTrue);
    final RemoteEntry file = rows.firstWhere((RemoteEntry e) => e.name == '中文 片名.mp4');
    expect(file.isDir, isFalse);
    expect(file.size, 12345678);
  });

  test('AList：fs/list 真返回 + fs/get 两条路 + 两个都空要抛 ResolveException', () async {
    final AlistAdapter alist = AlistAdapter(
      account: const NetdiskAccountInfo(
        kind: NetdiskKind.alist,
        displayName: 'mock-alist',
        endpoint: _base,
      ),
      token: 'm6token',
      store: SecureStore(),
    );
    expect(await alist.verify(), isTrue);
    final List<RemoteEntry> rows = await alist.list('/');
    for (final RemoteEntry e in rows) {
      // ignore: avoid_print
      print('[M6-ALIST] ${e.isDir ? "DIR " : "FILE"} ${e.name} size=${e.size} sign=${e.extra["sign"] ?? ""}');
    }
    expect(rows.length, 3);

    final RemoteEntry a = rows.firstWhere((RemoteEntry e) => e.name == 'a.mp4');
    final dynamic raw = await alist.resolve(a);
    // ignore: avoid_print
    print('[M6-ALIST] resolve a.mp4 resolver=${raw.resolver} url=${redactUrl(raw.url)}');
    expect('${raw.resolver}', 'alist-raw');
    expect('${raw.url}'.contains('auth_key'), isTrue);

    const RemoteEntry b = RemoteEntry(id: 'b.mp4', name: 'b.mp4', isDir: false);
    final dynamic proxy = await alist.resolve(b);
    // ignore: avoid_print
    print('[M6-ALIST] resolve b.mp4 resolver=${proxy.resolver} url=${redactUrl(proxy.url)}');
    expect('${proxy.resolver}', 'alist-proxy');

    const RemoteEntry c = RemoteEntry(id: 'c.mp4', name: 'c.mp4', isDir: false);
    await expectLater(() => alist.resolve(c), throwsA(isA<Exception>()));
  });

  test('Emby：登录 + Items，两次登录 DeviceId 必须一样', () async {
    final SecureStore store = SecureStore();
    final EmbyAdapter e1 = EmbyAdapter(
      account: const NetdiskAccountInfo(
        kind: NetdiskKind.emby,
        displayName: 'mock-emby',
        endpoint: _base,
      ),
      username: 'demo',
      password: 'm6pass',
      store: store,
    );
    expect(await e1.verify(), isTrue);
    final List<RemoteEntry> rows = await e1.list('');
    for (final RemoteEntry e in rows) {
      // ignore: avoid_print
      print('[M6-EMBY] ${e.isDir ? "DIR " : "FILE"} ${e.name} type=${e.extra["type"]} dur=${e.extra["duration"] ?? ""}');
    }
    expect(rows.length, 3);
    expect(rows.first.isDir, isTrue);

    // 第二个实例 = 模拟重新登录
    final EmbyAdapter e2 = EmbyAdapter(
      account: const NetdiskAccountInfo(
        kind: NetdiskKind.emby,
        displayName: 'mock-emby',
        endpoint: _base,
      ),
      username: 'demo',
      password: 'm6pass',
      store: store,
    );
    expect(await e2.verify(), isTrue);

    final File log = File('E:/code/_m0_tmp/m6_devices.log');
    final List<String> ids = log.existsSync()
        ? log.readAsLinesSync().where((String s) => s.trim().isNotEmpty).toList()
        : <String>[];
    // ignore: avoid_print
    print('[M6-EMBY] 服务端收到的 DeviceId 序列：${ids.map((String s) => s.substring(0, 8)).join(', ')}');
    if (ids.length >= 2) {
      expect(ids[ids.length - 1], ids[ids.length - 2], reason: 'DeviceId 不能每次登录都变');
    }
  });

  test('日志脱敏：直链只留 host+path', () async {
    const String u = '$_base/v1/file.mp4?auth_key=1&sign=2';
    final String r = redactUrl(u);
    // ignore: avoid_print
    print('[M6-REDACT] $r');
    expect(r.contains('auth_key'), isFalse);
    expect(r, endsWith('/v1/file.mp4'));
  });

  test('四种异常各抛一次、类型必须分开', () async {
    // 1) 凭据过期：token 错 → code=401 → AuthExpiredException
    final AlistAdapter bad = AlistAdapter(
      account: const NetdiskAccountInfo(
        kind: NetdiskKind.alist,
        displayName: 'bad-token',
        endpoint: _base,
      ),
      token: 'wrong-token',
      store: SecureStore(),
    );
    await expectLater(() => bad.list('/'), throwsA(isA<AuthExpiredException>()));
    // ignore: avoid_print
    print('[M6-ERR] 401 → AuthExpiredException ✔');

    // 2) 直链拿不到：raw_url 与 url 都空 → ResolveException
    final AlistAdapter ok = AlistAdapter(
      account: const NetdiskAccountInfo(
        kind: NetdiskKind.alist,
        displayName: 'ok-token',
        endpoint: _base,
      ),
      token: 'm6token',
      store: SecureStore(),
    );
    await expectLater(
      () => ok.resolve(const RemoteEntry(id: 'c.mp4', name: 'c.mp4', isDir: false)),
      throwsA(isA<ResolveException>()),
    );
    // ignore: avoid_print
    print('[M6-ERR] 空直链 → ResolveException ✔');

    // 3) 连不上：端口没人听 → NetworkException
    final WebDavAdapter dead = WebDavAdapter(
      account: const NetdiskAccountInfo(
        kind: NetdiskKind.webdav,
        displayName: 'dead',
        endpoint: 'http://127.0.0.1:1/dav',
      ),
      username: 'x',
      password: 'y',
      store: SecureStore(),
    );
    await expectLater(() => dead.list('/'), throwsA(isA<NetworkException>()));
    // ignore: avoid_print
    print('[M6-ERR] 端口不通 → NetworkException ✔');

    // 4) 返回结构不对：data 不是对象 → ParseException
    expect(
      () => AlistParser.parseList(<String, dynamic>{'code': 200, 'data': 'oops'}),
      throwsA(isA<ParseException>()),
    );
    // ignore: avoid_print
    print('[M6-ERR] 结构不对 → ParseException ✔');
  });
}
