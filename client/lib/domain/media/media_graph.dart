class MediaAuth {
  final Map<String, String> headers;
  final Map<String, String> cookies;

  const MediaAuth({
    this.headers = const {},
    this.cookies = const {},
  });

  factory MediaAuth.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const MediaAuth();
    }
    return MediaAuth(
      headers: (json['headers'] as Map<String, dynamic>? ?? const {})
          .map((key, value) => MapEntry(key, '$value')),
      cookies: (json['cookies'] as Map<String, dynamic>? ?? const {})
          .map((key, value) => MapEntry(key, '$value')),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'headers': headers,
      'cookies': cookies,
    };
  }
}

class MediaTrack {
  final String id;
  final String kind;
  final Uri url;
  final String mimeType;

  const MediaTrack({
    required this.id,
    required this.kind,
    required this.url,
    this.mimeType = '',
  });

  factory MediaTrack.fromJson(Map<String, dynamic> json) {
    return MediaTrack(
      id: '${json['id'] ?? ''}',
      kind: '${json['kind'] ?? ''}',
      url: Uri.parse('${json['url'] ?? ''}'),
      mimeType: '${json['mimeType'] ?? ''}',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'kind': kind,
      'url': url.toString(),
      'mimeType': mimeType,
    };
  }
}

class MediaFallback {
  final String label;
  final Uri url;

  const MediaFallback({
    required this.label,
    required this.url,
  });

  factory MediaFallback.fromJson(Map<String, dynamic> json) {
    return MediaFallback(
      label: '${json['label'] ?? ''}',
      url: Uri.parse('${json['url'] ?? ''}'),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'label': label,
      'url': url.toString(),
    };
  }
}

class MediaGraph {
  final int runtimeId;
  final String mediaId;
  final String sourceId;
  final String title;
  final String kind;
  final Uri primaryUrl;
  final Uri inputUrl;
  final String displayLabel;
  final String resolverKind;
  final String mimeType;
  final Uri? secondaryAudioUrl;
  final List<MediaTrack> tracks;
  final List<MediaFallback> fallbacks;
  final MediaAuth auth;

  const MediaGraph({
    required this.runtimeId,
    required this.mediaId,
    required this.sourceId,
    required this.title,
    required this.kind,
    required this.primaryUrl,
    required this.inputUrl,
    required this.displayLabel,
    required this.resolverKind,
    required this.tracks,
    required this.fallbacks,
    required this.auth,
    this.mimeType = '',
    this.secondaryAudioUrl,
  });

  factory MediaGraph.fromJson(Map<String, dynamic> json) {
    return MediaGraph(
      runtimeId: (json['runtimeId'] as num?)?.toInt() ?? 0,
      mediaId: '${json['mediaId'] ?? ''}',
      sourceId: '${json['sourceId'] ?? ''}',
      title: '${json['title'] ?? ''}',
      kind: '${json['kind'] ?? ''}',
      primaryUrl: Uri.parse('${json['primaryUrl'] ?? ''}'),
      inputUrl: Uri.parse('${json['inputUrl'] ?? json['primaryUrl'] ?? ''}'),
      displayLabel: '${json['displayLabel'] ?? ''}',
      resolverKind: '${json['resolverKind'] ?? ''}',
      mimeType: '${json['mimeType'] ?? ''}',
      secondaryAudioUrl: _parseOptionalUri(json['secondaryAudioUrl']),
      tracks: (json['tracks'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((item) => MediaTrack.fromJson(Map<String, dynamic>.from(item)))
          .toList(growable: false),
      fallbacks: (json['fallbacks'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((item) => MediaFallback.fromJson(Map<String, dynamic>.from(item)))
          .toList(growable: false),
      auth: MediaAuth.fromJson(json['auth'] as Map<String, dynamic>?),
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
      'inputUrl': inputUrl.toString(),
      'displayLabel': displayLabel,
      'resolverKind': resolverKind,
      'mimeType': mimeType,
      'secondaryAudioUrl': secondaryAudioUrl?.toString(),
      'tracks': tracks.map((item) => item.toJson()).toList(growable: false),
      'fallbacks': fallbacks.map((item) => item.toJson()).toList(growable: false),
      'auth': auth.toJson(),
    };
  }
}

Uri? _parseOptionalUri(Object? value) {
  final text = '$value'.trim();
  if (text.isEmpty || text == 'null') {
    return null;
  }
  return Uri.tryParse(text);
}
