import 'dart:convert';

/// 一个下载任务（15 号「F2 下载」：queued → running → paused → done / failed）。
///
/// id 和 [LibraryMedia] 用同一套：`md5(url)[0:16]`，这样同一片子重复点下载
/// 能命中同一条任务，不会出现两个进度条抢同一个文件。
enum DownloadState { queued, running, paused, done, failed }

class DownloadTask {
  DownloadTask({
    required this.id,
    required this.url,
    required this.title,
    required this.savePath,
    this.received = 0,
    this.total = -1,
    this.state = DownloadState.queued,
    this.error,
    this.createdAt = 0,
  });

  final String id;
  final String url;
  final String title;
  final String savePath;

  /// 已收字节（续传时就是文件当前长度）
  int received;

  /// 服务器没给 Content-Length 时是 -1
  int total;

  DownloadState state;
  String? error;

  /// 两次采样算出来的瞬时速度，只给 UI 看
  double speedKbps = 0;

  /// 毫秒时间戳，用来稳定排序（同批入队的按创建顺序显示）
  int createdAt;

  double get progress {
    if (total > 0) return (received / total).clamp(0.0, 1.0);
    return 0;
  }

  bool get isActive =>
      state == DownloadState.running || state == DownloadState.queued;

  static String sizeText(int bytes) {
    if (bytes < 0) return '未知';
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '$bytes B';
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'url': url,
        'title': title,
        'savePath': savePath,
        'received': received,
        'total': total,
        'state': state.name,
        'error': error,
        'createdAt': createdAt,
      };

  static DownloadTask? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final Map<String, dynamic> m = raw.cast<String, dynamic>();
    final Object? id = m['id'];
    final Object? url = m['url'];
    if (id is! String || id.isEmpty || url is! String || url.isEmpty) {
      return null;
    }
    DownloadState st = DownloadState.queued;
    for (final DownloadState s in DownloadState.values) {
      if (s.name == m['state']) st = s;
    }
    // 上次进程死掉时正在跑的任务，恢复成「已暂停」，等用户点继续
    if (st == DownloadState.running) st = DownloadState.paused;
    return DownloadTask(
      id: id,
      url: url,
      title: (m['title'] as String?) ?? url,
      savePath: (m['savePath'] as String?) ?? '',
      received: (m['received'] as num?)?.toInt() ?? 0,
      total: (m['total'] as num?)?.toInt() ?? -1,
      state: st,
      error: m['error'] as String?,
      createdAt: (m['createdAt'] as num?)?.toInt() ?? 0,
    );
  }

  static String encodeList(List<DownloadTask> list) =>
      jsonEncode(list.map((DownloadTask t) => t.toJson()).toList());

  static List<DownloadTask> decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return <DownloadTask>[];
    try {
      final Object? parsed = jsonDecode(raw);
      if (parsed is! List) return <DownloadTask>[];
      return parsed
          .map(DownloadTask.fromJson)
          .whereType<DownloadTask>()
          .toList();
    } catch (_) {
      return <DownloadTask>[];
    }
  }
}
