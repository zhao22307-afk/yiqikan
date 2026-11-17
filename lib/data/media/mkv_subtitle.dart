/// MKV/WebM 内嵌字幕抽取（I-6 B 方案，纯 Dart，无 FFI）。
///
/// 背景：fvp(mdk) 的内嵌字幕文本回调在真机上是 0 次（ASS/SRT 都是，见 15 §A5 实测），
/// 所以不去修内核，而是把内嵌轨抽成一份标准字幕文件，走已经跑通的外挂路径
/// （Flutter 自绘 SubtitleOverlay / mpv --sub-file）。
///
/// 只做三件事：认 EBML 结构 → 找到文本字幕轨 → 拼成 .ass / .srt 文本。
/// 任何一步不认（结构坏了 / 没有字幕轨 / 是 PGS/VOBSUB 位图字幕）都返回 null，
/// 调用方照常播放，不弹错。
library;

import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:io';

/// 抽出来的字幕
class ExtractedSubtitle {
  const ExtractedSubtitle({
    required this.path,
    required this.codecId,
    required this.cueCount,
    required this.imageBased,
  });

  /// 落到临时目录里的 .ass / .srt
  final String path;
  final String codecId;
  final int cueCount;
  final bool imageBased;

  bool get hasText => !imageBased && cueCount > 0;
}

/// 一条字幕轨的元信息（单测和日志都用得上）
class MkvSubtitleTrack {
  const MkvSubtitleTrack({
    required this.number,
    required this.codecId,
    required this.codecPrivate,
  });

  final int number;
  final String codecId;
  final Uint8List codecPrivate;

  bool get isText =>
      codecId == 'S_TEXT/ASS' ||
      codecId == 'S_TEXT/SSA' ||
      codecId == 'S_TEXT/UTF8' ||
      codecId == 'S_TEXT/WEBVTT' ||
      codecId == 'S_ASS' ||
      codecId == 'S_SSA';

  bool get isImageBased =>
      codecId == 'S_HDMV/PGS' || codecId == 'S_VOBSUB' || codecId == 'S_HDMV/TEXTST';
}

/// 解析结果：轨 + 已经拼好的字幕正文
class MkvParseResult {
  const MkvParseResult({
    required this.track,
    required this.subtitleText,
    required this.cueCount,
  });

  final MkvSubtitleTrack? track;
  final String subtitleText;
  final int cueCount;
}

/// EBML 元素 ID（ID 保留长度标记位，和文件里的字节原样比）
class _Id {
  static const int segment = 0x18538067;
  static const int tracks = 0x1654AE6B;
  static const int trackEntry = 0xAE;
  static const int trackNumber = 0xD7;
  static const int trackType = 0x83;
  static const int codecId = 0x86;
  static const int codecPrivate = 0x63A2;
  static const int cluster = 0x1F43B675;
  static const int timestamp = 0xE7;
  static const int simpleBlock = 0xA3;
  static const int blockGroup = 0xA0;
  static const int block = 0xA1;
  static const int blockDuration = 0x9B;
}

class _Vint {
  const _Vint(this.value, this.length);
  final int value;
  final int length;
}

class MkvSubtitleExtractor {
  /// 太大的文件不整块读进内存（怕 OOM）；超过这个尺寸就返回 null，照常播放
  static const int maxBytes = 256 * 1024 * 1024;

  /// 从本地文件抽字幕；抽不出来返回 null（绝不抛）
  /// 纯解析入口（单测直接用字节流喂这里）
  static MkvParseResult? parse(Uint8List data) {
    try {
      final MkvSubtitleTrack? track = _findSubtitleTrack(data);
      if (track == null) return null;
      if (!track.isText) {
        return MkvParseResult(track: track, subtitleText: '', cueCount: 0);
      }
      final List<_Cue> cues = _collectCues(data, track.number);
      if (cues.isEmpty) {
        return MkvParseResult(track: track, subtitleText: '', cueCount: 0);
      }
      if (track.codecId.contains('UTF8') || track.codecId.contains('WEBVTT')) {
        return MkvParseResult(
          track: track,
          subtitleText: _toSrt(cues),
          cueCount: cues.length,
        );
      }
      return MkvParseResult(
        track: track,
        subtitleText: _toAss(track.codecPrivate, cues),
        cueCount: cues.length,
      );
    } on Object {
      return null;
    }
  }

