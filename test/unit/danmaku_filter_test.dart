import 'package:flutter_test/flutter_test.dart';
import 'package:yiqikan/domain/danmaku_filter.dart';

void main() {
  test('正常短句直接通过', () {
    final FilterResult r = DanmakuFilter.check('这段好看', <String>[]);
    expect(r.reason, FilterReason.none);
    expect(r.blocked, isFalse);
  });

  test('太短：去空白后不足 2 个字', () {
    expect(DanmakuFilter.check('哦', <String>[]).reason, FilterReason.tooShort);
    expect(DanmakuFilter.check('   ', <String>[]).reason, FilterReason.tooShort);
  });

  test('太长：超过 50 字', () {
    final String long = '字' * 51;
    expect(DanmakuFilter.check(long, <String>[]).reason, FilterReason.tooLong);
  });

  test('重复：最近窗口里同文本已经出现 2 次，第 3 次被挡', () {
    final FilterResult r =
        DanmakuFilter.check('前排', <String>['前排', '前排', '别的']);
    expect(r.reason, FilterReason.repeat);
    expect(r.hit, contains('3x'));
  });

  test('重复：只出现 1 次时不挡', () {
    expect(DanmakuFilter.check('前排', <String>['前排']).reason,
        FilterReason.none);
  });

  test('刷屏：同字符连续 6 个以上', () {
    final FilterResult r = DanmakuFilter.check('哈哈哈哈哈哈哈哈', <String>[]);
    expect(r.reason, FilterReason.spam);
    expect(r.hit, contains('哈'));
  });

  test('刷屏：90% 以上是标点', () {
    expect(DanmakuFilter.check('！！！！！！！', <String>[]).reason,
        FilterReason.spam);
  });

  test('剧透：命中词表', () {
    final FilterResult r = DanmakuFilter.check('凶手是管家', <String>[]);
    expect(r.reason, FilterReason.spoiler);
    expect(r.hit, '凶手是');
  });

  test('剧透：命中「反转」这类单词', () {
    expect(DanmakuFilter.check('等下有大反转', <String>[]).reason,
        FilterReason.spoiler);
  });

  test('关掉全部规则后什么都不挡', () {
    const FilterOptions off = FilterOptions(
      tooShort: false,
      tooLong: false,
      repeat: false,
      spam: false,
      spoiler: false,
    );
    expect(DanmakuFilter.check('哈哈哈', <String>[], options: off).reason,
        FilterReason.none);
    expect(DanmakuFilter.check('凶', <String>[], options: off).reason,
        FilterReason.none);
  });

  test('规则开关可单独关：只关剧透，其余仍生效', () {
    const FilterOptions noSpoiler = FilterOptions(spoiler: false);
    expect(DanmakuFilter.check('凶手是管家', <String>[], options: noSpoiler).reason,
        FilterReason.none);
    expect(DanmakuFilter.check('哈哈哈哈哈哈哈哈', <String>[],
            options: noSpoiler)
        .reason, FilterReason.spam);
  });

  test('FilterOptions 的 JSON 往返', () {
    const FilterOptions a = FilterOptions(repeat: false, spoiler: false);
    final FilterOptions b = FilterOptions.fromJson(a.toJson());
    expect(b.repeat, isFalse);
    expect(b.spoiler, isFalse);
    expect(b.tooShort, isTrue);
    expect(FilterOptions.fromJson(null).any, isTrue);
  });
}
