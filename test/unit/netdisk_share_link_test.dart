/// 网盘分享链接解析（第二段）：四种平台 + 五种脏输入。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:yiqikan/data/netdisk/netdisk_adapter.dart';
import 'package:yiqikan/data/netdisk/share_link.dart';

void main() {
  test('夸克：裸链接', () {
    final ShareLink? s = parseShareLink('https://pan.quark.cn/s/abc123def');
    expect(s, isNotNull);
    expect(s!.kind, NetdiskKind.quark);
    expect(s.shareId, 'abc123def');
    expect(s.receiveCode, '');
  });

  test('115：带提取码', () {
    final ShareLink? s = parseShareLink(
      'https://115.com/s/sw6abcd?password=x9y8',
    );
    expect(s, isNotNull);
    expect(s!.kind, NetdiskKind.pan115);
    expect(s.shareId, 'sw6abcd');
    expect(s.receiveCode, 'x9y8');
  });

  test('123：五个域名之一', () {
    final ShareLink? s = parseShareLink('https://www.123912.com/s/AbC-123');
    expect(s, isNotNull);
    expect(s!.kind, NetdiskKind.pan123);
    expect(s.shareId, 'AbC-123');
  });

  test('天翼：/t/ 与 /web/share?code= 两种形态', () {
    final ShareLink? a = parseShareLink('https://cloud.189.cn/t/AbCd1234');
    expect(a?.kind, NetdiskKind.tianyi);
    expect(a?.shareId, 'AbCd1234');

    final ShareLink? b = parseShareLink('https://cloud.189.cn/web/share?code=XyZ987');
    expect(b?.kind, NetdiskKind.tianyi);
    expect(b?.shareId, 'XyZ987');
  });

  test('脏输入 1：整段分享文案（要从中文里抠出链接）', () {
    final ShareLink? s = parseShareLink(
      '我用夸克网盘分享了「test sample」，点击链接即可保存。链接：'
      'https://pan.quark.cn/s/9f8e7d6c 提取码：ab12',
    );
    expect(s, isNotNull);
    expect(s!.kind, NetdiskKind.quark);
    expect(s.shareId, '9f8e7d6c');
    expect(s.receiveCode, 'ab12');
  });

  test('脏输入 2：短链 / 带锚点 / 带追踪参数', () {
    final ShareLink? s = parseShareLink(
      'https://pan.quark.cn/s/abc999?entry=share#fragment',
    );
    expect(s?.kind, NetdiskKind.quark);
    expect(s?.shareId, 'abc999');
  });

  test('脏输入 3：链接结尾带中文标点', () {
    final ShareLink? s = parseShareLink('看这个 https://115.com/s/sw9zzz。');
    expect(s?.kind, NetdiskKind.pan115);
    expect(s?.shareId, 'sw9zzz');
  });

  test('脏输入 4：完全无关的文字 → null，不崩', () {
    expect(parseShareLink('今天天气不错，出去走走吧'), isNull);
    expect(parseShareLink(''), isNull);
    expect(parseShareLink('   '), isNull);
  });

  test('脏输入 5：别的站的链接 → null', () {
    expect(parseShareLink('https://www.bilibili.com/video/BV1xx411c7mD'), isNull);
    expect(parseShareLink('https://example.com/s/abc'), isNull);
  });

  test('toExtra 的键名和各家 list/resolve 要的一致', () {
    final ShareLink q = parseShareLink('https://pan.quark.cn/s/p1?pwd=z9z9')!;
    expect(q.toExtra()['pwd_id'], 'p1');
    expect(q.toExtra()['passcode'], 'z9z9');

    final ShareLink t = parseShareLink('https://cloud.189.cn/t/T1')!;
    expect(t.toExtra()['shareId'], 'T1');

    final ShareLink n = parseShareLink('https://www.123684.com/s/K1')!;
    expect(n.toExtra()['share_key'], 'K1');
  });
}
