/// 分享链接解析（第二段）：从一段文字里抠出「哪个网盘 + 分享 id + 提取码」。
///
/// 不许抛异常：用户粘的可能是一整段分享文案、短链、带锚点、或者完全无关的文字；
/// 认不出来就返回 null，由 UI 说「没识别出分享链接」。
library;

import 'netdisk_adapter.dart';

/// 一条绑定好的分享
class ShareLink {
  const ShareLink({
    required this.kind,
    required this.shareId,
    this.receiveCode = '',
    this.rawUrl = '',
  });

  final NetdiskKind kind;

  /// 夸克 pwd_id / 115 share_code / 123 shareKey / 天翼 shareId
  final String shareId;

  /// 115 的接收码、夸克的提取码；没有就是空串
  final String receiveCode;

  /// 原文里的那条 URL（只用于回显，不进日志）
  final String rawUrl;

  /// 写进 accounts.extra 的键值（key 按各家 list/resolve 要的字段名）
  Map<String, String> toExtra() {
    switch (kind) {
      case NetdiskKind.quark:
        return <String, String>{
          'pwd_id': shareId,
          if (receiveCode.isNotEmpty) 'passcode': receiveCode,
        };
      case NetdiskKind.pan115:
        return <String, String>{
          'share_code': shareId,
          if (receiveCode.isNotEmpty) 'receive_code': receiveCode,
        };
      case NetdiskKind.pan123:
        return <String, String>{
          'share_key': shareId,
          if (receiveCode.isNotEmpty) 'share_pwd': receiveCode,
        };
      case NetdiskKind.tianyi:
        return <String, String>{
          'shareId': shareId,
          if (receiveCode.isNotEmpty) 'accessCode': receiveCode,
        };
      default:
        return const <String, String>{};
    }
  }

  String get display => receiveCode.isEmpty
      ? '${kind.label} · $shareId'
      : '${kind.label} · $shareId · 提取码 $receiveCode';
}

/// 认不出来就 null（调用方不许 try/catch 兜底，因为这里不抛）
ShareLink? parseShareLink(String raw) {
  if (raw.trim().isEmpty) return null;

  // 1) 先把文字里的第一条 http(s) 链接抠出来（用户经常整段粘贴）
  final String? url = extractUrl(raw);
  // 2) 没有链接时，看看是不是只贴了 id（夸克/115 的纯 id 也能认）
  if (url == null) return null;

  final String text = raw; // 提取码常在链接外面那段文字里
  final String noFragment = url.split('#').first;

  // 夸克：pan.quark.cn/s/{pwd_id}
  final RegExpMatch? quark =
      RegExp(r'pan\.quark\.cn/s/([A-Za-z0-9]+)').firstMatch(noFragment);
  if (quark != null) {
    return ShareLink(
      kind: NetdiskKind.quark,
      shareId: quark.group(1)!,
      receiveCode: _codeFrom(url, text),
      rawUrl: url,
    );
  }

  // 115：115.com / 115cdn.com / anxia.com 的 /s/{share_code}
  final RegExpMatch? p115 = RegExp(
    r'(?:115|115cdn|anxia)\.com/s/([A-Za-z0-9]+)',
  ).firstMatch(noFragment);
  if (p115 != null) {
    return ShareLink(
      kind: NetdiskKind.pan115,
      shareId: p115.group(1)!,
      receiveCode: _codeFrom(url, text),
      rawUrl: url,
    );
  }

  // 123：五个域名 + /s/{shareKey}
  final RegExpMatch? p123 = RegExp(
    r'(?:123684|123685|123912|123pan|123pan\.cn)\.com/s/([A-Za-z0-9_-]+)',
  ).firstMatch(noFragment);
  if (p123 != null) {
    return ShareLink(
      kind: NetdiskKind.pan123,
      shareId: p123.group(1)!,
      receiveCode: _codeFrom(url, text),
      rawUrl: url,
    );
  }

  // 天翼：cloud.189.cn/t/{shareId} 或 /web/share?code={shareId}
  final RegExpMatch? ty1 =
      RegExp(r'cloud\.189\.cn/t/([A-Za-z0-9]+)').firstMatch(noFragment);
  if (ty1 != null) {
    return ShareLink(
      kind: NetdiskKind.tianyi,
      shareId: ty1.group(1)!,
      receiveCode: _codeFrom(url, text),
      rawUrl: url,
    );
  }
  final RegExpMatch? ty2 =
      RegExp(r'cloud\.189\.cn/web/share\?[^#\s]*code=([A-Za-z0-9]+)')
          .firstMatch(noFragment);
  if (ty2 != null) {
    return ShareLink(
      kind: NetdiskKind.tianyi,
      shareId: ty2.group(1)!,
      receiveCode: _codeFrom(url, text),
      rawUrl: url,
    );
  }

  return null;
}

/// URL 合法的非空白字符（单独拎出来，避免靠相邻字面量拼接——那种写法只要往字符类里
/// 加一个单引号就会静默截断）
const String _urlChars = r'''[^\s，。！？、；：""''（）【】《》<>|]''';
final RegExp _urlRe = RegExp('https?://$_urlChars+');

/// 从一段文字里取第一条 http(s) 链接；去掉结尾的中英文标点
String? extractUrl(String raw) {
  final RegExpMatch? m = _urlRe.firstMatch(raw);
  if (m == null) return null;
  String url = m.group(0)!;
  while (url.isNotEmpty && '.,;:!?)]}"\''.contains(url[url.length - 1])) {
    url = url.substring(0, url.length - 1);
  }
  return url.isEmpty ? null : url;
}

/// 提取码：优先 URL 里的 ?pwd= / ?password= / &code=，
/// 其次从文案里找「提取码：abcd」「密码 abcd」
String _codeFrom(String url, String text) {
  final RegExpMatch? inUrl =
      RegExp(r'[?&](?:pwd|password|code|share_pwd)=([A-Za-z0-9]{1,8})')
          .firstMatch(url);
  if (inUrl != null) return inUrl.group(1)!;
  final RegExpMatch? inText = RegExp(
    r'(?:提取码|访问码|密码|pwd)\s*[:：]?\s*([A-Za-z0-9]{1,8})',
  ).firstMatch(text);
  return inText?.group(1) ?? '';
}
