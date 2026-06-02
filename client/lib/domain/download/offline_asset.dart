enum OfflineAssetKind { snapshot, download }

class OfflineAsset {
  final String assetId;
  final String mediaId;
  final String sourceId;
  final String title;
  final OfflineAssetKind kind;
  final String localPath;
  final String mimeType;
  final int durationMs;
  final int fileSizeBytes;
  final String contentType;
  final String originalUrl;
  final DateTime createdAt;
  final DateTime? lastPlayedAt;

  const OfflineAsset({
    required this.assetId,
    required this.mediaId,
    this.sourceId = '',
    required this.title,
    this.kind = OfflineAssetKind.download,
    required this.localPath,
    required this.mimeType,
    required this.durationMs,
    this.fileSizeBytes = 0,
    this.contentType = '',
    this.originalUrl = '',
    required this.createdAt,
    this.lastPlayedAt,
  });
}
