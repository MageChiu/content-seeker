import 'dart:convert';
import 'dart:io';

import '../../domain/download/offline_asset.dart';
import '../../platform/storage/app_storage_paths.dart';
import 'offline_asset_repository.dart';

class JsonOfflineAssetRepository implements OfflineAssetRepository {
  final AppStoragePaths storagePaths;

  List<OfflineAsset>? _cache;

  JsonOfflineAssetRepository({
    this.storagePaths = const AppStoragePaths(),
  });

  @override
  Future<List<OfflineAsset>> listAssets() async {
    final items = await _loadAssets();
    return List<OfflineAsset>.unmodifiable(items);
  }

  @override
  Future<void> saveAsset(OfflineAsset asset) async {
    final items = await _loadAssets();
    final index = items.indexWhere((item) => item.assetId == asset.assetId);
    if (index >= 0) {
      items[index] = asset;
    } else {
      items.add(asset);
    }
    await _persist(items);
  }

  @override
  Future<void> removeAsset(String assetId) async {
    final items = await _loadAssets();
    items.removeWhere((item) => item.assetId == assetId);
    await _persist(items);
  }

  @override
  Future<OfflineAsset?> findByMediaId(String mediaId) async {
    final items = await _loadAssets();
    for (final item in items.reversed) {
      if (item.mediaId == mediaId) {
        return item;
      }
    }
    return null;
  }

  Future<List<OfflineAsset>> _loadAssets() async {
    if (_cache != null) {
      return _cache!;
    }
    final file = await _dataFile();
    if (!await file.exists()) {
      _cache = <OfflineAsset>[];
      return _cache!;
    }
    final raw = await file.readAsString();
    if (raw.trim().isEmpty) {
      _cache = <OfflineAsset>[];
      return _cache!;
    }
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      _cache = <OfflineAsset>[];
      return _cache!;
    }
    _cache = decoded
        .whereType<Map>()
        .map(
          (item) => _decodeAsset(Map<String, dynamic>.from(item)),
        )
        .toList(growable: true);
    return _cache!;
  }

  Future<void> _persist(List<OfflineAsset> items) async {
    final file = await _dataFile();
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(
        items.map(_encodeAsset).toList(growable: false),
      ),
    );
    _cache = items;
  }

  Future<File> _dataFile() {
    return storagePaths.metadataFile('offline_assets.json');
  }

  Map<String, Object?> _encodeAsset(OfflineAsset asset) {
    return {
      'asset_id': asset.assetId,
      'media_id': asset.mediaId,
      'source_id': asset.sourceId,
      'title': asset.title,
      'kind': asset.kind.name,
      'local_path': asset.localPath,
      'mime_type': asset.mimeType,
      'duration_ms': asset.durationMs,
      'file_size_bytes': asset.fileSizeBytes,
      'content_type': asset.contentType,
      'original_url': asset.originalUrl,
      'created_at': asset.createdAt.toIso8601String(),
      'last_played_at': asset.lastPlayedAt?.toIso8601String(),
    };
  }

  OfflineAsset _decodeAsset(Map<String, dynamic> json) {
    return OfflineAsset(
      assetId: '${json['asset_id'] ?? ''}',
      mediaId: '${json['media_id'] ?? ''}',
      sourceId: '${json['source_id'] ?? ''}',
      title: '${json['title'] ?? ''}',
      kind: _parseKind(json['kind']),
      localPath: '${json['local_path'] ?? ''}',
      mimeType: '${json['mime_type'] ?? ''}',
      durationMs: _readInt(json['duration_ms']),
      fileSizeBytes: _readInt(json['file_size_bytes']),
      contentType: '${json['content_type'] ?? ''}',
      originalUrl: '${json['original_url'] ?? ''}',
      createdAt: DateTime.tryParse('${json['created_at'] ?? ''}') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      lastPlayedAt: DateTime.tryParse('${json['last_played_at'] ?? ''}'),
    );
  }

  OfflineAssetKind _parseKind(Object? value) {
    switch ('$value'.trim().toLowerCase()) {
      case 'snapshot':
        return OfflineAssetKind.snapshot;
      default:
        return OfflineAssetKind.download;
    }
  }

  int _readInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.round();
    }
    return int.tryParse('$value') ?? 0;
  }
}
