import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// M10 B 组：DLNA 发送端（投到电视）。
///
/// 只用 dart:io 自写（不引新依赖）：
///   1. SSDP M-SEARCH 到 239.255.255.250:1900，收 LOCATION；
///   2. GET 设备描述 XML，正则取 friendlyName + AVTransport 的 controlURL；
///   3. SOAP POST 到 controlURL 做 SetAVTransportURI / Play / Pause / Stop / Seek。
///
/// 见 15 号 §B22 的四个坑：
///   - DIDL-Lite 里的 URL 必须 XML 转义（`&` 会打断 XML）；
///   - controlURL 多半是相对路径，要拿 LOCATION 的 scheme://host:port 拼；
///   - 有些电视只认 `SetAVTransportURI` 之后再 `Play`，一步到位不行；
///   - MX 太大会让设备慢回，这里固定 2 秒、发两包。
class DlnaDevice {
  DlnaDevice({
    required this.friendlyName,
    required this.location,
    required this.controlUrl,
    required this.modelName,
  });

  final String friendlyName;
  final String location;
  final String controlUrl;
  final String modelName;

  @override
  String toString() => '$friendlyName ($modelName) $controlUrl';
}

class DlnaSender {
  DlnaSender(this.device);

  final DlnaDevice device;

  static const String _avt = 'urn:schemas-upnp-org:service:AVTransport:1';

  /// 投一个 url 过去并立刻播放。
  Future<void> play(String url, {String? title}) async {
    await setAvTransportUri(url, title: title);
    await _play();
  }

  Future<void> setAvTransportUri(String url, {String? title}) async {
    final String meta = _didl(url, title ?? '一起看');
    await _soap('SetAVTransportURI', '''
<InstanceID>0</InstanceID>
<CurrentURI>${_xml(url)}</CurrentURI>
<CurrentURIMetaData>${_xml(meta)}</CurrentURIMetaData>''');
  }

  Future<void> pause() => _soap('Pause', '<InstanceID>0</InstanceID>');

  /// 已经是同一部片子时，只补一条 Play（不重设 URI）。
  Future<void> resume() => _play();

  Future<void> stop() => _soap('Stop', '<InstanceID>0</InstanceID>');

  Future<void> seek(Duration at) {
    final int s = at.inSeconds;
    final String hms = '${(s ~/ 3600).toString().padLeft(2, '0')}:'
        '${((s % 3600) ~/ 60).toString().padLeft(2, '0')}:'
        '${(s % 60).toString().padLeft(2, '0')}';
    return _soap('Seek', '<InstanceID>0</InstanceID><Unit>REL_TIME</Unit>'
        '<Target>$hms</Target>');
  }

  Future<void> _play() =>
      _soap('Play', '<InstanceID>0</InstanceID><Speed>1</Speed>');

  /// 发一条 SOAP 请求。失败抛 [DlnaException]，由调用方转成 toast。
  Future<String> _soap(String action, String body) async {
    final String envelope = '<?xml version="1.0" encoding="utf-8"?>'
        '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
        's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">'
        '<s:Body><u:$action xmlns:u="$_avt">$body</u:$action></s:Body>'
        '</s:Envelope>';
    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 4);
    try {
      final HttpClientRequest req = await client.postUrl(Uri.parse(device.controlUrl));
      req.headers.set('Content-Type', 'text/xml; charset="utf-8"');
      req.headers.set('SOAPAction', '"$_avt#$action"');
      final List<int> bytes = utf8.encode(envelope);
      req.headers.set('Content-Length', '${bytes.length}');
      req.add(bytes);
      final HttpClientResponse res = await req.close().timeout(const Duration(seconds: 6));
      final String text = await res.transform(utf8.decoder).join();
      if (res.statusCode >= 400) {
        throw DlnaException('$action HTTP ${res.statusCode}: ${_trim(text)}');
      }
      return text;
    } finally {
      client.close(force: true);
    }
  }

  static String _didl(String url, String title) =>
      '<DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" '
      'xmlns:dc="http://purl.org/dc/elements/1.1/" '
      'xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/">'
      '<item id="0" parentID="-1" restricted="1">'
      '<dc:title>${_xml(title)}</dc:title>'
      '<upnp:class>object.item.videoItem</upnp:class>'
      '<res protocolInfo="http-get:*:video/*:*">${_xml(url)}</res>'
      '</item></DIDL-Lite>';

  static String _trim(String s) {
    final String t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t.length > 160 ? '${t.substring(0, 160)}…' : t;
  }
}

