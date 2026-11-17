/// MKV 内嵌字幕抽取：三段手搓 EBML 字节流（正常 ASS / 正常 SRT / 只有视频轨）。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yiqikan/data/media/mkv_subtitle.dart';

/// 最小 EBML 构造器（只够造这几个用例）
class _Ebml {
  /// 变长 size 编码（最短长度）：1 字节 marker=0x80，2 字节=0x40，3 字节=0x20…
  static Uint8List size(int v) {
    for (int len = 1; len <= 8; len++) {
      final int max = (1 << (7 * len)) - 1;
      if (v < max) {
        final int marker = 1 << (8 - len);
        final Uint8List out = Uint8List(len);
        out[0] = marker | (v >> (8 * (len - 1)));
        for (int i = 1; i < len; i++) {
          out[i] = (v >> (8 * (len - 1 - i))) & 0xff;
        }
        return out;
      }
    }
    throw ArgumentError('size 太大');
  }

  static Uint8List id(int v) {
    final List<int> bytes = <int>[];
    int x = v;
    while (x > 0) {
      bytes.insert(0, x & 0xff);
      x >>= 8;
    }
    return Uint8List.fromList(bytes);
  }

  static Uint8List el(int idValue, List<int> payload) {
    final Uint8List i = id(idValue);
    final Uint8List s = size(payload.length);
    return Uint8List.fromList(<int>[...i, ...s, ...payload]);
  }

  static Uint8List uintEl(int idValue, int value) {
    final List<int> b = <int>[];
    int x = value;
    do {
      b.insert(0, x & 0xff);
      x >>= 8;
    } while (x > 0);
    return el(idValue, b);
  }

  static Uint8List strEl(int idValue, String s) =>
      el(idValue, utf8.encode(s));

  /// SimpleBlock：trackNumber VINT + int16 相对时间 + flags + payload
  static Uint8List block(int track, int relMs, int flags, List<int> payload) {
    final Uint8List t = size(track);
    final int rel = relMs & 0xffff;
    return el(0xA3, <int>[
      ...t,
      (rel >> 8) & 0xff,
      rel & 0xff,
      flags,
      ...payload,
    ]);
  }
}

void main() {
  test('正常 ASS 轨：抽出 Dialogue，且首字段 ReadOrder 被丢掉', () {
    const String header = '[Script Info]\nScriptType: v4.00+\n\n'
        '[V4+ Styles]\nFormat: Name\nStyle: Default,Arial\n\n'
        '[Events]\nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, '
        'MarginV, Effect, Text\n';
    final Uint8List tracks = _Ebml.el(0x1654AE6B, <int>[
      ..._Ebml.el(0xAE, <int>[
        ..._Ebml.uintEl(0xD7, 2),
        ..._Ebml.uintEl(0x83, 0x11),
        ..._Ebml.strEl(0x86, 'S_TEXT/ASS'),
        ..._Ebml.strEl(0x63A2, header),
      ]),
    ]);
    final Uint8List cluster = _Ebml.el(0x1F43B675, <int>[
      ..._Ebml.uintEl(0xE7, 0),
      ..._Ebml.block(2, 1000, 0x80,
          utf8.encode('1,0,Def,,0,0,0,,{\\an2}你好世界')),
      ..._Ebml.block(2, 5000, 0x80,
          utf8.encode('2,0,Def,,0,0,0,,第二行')),
    ]);
    final Uint8List file =
        _Ebml.el(0x18538067, <int>[...tracks, ...cluster]);

    final MkvParseResult? r = MkvSubtitleExtractor.parse(file);
    expect(r, isNotNull);
    expect(r!.track!.codecId, 'S_TEXT/ASS');
    expect(r.cueCount, 2);
    expect(r.subtitleText, contains('[Events]'));
    // 只丢 ReadOrder；Layer 之后（Start/End/样式/正文）原样保留
    // 时间由 Block 时间戳补回（MKV 的 ASS payload 不带 Start/End）
    expect(
      r.subtitleText,
      contains('Dialogue: 0,0:00:01.00,0:00:03.00,Def,,0,0,0,,'),
    );
    expect(r.subtitleText, contains(r'{\an2}'));
    expect(r.subtitleText, contains('你好世界'));
    // ReadOrder 已经被去掉
    expect(r.subtitleText, isNot(contains('Dialogue: 1,')));
  });

  test('正常 SRT 轨：payload 的 start/end 转成 SRT 时间轴', () {
    final Uint8List tracks = _Ebml.el(0x1654AE6B, <int>[
      ..._Ebml.el(0xAE, <int>[
        ..._Ebml.uintEl(0xD7, 3),
        ..._Ebml.uintEl(0x83, 0x11),
        ..._Ebml.strEl(0x86, 'S_TEXT/UTF8'),
        ..._Ebml.el(0x63A2, <int>[]),
      ]),
    ]);
    final Uint8List cluster = _Ebml.el(0x1F43B675, <int>[
      ..._Ebml.uintEl(0xE7, 1000),
      ..._Ebml.block(3, 0, 0x80,
          utf8.encode('1000\n3000\nSRT-L1 plain text line one')),
    ]);
    final Uint8List file =
        _Ebml.el(0x18538067, <int>[...tracks, ...cluster]);

    final MkvParseResult? r = MkvSubtitleExtractor.parse(file);
    expect(r, isNotNull);
    expect(r!.track!.codecId, 'S_TEXT/UTF8');
    expect(r.cueCount, 1);
    expect(r.subtitleText, contains('00:00:01,000 --> 00:00:03,000'));
    expect(r.subtitleText, contains('SRT-L1 plain text line one'));
    expect(r.subtitleText, isNot(contains('1000\n3000')));
  });

  test('只有视频轨 → null（不产生空字幕）', () {
    final Uint8List tracks = _Ebml.el(0x1654AE6B, <int>[
      ..._Ebml.el(0xAE, <int>[
        ..._Ebml.uintEl(0xD7, 1),
        ..._Ebml.uintEl(0x83, 0x01), // video
        ..._Ebml.strEl(0x86, 'V_MPEG4/ISO/AVC'),
      ]),
    ]);
    final Uint8List file = _Ebml.el(0x18538067, <int>[
      ...tracks,
      ..._Ebml.el(0x1F43B675, <int>[
        ..._Ebml.uintEl(0xE7, 0),
        ..._Ebml.block(1, 0, 0x80, <int>[1, 2, 3, 4]),
      ]),
    ]);
    expect(MkvSubtitleExtractor.parse(file), isNull);
  });

  test('图形字幕（PGS）标记成 imageBased，不产出文本', () {
    final Uint8List tracks = _Ebml.el(0x1654AE6B, <int>[
      ..._Ebml.el(0xAE, <int>[
        ..._Ebml.uintEl(0xD7, 4),
        ..._Ebml.uintEl(0x83, 0x11),
        ..._Ebml.strEl(0x86, 'S_HDMV/PGS'),
      ]),
    ]);
    final Uint8List file = _Ebml.el(0x18538067, <int>[...tracks]);
    final MkvParseResult? r = MkvSubtitleExtractor.parse(file);
    expect(r, isNotNull);
    expect(r!.track!.isImageBased, isTrue);
    expect(r.cueCount, 0);
    expect(r.subtitleText, isEmpty);
  });

  test('不是 EBML 的字节流 → null，不抛', () {
    final Uint8List junk = Uint8List.fromList(List<int>.generate(64, (int i) => i));
    expect(MkvSubtitleExtractor.parse(junk), isNull);
  });
}