  // ── EBML 基础 ───────────────────────────────────────────────

  /// 读变长整数；keepMarker=true 时保留长度标记位（ID 用），false 时去掉（size 用）
  static _Vint _readVint(Uint8List d, int off, {required bool keepMarker}) {
    final int first = d[off];
    int len = 1;
    int mask = 0x80;
    while (len <= 8 && (first & mask) == 0) {
      len++;
      mask >>= 1;
    }
    if (len > 8) throw const FormatException('EBML vint 太长');
    if (off + len > d.length) throw const FormatException('EBML 越界');
    int value = keepMarker ? first : (first & (mask - 1));
    for (int i = 1; i < len; i++) {
      value = (value << 8) | d[off + i];
    }
    // size 的「全 1」表示未知长度，交给调用方当作「到父级结束」
    return _Vint(value, len);
  }

  static bool _isUnknownSize(_Vint v) {
    final int max = (1 << (7 * v.length)) - 1;
    return v.value == max;
  }

  /// 遍历 [start, end) 里的元素，回调 (id, payloadStart, payloadEnd)
  static void _walk(
    Uint8List d,
    int start,
    int end,
    void Function(int id, int payloadStart, int payloadEnd) onElement,
  ) {
    int p = start;
    final int limit = end > d.length ? d.length : end;
    while (p < limit) {
      final _Vint id;
      try {
        id = _readVint(d, p, keepMarker: true);
      } on Object {
        return;
      }
      final int afterId = p + id.length;
      if (afterId >= limit) return;
      final _Vint size = _readVint(d, afterId, keepMarker: false);
      final int payloadStart = afterId + size.length;
      int payloadEnd;
      if (_isUnknownSize(size)) {
        payloadEnd = limit; // 未知长度：吃到父级结束
      } else {
        payloadEnd = payloadStart + size.value;
      }
      if (payloadEnd > d.length) payloadEnd = d.length;
      if (payloadStart > limit) return;
      onElement(id.value, payloadStart, payloadEnd);
      if (payloadEnd <= p) return;
      p = payloadEnd;
    }
  }

  static int _uint(Uint8List d, int start, int end) {
    int v = 0;
    for (int i = start; i < end; i++) {
      v = (v << 8) | d[i];
    }
    return v;
  }

  static Uint8List _bytes(Uint8List d, int start, int end) =>
      Uint8List.sublistView(d, start, end > d.length ? d.length : end);

  // ── 找字幕轨 ───────────────────────────────────────────────

  static MkvSubtitleTrack? _findSubtitleTrack(Uint8List d) {
    MkvSubtitleTrack? found;
    _walk(d, 0, d.length, (int id, int s, int e) {
      if (found != null) return;
      if (id != _Id.segment && id != _Id.tracks) {
        // Segment 之外的顶层元素（EBML header 等）直接跳过
        return;
      }
      if (id == _Id.segment) {
        _findInTracks(d, s, e, (MkvSubtitleTrack t) => found ??= t);
      } else {
        _findInTracks(d, s, e, (MkvSubtitleTrack t) => found ??= t);
      }
    });
    return found;
  }

  static void _findInTracks(
    Uint8List d,
    int start,
    int end,
    void Function(MkvSubtitleTrack) onTrack,
  ) {
    _walk(d, start, end, (int id, int s, int e) {
      if (id == _Id.tracks) {
        _findInTracks(d, s, e, onTrack);
        return;
      }
      if (id != _Id.trackEntry) return;
      int number = 0;
      int type = 0;
      String codec = '';
      Uint8List priv = Uint8List(0);
      _walk(d, s, e, (int cid, int cs, int ce) {
        switch (cid) {
          case _Id.trackNumber:
            number = _uint(d, cs, ce);
          case _Id.trackType:
            type = _uint(d, cs, ce);
          case _Id.codecId:
            codec = utf8.decode(_bytes(d, cs, ce), allowMalformed: true).trim();
          case _Id.codecPrivate:
            priv = Uint8List.fromList(_bytes(d, cs, ce));
        }
      });
      // 0x11 = subtitle
      if (type == 0x11) {
        onTrack(MkvSubtitleTrack(
          number: number,
          codecId: codec,
          codecPrivate: priv,
        ));
      }
    });
  }

