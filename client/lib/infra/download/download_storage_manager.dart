class DownloadStoragePlan {
  final String relativeDirectory;
  final String absoluteDirectory;
  final String filename;

  const DownloadStoragePlan({
    required this.relativeDirectory,
    required this.absoluteDirectory,
    required this.filename,
  });

  String get relativePath => '$relativeDirectory/$filename';
  String get absolutePath => '$absoluteDirectory/$filename';
}

abstract class DownloadStorageManager {
  Future<DownloadStoragePlan> planFor({
    required String sourceId,
    required String suggestedFilename,
  });
}
