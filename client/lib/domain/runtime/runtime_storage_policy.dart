class RuntimeManagedDirectoryPolicy {
  final String customPath;
  final String bookmark;

  const RuntimeManagedDirectoryPolicy({
    this.customPath = '',
    this.bookmark = '',
  });

  bool get hasCustomPath => customPath.trim().isNotEmpty;

  RuntimeManagedDirectoryPolicy copyWith({
    String? customPath,
    String? bookmark,
  }) {
    return RuntimeManagedDirectoryPolicy(
      customPath: customPath ?? this.customPath,
      bookmark: bookmark ?? this.bookmark,
    );
  }
}

class RuntimeStoragePolicy {
  final bool progressiveCacheEnabled;
  final RuntimeManagedDirectoryPolicy cacheDirectory;
  final RuntimeManagedDirectoryPolicy recordingDirectory;

  const RuntimeStoragePolicy({
    this.progressiveCacheEnabled = false,
    this.cacheDirectory = const RuntimeManagedDirectoryPolicy(),
    this.recordingDirectory = const RuntimeManagedDirectoryPolicy(),
  });

  RuntimeStoragePolicy copyWith({
    bool? progressiveCacheEnabled,
    RuntimeManagedDirectoryPolicy? cacheDirectory,
    RuntimeManagedDirectoryPolicy? recordingDirectory,
  }) {
    return RuntimeStoragePolicy(
      progressiveCacheEnabled:
          progressiveCacheEnabled ?? this.progressiveCacheEnabled,
      cacheDirectory: cacheDirectory ?? this.cacheDirectory,
      recordingDirectory: recordingDirectory ?? this.recordingDirectory,
    );
  }
}