  // ── 收 Block ───────────────────────────────────────────────

  static List<_Cue> _collectCues(Uint8List d, int trackNumber) {
    final List<_Cue> cues = <_Cue>[];
    _walk(d, 0, d.length, (int id, int s, int e) {
      if (id == _Id.segment) {
        _walk(d, s, e, (int cid, int cs, int ce) {
          if (cid == _Id.cluster) _readCluster(d, cs, ce, trackNumber, cues);
        });
      }
    });
    cues.sort((_Cue a, _Cue b) => a.startMs.compareTo(b.startMs));
    return cues;
  }

  static void _readCluster(
    Uint8List d,
    int start,
    int end,
    int trackNumber,
    List<_Cue> cues,
  ) {
    int base = 0;
    _walk(d, start, end, (int id, int s, int e) {
      switch (id) {
        case _Id.timestamp:
          base = _uint(d, s, e);
        case _Id.simpleBlock:
          final _Cue? c = _readBlock(d, s, e, base, trackNumber, null);
          if (c != null) cues.add(c);
        case _Id.blockGroup:
          int duration = 0;
          int? blockStart;
          int? blockEnd;
          _walk(d, s, e, (int gid, int gs, int ge) {
            if (gid == _Id.block) {
              blockStart = gs;
              blockEnd = ge;
            } else if (gid == _Id.blockDuration) {
              duration = _uint(d, gs, ge);
            }
          });
          if (blockStart != null && blockEnd != null) {
            final _Cue? c = _readBlock(
              d,
              blockStart!,
              blockEnd!,
              base,
              trackNumber,
              duration == 0 ? null : duration,
            );
            if (c != null) cues.add(c);
          }
      }
    });
  }

  /// Block 结构：trackNumber(VINT) + int16 相对时间 + flags(1B) + payload
  static _Cue? _readBlock(
    Uint8List d,
    int start,
    int end,
    int base,
    int wantTrack,
    int? durationMs,
  ) {
    if (end - start < 4) return null;
    final _Vint track = _readVint(d, start, keepMarker: false);
    final int p = start + track.length;
    if (p + 3 > end) return null;
    if (track.value != wantTrack) return null;
    final int rel = (d[p] << 8 | d[p + 1]).toSigned(16);
    final int flags = d[p + 2];
    int payload = p + 3;
    if (payload >= end) return null;

    // lacing：0x06 两位非 0 表示有分片；字幕很少用，按分片数逐段读
    final int lacing = (flags >> 1) & 0x03;
    final List<Uint8List> parts = <Uint8List>[];
    if (lacing == 0) {
      parts.add(_bytes(d, payload, end));
    } else {
      try {
        final int count = d[payload] + 1;
        payload += 1;
        final List<int> sizes = <int>[];
        if (lacing == 1) {
          // Xiph
          for (int i = 0; i < count - 1; i++) {
            int v = 0;
            while (true) {
              final int b = d[payload++];
              v += b;
              if (b != 255) break;
            }
            sizes.add(v);
          }
        } else if (lacing == 3) {
          // EBML lacing
          final _Vint first = _readVint(d, payload, keepMarker: false);
          payload += first.length;
          sizes.add(first.value);
          int prev = first.value;
          for (int i = 1; i < count - 1; i++) {
            final _Vint delta = _readVint(d, payload, keepMarker: false);
            payload += delta.length;
            // 有符号差值
            final int sign = (delta.value >> (7 * delta.length - 1)) & 1;
            final int mask = (1 << (7 * delta.length - 1)) - 1;
            final int v = delta.value & mask;
            final int d2 = sign == 1 ? v - mask - 1 : v;
            prev += d2;
            sizes.add(prev);
          }
        }
        int off = payload;
        for (final int size in sizes) {
          parts.add(_bytes(d, off, off + size));
          off += size;
        }
        parts.add(_bytes(d, off, end));
      } on Object {
        return null;
      }
    }

    final String text = parts
        .map((Uint8List b) => utf8.decode(b, allowMalformed: true))
        .join('\n')
        .trimRight();
    if (text.isEmpty) return null;
    final int startMs = base + rel;
    final int endMs = durationMs != null
        ? startMs + durationMs
        : startMs + 2000; // 没给 BlockDuration 就按 2 秒兜住
    return _Cue(startMs, endMs, text);
  }

