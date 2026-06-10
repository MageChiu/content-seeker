enum MaterializedAssetStorageKind { temp, cache, offline }

enum MaterializedAssetCompleteness { partial, full }

class MaterializedAsset {
  final String assetId;
  final String mediaId;
  final MaterializedAssetStorageKind storageKind;
  final MaterializedAssetCompleteness completeness;
  final String manifestPath;
  final String primaryFilePath;
  final List<String> auxiliaryFiles;
  final int bytesTotal;
  final int bytesReady;

  const MaterializedAsset({
    required this.assetId,
    required this.mediaId,
    required this.storageKind,
    required this.completeness,
    this.manifestPath = '',
    this.primaryFilePath = '',
    this.auxiliaryFiles = const [],
    this.bytesTotal = 0,
    this.bytesReady = 0,
  });

  factory MaterializedAsset.fromJson(Map<String, dynamic> json) {
    return MaterializedAsset(
      assetId: '${json['assetId'] ?? ''}',
      mediaId: '${json['mediaId'] ?? ''}',
      storageKind: _parseStorageKind('${json['storageKind'] ?? ''}'),
      completeness: _parseCompleteness('${json['completeness'] ?? ''}'),
      manifestPath: '${json['manifestPath'] ?? ''}',
      primaryFilePath: '${json['primaryFilePath'] ?? ''}',
      auxiliaryFiles: (json['auxiliaryFiles'] as List<dynamic>? ?? const [])
          .map((item) => '$item')
          .toList(growable: false),
      bytesTotal: (json['bytesTotal'] as num?)?.toInt() ?? 0,
      bytesReady: (json['bytesReady'] as num?)?.toInt() ?? 0,
    );
  }
}

MaterializedAssetStorageKind _parseStorageKind(String value) {
  switch (value) {
    case 'offline':
      return MaterializedAssetStorageKind.offline;
    case 'cache':
      return MaterializedAssetStorageKind.cache;
    case 'temp':
    default:
      return MaterializedAssetStorageKind.temp;
  }
}

MaterializedAssetCompleteness _parseCompleteness(String value) {
  switch (value) {
    case 'full':
      return MaterializedAssetCompleteness.full;
    case 'partial':
    default:
      return MaterializedAssetCompleteness.partial;
  }
}
