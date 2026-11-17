import 'package:flutter_test/flutter_test.dart';
import 'package:yiqikan/domain/entities/subtitle.dart';

/// PlayRes 是 ASS 的坐标系原点：解析错了（比如退回默认 384x288），
/// 字幕就会整体偏移、被裁。这里把「文件头有 PlayRes」「文件头没有」两种都钉住。
void main() {
  const String ass = '''
[Script Info]
Title: libass probe
ScriptType: v4.00+
PlayResX: 640
PlayResY: 360

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Def,Microsoft YaHei,20,&H00FFFFFF,&H000000FF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,1,1,2,10,10,14,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Dialogue: 0,0:00:00.00,0:00:04.00,Def,,0,0,0,,{\\pos(320,300)}四
''';

  test('读到文件头里的 PlayResX/PlayResY', () {
    final SubtitleData d = SubtitleData.parse(ass);
    expect(d.playResX, 640);
    expect(d.playResY, 360);
    expect(d.cues.length, 1);
    expect(d.styles.containsKey('Def'), isTrue);
    expect(d.styles['Def']!.marginV, 14);
  });

  test('文件头没有 PlayRes 时退回 384x288', () {
    final SubtitleData d = SubtitleData.parse('''
1
00:00:00,000 --> 00:00:02,000
plain srt
''');
    expect(d.playResX, 384);
    expect(d.playResY, 288);
    expect(d.cues.length, 1);
  });
}
