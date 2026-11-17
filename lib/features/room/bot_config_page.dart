import 'package:flutter/material.dart';

import '../../platform/room/bot_state.dart';
import '../../platform/room/room_client.dart';
import '../../theme/app_colors.dart';

/// 房主的「房间 Bot」设置页（D27）。
///
/// 只有房主用得到：服务端 `handleBotConfig` 对非房主回 `not_host`，
/// 所以入口也只放在房主菜单里。这里不做任何持久化——服务端是内存态，
/// 客户端一存就会出现「UI 说有、服务端没有」。
class BotConfigPage extends StatefulWidget {
  const BotConfigPage({super.key, required this.roomClient});

  final RoomClient roomClient;

  @override
  State<BotConfigPage> createState() => _BotConfigPageState();
}

class _BotConfigPageState extends State<BotConfigPage> {
  late final TextEditingController _name;
  late final TextEditingController _aliases;
  late final TextEditingController _reply;
  late final TextEditingController _cooldown;
  late final TextEditingController _quota;

  bool _enabled = true;
  bool _occupySlot = false; // 默认不占位，与 10 号 D28 一致

  String? _nameError;
  String? _cooldownError;
  String? _quotaError;

  @override
  void initState() {
    super.initState();
    final BotState s = widget.roomClient.botState.value ?? const BotState();
    _enabled = s.enabled;
    _occupySlot = s.occupySlot;
    _name = TextEditingController(text: s.name);
    _aliases = TextEditingController(
      text: s.aliases.isEmpty ? s.name : s.aliases.join(','),
    );
    _reply = TextEditingController(text: s.reply);
    _cooldown = TextEditingController(text: '${s.cooldownSec}');
    _quota = TextEditingController(text: '${s.hourlyQuota}');
  }

  @override
  void dispose() {
    _name.dispose();
    _aliases.dispose();
    _reply.dispose();
    _cooldown.dispose();
    _quota.dispose();
    super.dispose();
  }

  int? _positive(TextEditingController c) {
    final int? v = int.tryParse(c.text.trim());
    if (v == null || v <= 0) return null;
    return v;
  }

  void _save() {
    final String name = _name.text.trim();
    final int? cd = _positive(_cooldown);
    final int? quota = _positive(_quota);
    setState(() {
      _nameError = name.isEmpty ? '名字不能为空' : null;
      _cooldownError = cd == null ? '要填正整数' : null;
      _quotaError = quota == null ? '要填正整数' : null;
    });
    if (_nameError != null || _cooldownError != null || _quotaError != null) {
      // 就地提示，绝不把非法值静默改成 0
      return;
    }
    final String aliasText = _aliases.text.trim();
    widget.roomClient.sendBotConfig(cfg: <String, dynamic>{
      'enabled': _enabled,
      'name': name,
      'aliases': aliasText.isEmpty ? name : aliasText,
      'reply': _reply.text.trim().isEmpty ? '我在' : _reply.text.trim(),
      'cooldownSec': cd,
      'hourlyQuota': quota,
      'occupySlot': _occupySlot,
    });
    debugPrint('[YQK-BOT] config sent enabled=$_enabled name=$name '
        'aliases=$aliasText cd=$cd quota=$quota slot=$_occupySlot');
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('房间 Bot'),
        actions: <Widget>[
          TextButton(
            onPressed: _save,
            child: const Text('保存'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: <Widget>[
          SwitchListTile(
            value: _enabled,
            onChanged: (bool v) => setState(() => _enabled = v),
            title: const Text('启用'),
            subtitle: const Text('关掉之后 @ 它不会回复'),
          ),
          _field(
            controller: _name,
            label: '名字',
            hint: '小看',
            error: _nameError,
          ),
          _field(
            controller: _aliases,
            label: '别名',
            hint: '用逗号分隔，如：小看,小看酱',
          ),
          _field(
            controller: _reply,
            label: '回复语',
            hint: '我在',
          ),
          _field(
            controller: _cooldown,
            label: '冷却（秒）',
            hint: '10',
            number: true,
            error: _cooldownError,
          ),
          _field(
            controller: _quota,
            label: '每小时上限',
            hint: '30',
            number: true,
            error: _quotaError,
          ),
          SwitchListTile(
            value: _occupySlot,
            onChanged: (bool v) => setState(() => _occupySlot = v),
            title: const Text('占一个成员位'),
            subtitle: const Text('打开时房间人数把它算进去（最多 4 人的语音房不受影响）'),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Text(
              'Bot 只在本地按规则回复，不接外部服务；配置只存在内存，重启后恢复默认。',
              style: TextStyle(fontSize: 12, color: AppColors.textDim),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    String? hint,
    String? error,
    bool number = false,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: TextField(
        controller: controller,
        keyboardType: number ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          errorText: error,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }
}