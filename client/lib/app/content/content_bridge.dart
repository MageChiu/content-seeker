import '../../core/source_catalog.dart';
import '../../domain/download/download_request.dart';
import '../../models/play_request.dart';
import '../../models/search_result.dart';
import 'content_request.dart';

extension SearchResultContentBridge on SearchResult {
  ContentRequest toContentRequest({
    ContentIntent intent = ContentIntent.playback,
  }) {
    final primaryUri = _parseUri(playUrl);
    final canonicalUri = _parseUri(canonicalUrl);
    return ContentRequest(
      intent: intent,
      contentId: id.trim(),
      sourceId: sourceKey,
      title: title,
      mediaType: mediaType == MediaType.audio
          ? ContentMediaType.audio
          : ContentMediaType.video,
      primaryUri: primaryUri,
      fallbackUri: canonicalUri ?? primaryUri,
      sourceLabel: sourceLabel,
      thumbnailUrl: thumbnailUrl,
      durationSeconds: durationSeconds,
      description: description,
      filename: _suggestedFilename(
        explicit: '',
        title: title,
        contentId: id,
        uri: primaryUri,
      ),
      attributes: {
        'playbackKind': playbackKind.name,
        'availability': availability.name,
        'sourceTier': sourceTier.name,
      },
    );
  }
}

extension PlayRequestContentBridge on PlayRequest {
  ContentRequest toContentRequest() {
    final primaryUri = _parseUri(url);
    return ContentRequest(
      intent: ContentIntent.playback,
      contentId: contentId.trim(),
      sourceId: sourceHint.trim().toLowerCase(),
      title: title,
      mediaType: mediaType == PlayMediaType.audio
          ? ContentMediaType.audio
          : ContentMediaType.video,
      primaryUri: primaryUri,
      fallbackUri: primaryUri,
      sourceLabel: sourceLabel.isNotEmpty
          ? sourceLabel
          : sourceDescriptor(sourceHint).label,
      thumbnailUrl: thumbnailUrl,
      durationSeconds: durationSeconds,
      description: description,
      filename: _suggestedFilename(
        explicit: '',
        title: title,
        contentId: contentId,
        uri: primaryUri,
      ),
    );
  }
}

extension DownloadRequestContentBridge on DownloadRequest {
  ContentRequest toContentRequest() {
    return ContentRequest(
      intent: ContentIntent.download,
      contentId: mediaId.trim(),
      sourceId: sourceId.trim().toLowerCase(),
      title: filename,
      mediaType: _inferContentMediaType(filename, url),
      primaryUri: url,
      fallbackUri: url,
      filename: _suggestedFilename(
        explicit: filename,
        title: filename,
        contentId: mediaId,
        uri: url,
      ),
      headers: headers,
    );
  }
}

extension ContentRequestLegacyBridge on ContentRequest {
  PlayRequest toLegacyPlayRequest() {
    final uri = primaryUri ?? fallbackUri;
    if (uri == null || uri.toString().trim().isEmpty) {
      throw StateError('当前内容缺少可播放地址，无法桥接到旧播放请求。');
    }

    return PlayRequest(
      url: uri.toString(),
      title: title.isNotEmpty ? title : stableId,
      mediaType: _toLegacyPlayMediaType(mediaType),
      sourceHint: sourceId,
      contentId: contentId,
      thumbnailUrl: thumbnailUrl,
      durationSeconds: durationSeconds,
      description: description,
      sourceLabel: sourceLabel,
    );
  }

  DownloadRequest toLegacyDownloadRequest() {
    final uri = primaryUri ?? fallbackUri;
    if (uri == null) {
      throw StateError('当前内容缺少可下载地址，无法桥接到旧下载请求。');
    }

    return DownloadRequest(
      mediaId: contentId.isNotEmpty ? contentId : stableId,
      sourceId: sourceId,
      url: uri,
      filename: _suggestedFilename(
        explicit: filename,
        title: title,
        contentId: contentId,
        uri: uri,
      ),
      headers: headers,
    );
  }
}

Uri? _parseUri(String raw) {
  final normalized = raw.trim();
  if (normalized.isEmpty) {
    return null;
  }
  return Uri.tryParse(normalized);
}

ContentMediaType _inferContentMediaType(String filename, Uri uri) {
  final sample = '${filename.toLowerCase()} ${uri.path.toLowerCase()}';
  if (_looksLikeAudio(sample)) {
    return ContentMediaType.audio;
  }
  if (_looksLikeVideo(sample)) {
    return ContentMediaType.video;
  }
  return ContentMediaType.unknown;
}

PlayMediaType _toLegacyPlayMediaType(ContentMediaType mediaType) {
  switch (mediaType) {
    case ContentMediaType.audio:
      return PlayMediaType.audio;
    case ContentMediaType.unknown:
    case ContentMediaType.video:
      return PlayMediaType.video;
  }
}

String _suggestedFilename({
  required String explicit,
  required String title,
  required String contentId,
  required Uri? uri,
}) {
  final direct = explicit.trim();
  if (direct.isNotEmpty) {
    return direct;
  }

  final baseName = _sanitizeFilename(
    title.trim().isNotEmpty ? title.trim() : contentId.trim(),
  );
  final effectiveBaseName = baseName.isNotEmpty ? baseName : 'content';
  final extension = _pickExtension(uri);
  if (extension.isEmpty) {
    return effectiveBaseName;
  }
  return '$effectiveBaseName.$extension';
}

String _sanitizeFilename(String input) {
  return input.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
}

String _pickExtension(Uri? uri) {
  if (uri == null) {
    return '';
  }
  final segments = uri.pathSegments;
  if (segments.isEmpty) {
    return '';
  }
  final last = segments.last.trim();
  final dotIndex = last.lastIndexOf('.');
  if (dotIndex <= 0 || dotIndex >= last.length - 1) {
    return '';
  }
  return last.substring(dotIndex + 1).toLowerCase();
}

bool _looksLikeAudio(String sample) {
  return sample.contains('.mp3') ||
      sample.contains('.m4a') ||
      sample.contains('.aac') ||
      sample.contains('.wav') ||
      sample.contains('.flac') ||
      sample.contains('.ogg');
}

bool _looksLikeVideo(String sample) {
  return sample.contains('.mp4') ||
      sample.contains('.m3u8') ||
      sample.contains('.webm') ||
      sample.contains('.mkv') ||
      sample.contains('.mov');
}