  // ── 输出 ───────────────────────────────────────────────────

  /// ASS 轨：CodecPrivate 就是文件头，Block 是 Dialogue 的字段（首字段 ReadOrder 要丢）
  static String _toAss(Uint8List codecPrivate, List<_Cue> cues) {
    final String header = utf8.decode(codecPrivate, allowMalformed: true);
    final StringBuffer sb = StringBuffer();
    if (header.contains('[Events]')) {
      sb.write(header.trimRight());
      sb.write('\n');
    } else {
      sb.write('[Script Info]\nScriptType: v4.00+\n'
          'PlayResX: 640\nPlayResY: 360\n\n'
          '[V4+ Styles]\n'
          'Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, '
          'OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, '
          'ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, '
          'Alignment, MarginL, MarginR, MarginV, Encoding\n'
          'Style: Default,Arial,20,&H00FFFFFF,&H000000FF,&H00000000,&H00000000,'
          '0,0,0,0,100,100,0,0,1,2,0,2,10,10,10,1\n\n'
          '[Events]\n'
          'Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, '
          'Effect, Text\n');
      if (header.trim().isNotEmpty) {
        // 有头但没 [Events]：把 Events 段补上
        sb.write('$header\n');
      }
    }
    for (final _Cue c in cues) {
      // MKV 里的 ASS Block payload 是 ReadOrder,Layer,Style,Name,ML,MR,MV,Effect,Text
      // —— 没有 Start/End，时间来自 Block 时间戳，这里补回去。
      final int c1 = c.text.indexOf(',');
      final String rest = c1 < 0 ? c.text : c.text.substring(c1 + 1);
      final int c2 = rest.indexOf(',');
      final String layer = c2 < 0 ? rest : rest.substring(0, c2);
      final String tail = c2 < 0 ? '' : rest.substring(c2 + 1);
      sb.write('Dialogue: $layer,${_assTime(c.startMs)},${_assTime(c.endMs)},'
          '$tail\n');
    }
    return sb.toString();
  }

  /// SRT 轨：payload 是「start_ms\nend_ms\ntext」
  static String _toSrt(List<_Cue> cues) {
    final StringBuffer sb = StringBuffer();
    int i = 1;
    for (final _Cue c in cues) {
      sb.write('$i\n');
      sb.write('${_srtTime(c.startMs)} --> ${_srtTime(c.endMs)}\n');
      sb.write('${_srtText(c.text)}\n\n');
      i++;
    }
    return sb.toString();
  }

  /// SRT / UTF8 轨的 payload 前两行是起止毫秒，正文从第三行开始
  static String _srtText(String raw) {
    final List<String> lines = raw.split('\n');
    if (lines.length >= 3 &&
        int.tryParse(lines[0].trim()) != null &&
        int.tryParse(lines[1].trim()) != null) {
      return lines.sublist(2).join('\n').trim();
    }
    return raw.trim();
  }


  static String _assTime(int ms) {
    final int h = ms ~/ 3600000;
    final int m = (ms % 3600000) ~/ 60000;
    final int s = (ms % 60000) ~/ 1000;
    final int cs = (ms % 1000) ~/ 10;
    return '$h:${_two(m)}:${_two(s)}.${_two(cs)}';
  }

  static String _srtTime(int ms) {
    final int h = ms ~/ 3600000;
    final int m = (ms % 3600000) ~/ 60000;
    final int s = (ms % 60000) ~/ 1000;
    final int msec = ms % 1000;
    return '${_two(h)}:${_two(m)}:${_two(s)},${m3(msec)}';
  }

  static String _two(int v) => v.toString().padLeft(2, '0');
  static String m3(int v) => v.toString().padLeft(3, '0');

