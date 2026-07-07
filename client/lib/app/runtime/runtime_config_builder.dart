import '../../domain/runtime/runtime_storage_policy.dart';

Map<String, dynamic> buildRuntimeConfig({
  required String appSupportRoot,
  RuntimeStoragePolicy? storagePolicy,
}) {
  return {
    'storageRoot': '$appSupportRoot/runtime',
    'progressiveCacheEnabled': storagePolicy?.progressiveCacheEnabled ?? false,
    'cacheDir': storagePolicy?.cacheDirectory.customPath ?? '',
    'cacheDirBookmark': storagePolicy?.cacheDirectory.bookmark ?? '',
    'recordingDir': storagePolicy?.recordingDirectory.customPath ?? '',
    'recordingDirBookmark': storagePolicy?.recordingDirectory.bookmark ?? '',
  };
}
