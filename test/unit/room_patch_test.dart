import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

/// 纯逻辑复刻：服务端 Api.applyPlayback 的 patch 语义（只覆盖 src 里真有的字段）
Map<String, dynamic> applyPatch(Map<String, dynamic> cur, Map<String, dynamic> src) {
  final Map<String, dynamic> out = Map<String, dynamic>.from(cur);
  if (src.containsKey('position') || src.containsKey('progress')) {
    out['position'] = (src['position'] as num?)?.toDouble() ?? 0.0;
  }
  if (src.containsKey('duration')) {
    out['duration'] = (src['duration'] as num?)?.toDouble() ?? 0.0;
  }
  if (src.containsKey('playing') || src.containsKey('is_playing')) {
    out['playing'] = src['playing'] as bool? ?? src['is_playing'] as bool? ?? false;
  }
  if (src.containsKey('episode') || src.containsKey('current_episode')) {
    out['episode'] = src['episode'] as int? ?? src['current_episode'] as int? ?? 0;
  }
  if (src.containsKey('speed') || src.containsKey('rate')) {
    out['speed'] = (src['speed'] as num?)?.toDouble() ?? (src['rate'] as num?)?.toDouble() ?? 1.0;
  }
  return out;
}

void main() {
  test('patch 语义：只带 speed 时位置/时长/集数都不动', () {
    final Map<String, dynamic> cur = <String, dynamic>{
      'position': 300.0,
      'duration': 600.0,
      'playing': true,
      'episode': 7,
      'speed': 1.0,
    };
    final Map<String, dynamic> out = applyPatch(cur, <String, dynamic>{'speed': 2.0});
    expect(out['speed'], 2.0);
    expect(out['position'], 300.0);
    expect(out['duration'], 600.0);
    expect(out['episode'], 7);
    expect(out['playing'], isTrue);
  });

  test('rate 动作不带 position：审批后不产生位置变更', () {
    final Map<String, dynamic> cur = <String, dynamic>{
      'position': 300.0,
      'speed': 1.0,
      'playing': true,
    };
    // LocalServer 在 rate 分支只 put speed，不 put position
    final Map<String, dynamic> apply = <String, dynamic>{'speed': 1.5};
    final Map<String, dynamic> out = applyPatch(cur, apply);
    expect(out['position'], 300.0);
    expect(out['speed'], 1.5);
  });

  test('state 广播读 cur：rate 动作不会广播缺省 playing', () {
    final Map<String, dynamic> cur = <String, dynamic>{
      'position': 300.0,
      'playing': true,
      'speed': 1.5,
      'duration': 600.0,
      'episode': 7,
    };
    final Map<String, dynamic> inner = <String, dynamic>{
      'playing': cur['playing'],
      'position': cur['position'],
      'rate': cur['speed'],
      'duration': cur['duration'],
      'episode': cur['episode'],
    };
    expect(jsonEncode(inner), contains('"playing":true'));
    expect(inner['rate'], 1.5);
    expect(inner['duration'], 600.0);
  });
}
