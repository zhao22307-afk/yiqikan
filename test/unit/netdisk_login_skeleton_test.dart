/// 第二段登录骨架的「假凭据」自检：确认四家都是抛 AuthExpiredException，
/// 而不是 NullPointer / FormatException 之类崩掉。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:yiqikan/core/errors/app_exception.dart';
import 'package:yiqikan/data/netdisk/netdisk_adapter.dart';
import 'package:yiqikan/data/netdisk/pan123_adapter.dart';
import 'package:yiqikan/data/netdisk/quark_adapter.dart';
import 'package:yiqikan/data/netdisk/tianyi_adapter.dart';
import 'package:yiqikan/data/netdisk/x115_adapter.dart';
import 'package:yiqikan/data/local/secure_store.dart';

void main() {
  final SecureStore store = SecureStore();

  const NetdiskAccountInfo quarkInfo =
      NetdiskAccountInfo(kind: NetdiskKind.quark, displayName: '夸克');
  const NetdiskAccountInfo p115Info =
      NetdiskAccountInfo(kind: NetdiskKind.pan115, displayName: '115');
  const NetdiskAccountInfo p123Info =
      NetdiskAccountInfo(kind: NetdiskKind.pan123, displayName: '123');
  const NetdiskAccountInfo tianyiInfo =
      NetdiskAccountInfo(kind: NetdiskKind.tianyi, displayName: '天翼');

  test('夸克：假 Cookie 直接判未登录，不打网络', () async {
    final QuarkAdapter a =
        QuarkAdapter(account: quarkInfo, cookie: 'garbage=1', store: store);
    await expectLater(a.verify(), throwsA(isA<AuthExpiredException>()));
  });

  test('115：Cookie 缺四段时报缺哪几个（不崩）', () async {
    final X115Adapter a =
        X115Adapter(account: p115Info, cookie: 'UID=1; CID=2', store: store);
    final List<String> missing = X115Adapter.missingCookieFields('UID=1; CID=2');
    expect(missing, <String>['SEID', 'KID']);
    expect(X115Adapter.cookieErrorText(missing), contains('SEID'));
    await expectLater(a.verify(), throwsA(isA<AuthExpiredException>()));
  });

  test('115：AES 探测对坏密文返回 null 而不是抛异常', () {
    expect(X115Adapter.probeDecrypt('not-base64!!'), isNull);
    expect(X115Adapter.probeDecrypt(''), isNull);
  });

  test('123：空 token 判未登录', () async {
    final Pan123Adapter a =
        Pan123Adapter(account: p123Info, token: '', store: store);
    await expectLater(a.verify(), throwsA(isA<AuthExpiredException>()));
  });

  test('天翼：Cookie 里没有 COOKIE_LOGIN_USER 就判未登录', () async {
    final TianyiAdapter a =
        TianyiAdapter(account: tianyiInfo, cookie: 'foo=bar', store: store);
    expect(TianyiAdapter.ssKeyFrom('foo=bar'), isNull);
    await expectLater(a.verify(), throwsA(isA<AuthExpiredException>()));
  });
}
