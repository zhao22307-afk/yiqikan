import 'package:flutter_test/flutter_test.dart';
import 'package:yiqikan/features/room/follow_rules.dart';

void main() {
  group('shouldFollowState', () {
    test('房主自己不跟随（权威源）', () {
      expect(
        shouldFollowState(me: 'm_h', by: 'm_g', isHost: true, seekingLocally: false),
        isFalse,
      );
    });

    test('自己发的 state 不回灌（防自激）', () {
      expect(
        shouldFollowState(me: 'm_g', by: 'm_g', isHost: false, seekingLocally: false),
        isFalse,
      );
    });

    test('别人发的 state 要跟', () {
      expect(
        shouldFollowState(me: 'm_g', by: 'm_h', isHost: false, seekingLocally: false),
        isTrue,
      );
    });

    test('本地拖动期间不跟', () {
      expect(
        shouldFollowState(me: 'm_g', by: 'm_h', isHost: false, seekingLocally: true),
        isFalse,
      );
    });
  });

  group('followTarget（入参是本地单调时钟经过的毫秒）', () {
    test('播放中按倍速外推', () {
      // 100s、播放中、1.0x、收到帧后过了 2000ms → 102
      final double t = followTarget(
        position: 100,
        playing: true,
        rate: 1,
        elapsedMsLocal: 2000,
      );
      expect(t, closeTo(102, 0.001));
    });

    test('暂停时不外推', () {
      final double t = followTarget(
        position: 100,
        playing: false,
        rate: 1.5,
        elapsedMsLocal: 5000,
      );
      expect(t, 100);
    });

    test('1.5 倍速外推按倍率算', () {
      final double t = followTarget(
        position: 10,
        playing: true,
        rate: 1.5,
        elapsedMsLocal: 4000,
      );
      expect(t, closeTo(16, 0.001));
    });

    test('刚收到帧（经过 0ms）返回原位置', () {
      final double t = followTarget(
        position: 42,
        playing: true,
        rate: 2,
        elapsedMsLocal: 0,
      );
      expect(t, 42);
    });
  });

  group('needsSeek', () {
    test('2 秒以内不动（避免抖动）', () {
      expect(needsSeek(100.0, 101.9), isFalse);
    });

    test('超过 2 秒才硬 seek', () {
      expect(needsSeek(100.0, 97.5), isTrue);
    });
  });

  test('free 模式：房主也要跟别人（by != me）', () {
    expect(
      shouldFollowState(
        me: 'm_host',
        by: 'm_guest',
        isHost: true,
        seekingLocally: false,
        freeMode: true,
      ),
      isTrue,
    );
  });

  test('host 模式：房主不跟别人', () {
    expect(
      shouldFollowState(
        me: 'm_host',
        by: 'm_guest',
        isHost: true,
        seekingLocally: false,
      ),
      isFalse,
    );
  });

  // 13 号 D21 三档（0.3 / 0.7 是判据，不许调）
  // 用 mine=0.0 直接给偏差，避免 10.7-10.0 这类浮点误差把 0.70 算成 0.6999…
  group('decideFollow 三档边界', () {
    test('0.29 不动', () {
      expect(decideFollow(0.29, 0.0), FollowAction.none);
    });
    test('0.31 变速', () {
      expect(decideFollow(0.31, 0.0), FollowAction.speed);
    });
    test('0.69 变速', () {
      expect(decideFollow(0.69, 0.0), FollowAction.speed);
    });
    test('0.71 硬跳', () {
      expect(decideFollow(0.71, 0.0), FollowAction.seek);
    });
    test('负方向 -0.29 不动', () {
      expect(decideFollow(-0.29, 0.0), FollowAction.none);
    });
    test('负方向 -0.31 变速', () {
      expect(decideFollow(-0.31, 0.0), FollowAction.speed);
    });
    test('负方向 -0.71 硬跳', () {
      expect(decideFollow(-0.71, 0.0), FollowAction.seek);
    });
  });

  group('catchUpRate', () {
    test('偏差 0.30 → 约等于 base（区间左端点）', () {
      expect(catchUpRate(0.30, 0.0), closeTo(1.0, 0.001));
    });
    test('偏差 0.70 → 等于 base（区间外）', () {
      expect(catchUpRate(0.70, 0.0), closeTo(1.0, 0.001));
    });
    test('偏差 0.50 → base*1.15（±0.02）', () {
      expect(catchUpRate(0.50, 0.0), closeTo(1.15, 0.02));
    });
    test('负方向 0.50 → 减速（< 1.0）', () {
      final double r = catchUpRate(-0.50, 0.0);
      expect(r, lessThan(1.0));
      expect(r, closeTo(1 / 1.15, 0.02));
    });
    test('偏差 0.10（< fine）→ base', () {
      expect(catchUpRate(0.10, 0.0), closeTo(1.0, 0.001));
    });
  });
}
