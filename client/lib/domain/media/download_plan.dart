class DownloadPlan {
  final int runtimeId;
  final String mediaId;
  final String sourceId;
  final String title;
  final String kind;
  final Uri primaryUrl;
  final String mimeType;
  final String filename;
  final String savePath;
  final bool reuseCache;
  final bool supportsResume;

  const DownloadPlan({
    required this.runtimeId,
    required this.mediaId,
    required this.sourceId,
    required this.title,
    required this.kind,
    required this.primaryUrl,
    required this.mimeType,
    required this.filename,
    required this.savePath,
    required this.reuseCache,
    required this.supportsResume,
  });

  factory DownloadPlan.fromJson(Map<String, dynamic> json) {
    return DownloadPlan(
      runtimeId: (json['runtimeId'] as num?)?.toInt() ?? 0,
      mediaId: '${json['mediaId'] ?? ''}',
      sourceId: '${json['sourceId'] ?? ''}',
      title: '${json['title'] ?? ''}',
      kind: '${json['kind'] ?? ''}',
      primaryUrl: Uri.parse('${json['primaryUrl'] ?? ''}'),
      mimeType: '${json['mimeType'] ?? ''}',
      filename: '${json['filename'] ?? ''}',
      savePath: '${json['savePath'] ?? ''}',
      reuseCache: json['reuseCache'] != false,
      supportsResume: json['supportsResume'] != false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'runtimeId': runtimeId,
      'mediaId': mediaId,
      'sourceId': sourceId,
      'title': title,
      'kind': kind,
      'primaryUrl': primaryUrl.toString(),
      'mimeType': mimeType,
      'filename': filename,
      'savePath': savePath,
      'reuseCache': reuseCache,
      'supportsResume': supportsResume,
    };
  }
}