  static String _hash(String s) {
    int h = 0;
    for (final int c in s.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return h.toRadixString(16);
  }

  // ── 流式抽取（RandomAccessFile，内存稳在几 MB，不设大小上限）────────────

  /// 抽内嵌字幕（对外入口）。大文件走流式：只顺序扫 Cluster，非字幕 Block 直接 seek 跳过。
  static Future<ExtractedSubtitle?> extractFromFile(String path) async {
    try {
      final File f = File(path);
      if (!await f.exists()) return null;
      final int size = await f.length();
      final int rssBefore = ProcessInfo.currentRss;
      final Stopwatch sw = Stopwatch()..start();
      final ExtractedSubtitle? out = await Isolate.run(
        () => extractFromFileSync(path),
      );
      sw.stop();
      // 流式取证：整文件不读进内存，峰值应与文件大小无关（3GB 样本也该稳在几十 MB）
      final int peak = ProcessInfo.maxRss;
      debugPrint('[YQK-MKVSUB] streaming bytes=$size '
          'rss_before=${_mib(rssBefore)} peak_rss=${_mib(peak)} delta=${_mib(peak - rssBefore)} '
          'ms=${sw.elapsedMilliseconds} cues=${out?.cueCount ?? 0}');
      return out;
    } on Object {
      return null;
    }
  }

  static String _mib(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';

  /// 同步版（跑在 Isolate 里；也可以单测直接调）
  static ExtractedSubtitle? extractFromFileSync(String path) {
    RandomAccessFile? raf;
    try {
      final File f = File(path);
      if (!f.existsSync()) return null;
      raf = f.openSync();
      final int size = raf.lengthSync();
      if (size <= 0) return null;

      final MkvSubtitleTrack? track = _findTrackStreaming(raf, size);
      if (track == null) return null;
      if (!track.isText) {
        return ExtractedSubtitle(
          path: '',
          codecId: track.codecId,
          cueCount: 0,
          imageBased: track.isImageBased,
        );
      }
      final List<_Cue> cues = _scanCuesStreaming(raf, size, track.number);
      if (cues.isEmpty) {
        return ExtractedSubtitle(
          path: '',
          codecId: track.codecId,
          cueCount: 0,
          imageBased: false,
        );
      }
      final bool srt = track.codecId.contains('UTF8') ||
          track.codecId.contains('WEBVTT');
      final String text =
          srt ? _toSrt(cues) : _toAss(track.codecPrivate, cues);
      final String out = '${Directory.systemTemp.path}'
          '${Platform.pathSeparator}sub_${_hash(path)}.${srt ? 'srt' : 'ass'}';
      File(out).writeAsStringSync(text, flush: true);
      return ExtractedSubtitle(
        path: out,
        codecId: track.codecId,
        cueCount: cues.length,
        imageBased: false,
      );
    } on Object {
      return null;
    } finally {
      try {
        raf?.closeSync();
      } on Object {
        // 关不掉就算了，别把失败吞成的异常再抛出去
      }
    }
  }

  /// 头部：读前几 MB 找 Tracks。Tracks 找不到就翻倍再读（上限 128 MB，几乎不会到）。
  static MkvSubtitleTrack? _findTrackStreaming(RandomAccessFile raf, int size) {
    int window = 2 * 1024 * 1024;
    while (window <= 128 * 1024 * 1024) {
      final int n = window < size ? window : size;
      raf.setPositionSync(0);
      final Uint8List head = raf.readSync(n);
      final MkvSubtitleTrack? t = _findSubtitleTrack(head);
      if (t != null) return t;
      if (n >= size) return null;
      window *= 2;
    }
    return null;
  }

  /// 顺序扫 Segment 下的 Cluster；只把命中字幕轨的 Block 读进内存。
  static List<_Cue> _scanCuesStreaming(
    RandomAccessFile raf,
    int size,
    int trackNumber,
  ) {
    final List<_Cue> cues = <_Cue>[];
    int p = _segmentPayloadStart(raf, size);
    int guard = 0;
    while (p < size && guard++ < 2000000) {
      final _Hdr? h = _peekHeader(raf, p, size);
      if (h == null) break;
      if (h.id == 0) break; // 全零填充（稀疏文件尾部）或已到 EOF：直接收工
      if (h.id != _Id.cluster) {
        if (h.size < 0) break; // 未知长度的非 Cluster，没法跳
        final int next = h.payloadStart + h.size;
        if (next <= p) break; // size 写坏时防止原地打转
        p = next;
        continue;
      }
      // Cluster：边界已知就走边界，未知就走「遇到下一个 Cluster 为止」
      final int clusterEnd = h.size >= 0 ? h.payloadStart + h.size : size;
      p = _scanCluster(raf, h.payloadStart, clusterEnd, size, trackNumber, cues);
      if (p <= h.payloadStart) break;
    }
    cues.sort((_Cue a, _Cue b) => a.startMs.compareTo(b.startMs));
    return cues;
  }

  /// 返回这个 Cluster 结束的位置
  static int _scanCluster(
    RandomAccessFile raf,
    int start,
    int end,
    int size,
    int trackNumber,
    List<_Cue> cues,
  ) {
    int p = start;
    int base = 0;
    int guard = 0;
    while (p < end && p < size && guard++ < 1000000) {
      final _Hdr? h = _peekHeader(raf, p, size);
      if (h == null) return size;
      // 长度未知的 Cluster：碰到新的 Cluster/Segment 就收工
      if (h.size < 0) return h.start;
      final int next = h.payloadStart + h.size;
      if (next > size) return size;
      switch (h.id) {
        case _Id.timestamp:
          if (h.size <= 8) {
            raf.setPositionSync(h.payloadStart);
            final Uint8List b = raf.readSync(h.size);
            base = _uint(b, 0, b.length);
          }
        case _Id.simpleBlock:
          final Uint8List b = _readPayload(raf, h, size);
          final _Cue? c = _readBlock(b, 0, b.length, base, trackNumber, null);
          if (c != null) cues.add(c);
        case _Id.blockGroup:
          final Uint8List b = _readPayload(raf, h, size);
          int duration = 0;
          int? bs;
          int? be;
          _walk(b, 0, b.length, (int gid, int gs, int ge) {
            if (gid == _Id.block) {
              bs = gs;
              be = ge;
            } else if (gid == _Id.blockDuration) {
              duration = _uint(b, gs, ge);
            }
          });
          if (bs != null && be != null) {
            final _Cue? c = _readBlock(
              b,
              bs!,
              be!,
              base,
              trackNumber,
              duration == 0 ? null : duration,
            );
            if (c != null) cues.add(c);
          }
      }
      p = next;
    }
    return p;
  }

  static Uint8List _readPayload(RandomAccessFile raf, _Hdr h, int size) {
    if (h.size <= 0) return Uint8List(0);
    final int n = h.size > size - h.payloadStart ? size - h.payloadStart : h.size;
    if (n > 16 * 1024 * 1024) return Uint8List(0); // 单块 16MB 以上不是字幕
    raf.setPositionSync(h.payloadStart);
    return raf.readSync(n);
  }

  /// Segment 的 payload 起点：跳过 EBML header，找到 0x18538067
  static int _segmentPayloadStart(RandomAccessFile raf, int size) {
    int p = 0;
    int guard = 0;
    while (p < size && guard++ < 64) {
      final _Hdr? h = _peekHeader(raf, p, size);
      if (h == null) return 0;
      if (h.id == _Id.segment) return h.payloadStart;
      if (h.size < 0) return 0;
      p = h.payloadStart + h.size;
    }
    return 0;
  }

  /// 读一个元素头（最多 12 字节），解析成 id / size / payload 起点
  static _Hdr? _peekHeader(RandomAccessFile raf, int pos, int fileLength) {
    if (pos < 0 || pos >= fileLength) return null;
    final int n = (fileLength - pos) < 12 ? (fileLength - pos) : 12;
    raf.setPositionSync(pos);
    final Uint8List b = raf.readSync(n);
    if (b.isEmpty) return null;
    final _Vint id;
    final _Vint sz;
    try {
      id = _readVint(b, 0, keepMarker: true);
      sz = _readVint(b, id.length, keepMarker: false);
    } on Object {
      return null;
    }
    final int payloadStart = pos + id.length + sz.length;
    final bool unknown = _isUnknownSize(sz);
    return _Hdr(
      start: pos,
      id: id.value,
      size: unknown ? -1 : sz.value,
      payloadStart: payloadStart,
    );
  }
}

class _Hdr {
  const _Hdr({required this.start, required this.id, required this.size, required this.payloadStart});
  final int start;
  final int id;
  final int size;
  final int payloadStart;
}

class _Cue {
  const _Cue(this.startMs, this.endMs, this.text);
  final int startMs;
  final int endMs;
  final String text;
}