class DlnaException implements Exception {
  DlnaException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 找局域网里的 MediaRenderer。
///
/// 返回按 friendlyName 去重后的列表（同一台设备常回多个包）。
Future<List<DlnaDevice>> ssdpDiscover({
  Duration timeout = const Duration(seconds: 3),
  void Function(String)? onLog,
}) async {
  final void Function(String) log = onLog ?? (String _) {};
  final RawDatagramSocket sock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  sock.broadcastEnabled = true;
  final Map<String, String> locations = <String, String>{};
  final Completer<void> done = Completer<void>();
  late Timer timer;

  sock.listen((RawSocketEvent e) {
    if (e != RawSocketEvent.read) return;
    final Datagram? dg = sock.receive();
    if (dg == null) return;
    final String text = utf8.decode(dg.data, allowMalformed: true);
    final String? loc = _header(text, 'LOCATION');
    if (loc != null && loc.isNotEmpty) locations[loc] = loc;
  });

  final List<int> msg = utf8.encode('M-SEARCH * HTTP/1.1\r\n'
      'HOST: 239.255.255.250:1900\r\n'
      'MAN: "ssdp:discover"\r\n'
      'MX: 2\r\n'
      'ST: urn:schemas-upnp-org:device:MediaRenderer:1\r\n'
      '\r\n');
  final InternetAddress group = InternetAddress('239.255.255.250');
  void send() {
    try {
      sock.send(msg, group, 1900);
    } catch (e) {
      log('[YQK-DLNA] ssdp send fail $e');
    }
  }

  send();
  Timer(const Duration(milliseconds: 200), send);
  timer = Timer(timeout, () {
    if (!done.isCompleted) done.complete();
  });
  await done.future;
  timer.cancel();
  sock.close();
  log('[YQK-DLNA] ssdp found=${locations.length}');

  final List<DlnaDevice> out = <DlnaDevice>[];
  for (final String loc in locations.keys) {
    try {
      final DlnaDevice? d = await _describe(loc, onLog: log);
      if (d == null) continue;
      if (out.any((DlnaDevice x) => x.friendlyName == d.friendlyName)) continue;
      out.add(d);
    } catch (e) {
      log('[YQK-DLNA] describe fail $loc $e');
    }
  }
  return out;
}

/// 取设备描述，找 AVTransport 的 controlURL。
Future<DlnaDevice?> _describe(String location, {void Function(String)? onLog}) async {
  final void Function(String) log = onLog ?? (String _) {};
  final Uri base = Uri.parse(location);
  final HttpClient client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
  try {
    final HttpClientRequest req = await client.getUrl(base);
    final HttpClientResponse res = await req.close().timeout(const Duration(seconds: 6));
    final String xml = await res.transform(utf8.decoder).join();
    final String name = _tag(xml, 'friendlyName') ?? 'DLNA 设备';
    final String model = _tag(xml, 'modelName') ?? '';
    // AVTransport 服务的 controlURL：先切出包含 AVTransport:1 的 <service> 块
    String ctrl = '';
    final RegExp svc = RegExp(r'<service>(.*?)</service>', dotAll: true);
    for (final RegExpMatch m in svc.allMatches(xml)) {
      final String block = m.group(1) ?? '';
      if (!block.contains('AVTransport:1')) continue;
      ctrl = _tag(block, 'controlURL') ?? '';
      break;
    }
    if (ctrl.isEmpty) {
      log('[YQK-DLNA] no AVTransport controlURL at $location');
      return null;
    }
    final String abs = ctrl.startsWith('http')
        ? ctrl
        : '${base.scheme}://${base.host}:${base.hasPort ? base.port : 80}'
            '${ctrl.startsWith('/') ? '' : '/'}$ctrl';
    log('[YQK-DLNA] device name=$name model=$model ctrl=$abs');
    return DlnaDevice(
        friendlyName: name, location: location, controlUrl: abs, modelName: model);
  } finally {
    client.close(force: true);
  }
}

String? _tag(String xml, String name) {
  final RegExp re = RegExp('<$name[^>]*>(.*?)</$name>', dotAll: true);
  final RegExpMatch? m = re.firstMatch(xml);
  if (m == null) return null;
  return _unxml(m.group(1)!.trim());
}

String? _header(String text, String key) {
  for (final String line in const LineSplitter().convert(text)) {
    final int i = line.indexOf(':');
    if (i <= 0) continue;
    if (line.substring(0, i).trim().toUpperCase() == key) {
      return line.substring(i + 1).trim();
    }
  }
  return null;
}

String _xml(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

String _unxml(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&');

/// 单测入口：play() 用的就是同一个 _didl，转义处出错会直接在这里暴露。
String dlnaDidlFor(String url, String title) => DlnaSender._didl(url, title);

/// 单测入口：SOAP 体里的 URL 转义。
String dlnaEscape(String s) => _xml(s);
