import 'package:flutter_test/flutter_test.dart';
import 'package:yiqikan/core/perm/permission_guide.dart';

void main() {
  test('normalizeStatus：授权优先，其次永久拒绝，再其次被拒', () {
    expect(
      normalizeStatus(granted: true, permanentlyDenied: true, denied: true, restricted: true),
      PermState.granted,
    );
    expect(
      normalizeStatus(granted: false, permanentlyDenied: true, denied: true, restricted: false),
      PermState.permanentlyDenied,
    );
    expect(
      normalizeStatus(granted: false, permanentlyDenied: false, denied: true, restricted: false),
      PermState.denied,
    );
    expect(
      normalizeStatus(granted: false, permanentlyDenied: false, denied: false, restricted: false),
      PermState.notRequested,
    );
  });

  test('四种状态的文案与按钮', () {
    expect(PermState.granted.actionLabel, isNull);
    expect(PermState.notRequested.actionLabel, '申请');
    expect(PermState.denied.actionLabel, '再试一次');
    expect(PermState.permanentlyDenied.actionLabel, '去系统设置');
    expect(PermState.granted.label, '已授权');
  });

  test('只有 denied / notRequested 允许直接申请', () {
    expect(PermState.notRequested.canRequest, isTrue);
    expect(PermState.denied.canRequest, isTrue);
    expect(PermState.permanentlyDenied.canRequest, isFalse);
    expect(PermState.granted.canRequest, isFalse);
  });

  test('五种权限都有名称与用途说明', () {
    for (final PermKind k in PermKind.values) {
      expect(PermissionGuide.titleOf(k), isNotEmpty);
      expect(PermissionGuide.whyOf(k), isNotEmpty);
    }
    expect(PermissionGuide.titleOf(PermKind.installUnknown), '安装未知应用');
  });
}
