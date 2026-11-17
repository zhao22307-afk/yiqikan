/// 房主变更提示（纯函数，方便单测）。
///
/// 只在「房主真的换了人」时给一句话：
/// - 新 hostId 是我 → 你成为了房主
/// - 旧 hostId 是我 → 房主已移交（我被降级了）
/// - 别人之间换（理论上只有房主能发起，所以不会发生）→ 不给提示
///
/// 首帧（before 为空）不算变更：进房时我可能本来就是房主，那不是「成为」。
String hostChangeText({
  required String? before,
  required String? after,
  required String me,
}) {
  final String b = before ?? '';
  final String a = after ?? '';
  if (me.isEmpty || a.isEmpty) return '';
  if (b.isEmpty) return '';
  if (b == a) return '';
  if (a == me) return '你成为了房主';
  if (b == me) return '房主已移交';
  return '';
}
