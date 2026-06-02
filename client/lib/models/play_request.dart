// 播放请求模型。
// 搜索层与播放层之间的唯一连接点。
// 播放层不感知搜索结果的具体结构，只需要播放所需的最少信息。

enum PlayMediaType { video, audio }

class PlayRequest {
  /// 要播放的 URL（可以是页面 URL 或直接流 URL）
  final String url;

  /// 显示标题
  final String title;

  /// 媒体类型
  final PlayMediaType mediaType;

  /// 来源标识（如 "bilibili"、"youtube"），用于选择提取器
  final String sourceHint;

  /// 来源内容 ID（如 BV 号、video ID）
  final String contentId;

  /// 缩略图 URL
  final String thumbnailUrl;

  /// 时长（秒），0 表示未知
  final int durationSeconds;

  /// 描述文本
  final String description;

  /// 来源显示名称
  final String sourceLabel;

  const PlayRequest({
    required this.url,
    required this.title,
    this.mediaType = PlayMediaType.video,
    this.sourceHint = '',
    this.contentId = '',
    this.thumbnailUrl = '',
    this.durationSeconds = 0,
    this.description = '',
    this.sourceLabel = '',
  });

  bool get hasUrl => url.trim().isNotEmpty;

  String get durationFormatted {
    final h = durationSeconds ~/ 3600;
    final m = (durationSeconds % 3600) ~/ 60;
    final s = durationSeconds % 60;
    if (h > 0) return '$h' 'h${m}m${s}s';
    if (m > 0) return '$m:${s.toString().padLeft(2, '0')}';
    return '0:${s.toString().padLeft(2, '0')}';
  }
}
