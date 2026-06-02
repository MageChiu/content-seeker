import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/content/content.dart';
import '../../features/settings/settings_provider.dart';

const _legacyPlayUrlKey = 'legacy.playUrl';

class RealReadingSourceHub
    implements ContentSearchPort, ContentDetailPort, ContentOpenPort {
  static const _devToSource = ContentSourceRef(
    sourceId: 'devto-articles',
    adapterId: 'devto-article-search',
    displayName: 'DEV Community',
    capabilities: {
      ContentCapability.search,
      ContentCapability.detail,
      ContentCapability.open,
      ContentCapability.save,
    },
  );

  static const _gutendexSource = ContentSourceRef(
    sourceId: 'gutendex-books',
    adapterId: 'gutendex-book-search',
    displayName: 'Project Gutenberg',
    capabilities: {
      ContentCapability.search,
      ContentCapability.detail,
      ContentCapability.open,
      ContentCapability.save,
      ContentCapability.download,
    },
  );

  static const _neteaseNovelSource = ContentSourceRef(
    sourceId: 'netease-yunyuedu-books',
    adapterId: 'netease-yunyuedu-book-search',
    displayName: '网易云阅读',
    capabilities: {
      ContentCapability.search,
      ContentCapability.detail,
      ContentCapability.open,
      ContentCapability.save,
    },
  );

  static const _qidianNovelSource = ContentSourceRef(
    sourceId: 'qidian-books',
    adapterId: 'qidian-book-search',
    displayName: '起点中文网',
    capabilities: {
      ContentCapability.search,
      ContentCapability.detail,
      ContentCapability.open,
      ContentCapability.save,
    },
  );

  static const _fanqieNovelSource = ContentSourceRef(
    sourceId: 'fanqie-books',
    adapterId: 'fanqie-book-search',
    displayName: '番茄小说',
    capabilities: {
      ContentCapability.search,
      ContentCapability.detail,
      ContentCapability.open,
      ContentCapability.save,
    },
  );

  static const _rssFeedSource = ContentSourceRef(
    sourceId: 'configured-rss-feed',
    adapterId: 'configured-rss-feed',
    displayName: 'RSS Feed',
    capabilities: {
      ContentCapability.detail,
      ContentCapability.open,
      ContentCapability.save,
      ContentCapability.subscribe,
    },
  );

  static const _rssItemSource = ContentSourceRef(
    sourceId: 'configured-rss-item',
    adapterId: 'configured-rss-item-search',
    displayName: 'RSS Item',
    capabilities: {
      ContentCapability.search,
      ContentCapability.detail,
      ContentCapability.open,
      ContentCapability.save,
    },
  );

  static const _neteaseRequestHeaders = <String, String>{
    'Accept': 'application/json, text/plain, */*',
    'Referer': 'https://m.yuedu.163.com/',
    'User-Agent':
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36',
  };

  static const _browserRequestHeaders = <String, String>{
    'Accept':
        'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,'
            'image/webp,*/*;q=0.8',
    'User-Agent':
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36',
  };

  static const _jsonRequestHeaders = <String, String>{
    'Accept': 'application/json, text/plain, */*',
    'User-Agent':
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36',
  };

  static const _fallbackRssFeeds = [
    RssFeedConfig(
      id: 'feed.devto.flutter',
      title: 'DEV.to Flutter Feed',
      url: 'https://dev.to/feed/tag/flutter',
      subtitle: '实时 Flutter 文章 RSS',
    ),
    RssFeedConfig(
      id: 'feed.devto.dart',
      title: 'DEV.to Dart Feed',
      url: 'https://dev.to/feed/tag/dart',
      subtitle: '实时 Dart 文章 RSS',
    ),
    RssFeedConfig(
      id: 'feed.google.flutter',
      title: 'Google News Flutter RSS',
      url:
          'https://news.google.com/rss/search?q=flutter&hl=zh-CN&gl=CN&ceid=CN:zh-Hans',
      subtitle: 'Flutter 新闻聚合',
    ),
  ];

  final http.Client httpClient;
  final Map<String, ContentDetail> _detailCache = {};
  SettingsProvider? _settingsProvider;

  RealReadingSourceHub({
    http.Client? httpClient,
    SettingsProvider? settingsProvider,
  })  : httpClient = httpClient ?? http.Client(),
        _settingsProvider = settingsProvider;

  void attachSettings(SettingsProvider settingsProvider) {
    _settingsProvider = settingsProvider;
  }

  List<ContentEntity> featuredItemsSnapshot() {
    return _rssFeeds
        .map(
          (feed) => ContentEntity(
            handle: ContentHandle(
              id: feed.id,
              canonicalId: feed.url,
              type: ContentType.rss,
              source: _rssFeedSource,
            ),
            title: feed.title,
            subtitle: feed.subtitle,
            summary: feed.subtitle.isNotEmpty ? feed.subtitle : feed.url,
            readerKind: ContentReaderKind.rss,
            canonicalUri: Uri.tryParse(feed.url),
            capabilities: const {
              ContentCapability.detail,
              ContentCapability.open,
              ContentCapability.save,
              ContentCapability.subscribe,
            },
            metadata: {
              'feedId': feed.id,
              'feedUrl': feed.url,
            },
            tags: const ['RSS'],
          ),
        )
        .toList(growable: false);
  }

  List<ContentEntity> get featuredEntities => featuredItemsSnapshot();

  @override
  Future<CursorPage<ContentSearchResult>> search(
    ContentSearchRequest request,
  ) async {
    if (request.query.trim().isEmpty) {
      return const CursorPage(items: []);
    }

    if (request.types.isNotEmpty &&
        !request.types.any(_supportsRequestedType)) {
      return const CursorPage(items: []);
    }

    final futures = <Future<List<ContentSearchResult>>>[
      if (_shouldSearchArticles(request.types)) _searchDevTo(request),
      if (_shouldSearchRss(request.types)) _searchConfiguredRssFeeds(request),
      if (_shouldSearchNovels(request.types)) _searchGutendex(request),
      if (_shouldSearchNovels(request.types)) _searchNeteaseNovels(request),
      if (_shouldSearchNovels(request.types)) _searchQidianNovels(request),
      if (_shouldSearchNovels(request.types)) _searchFanqieNovels(request),
    ];

    final pages = await Future.wait(futures);
    final merged = pages.expand((page) => page).toList(growable: true)
      ..sort((left, right) => right.score.compareTo(left.score));

    return CursorPage(
      items: merged.take(request.limit).toList(growable: false),
      hasMore: merged.length > request.limit,
      nextCursor: merged.length > request.limit ? '${request.limit}' : '',
    );
  }

  @override
  Future<ContentDetail> getDetail(ContentDetailRequest request) async {
    final cached = _detailCache[request.handle.stableId];
    if (cached != null) {
      return cached;
    }

    switch (request.handle.source.sourceId) {
      case 'devto-articles':
        return _getDevToDetail(request.handle);
      case 'gutendex-books':
        return _getGutendexDetail(request.handle);
      case 'netease-yunyuedu-books':
        return _getNeteaseNovelDetail(request.handle);
      case 'qidian-books':
        return _getQidianNovelDetail(request.handle);
      case 'fanqie-books':
        return _getFanqieNovelDetail(request.handle);
      case 'configured-rss-feed':
        return _getConfiguredFeedDetail(request.handle);
      case 'configured-rss-item':
        return _getConfiguredFeedItemDetail(request.handle);
      default:
        throw StateError('未识别的阅读内容源: ${request.handle.source.sourceId}');
    }
  }

  @override
  Future<ContentOpenTarget> resolveOpenTarget(ContentOpenRequest request) async {
    final detail = await getDetail(ContentDetailRequest(handle: request.handle));
    final target =
        detail.entity.canonicalUri ?? Uri.parse('https://www.gutenberg.org/');
    return ContentOpenTarget(
      handle: request.handle,
      mode: request.preferredMode,
      target: target,
      extras: {
        'readerKind': detail.entity.readerKind.name,
        'adapterId': detail.entity.handle.source.adapterId,
      },
    );
  }

  Future<List<ContentSearchResult>> _searchDevTo(
    ContentSearchRequest request,
  ) async {
    final uri = Uri.https(
      'dev.to',
      '/api/articles',
      {
        'page': '1',
        'per_page': '${request.limit}',
        'search': request.query.trim(),
        'state': 'all',
      },
    );

    try {
      final response = await httpClient.get(uri);
      if (response.statusCode >= 400) {
        return const [];
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! List) {
        return const [];
      }
      final items = decoded
          .whereType<Map>()
          .map((item) => _parseDevToSearchItem(Map<String, dynamic>.from(item)))
          .toList(growable: false);
      for (final item in items) {
        _detailCache[item.entity.handle.stableId] = ContentDetail(
          entity: item.entity,
          description: item.entity.summary,
          sections: const {},
        );
      }
      return items;
    } catch (_) {
      return const [];
    }
  }

  Future<List<ContentSearchResult>> _searchConfiguredRssFeeds(
    ContentSearchRequest request,
  ) async {
    final futures = _rssFeeds.map((feed) => _searchSingleRssFeed(feed, request));
    final pages = await Future.wait(futures);
    return pages.expand((items) => items).toList(growable: false);
  }

  Future<List<ContentSearchResult>> _searchSingleRssFeed(
    RssFeedConfig feed,
    ContentSearchRequest request,
  ) async {
    final uri = Uri.tryParse(feed.url);
    if (uri == null) {
      return const [];
    }
    try {
      final response = await httpClient.get(uri);
      if (response.statusCode >= 400) {
        return const [];
      }
      final parsed = _parseRssFeed(response.body);
      return parsed.items
          .where(
            (item) => _matchesQuery(
              request.query,
              '${item.title}\n${item.summary}\n${feed.title}',
            ),
          )
          .take(request.limit)
          .map((item) => _toConfiguredFeedSearchResult(feed, item))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<List<ContentSearchResult>> _searchGutendex(
    ContentSearchRequest request,
  ) async {
    final uri = Uri.https(
      'gutendex.com',
      '/books',
      {'search': request.query.trim()},
    );
    try {
      final response = await httpClient.get(uri);
      if (response.statusCode >= 400) {
        return const [];
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        return const [];
      }
      final results = (decoded['results'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => _parseGutendexSearchItem(Map<String, dynamic>.from(item)))
          .take(request.limit)
          .toList(growable: false);
      return results;
    } catch (_) {
      return const [];
    }
  }

  Future<List<ContentSearchResult>> _searchNeteaseNovels(
    ContentSearchRequest request,
  ) async {
    final uri = Uri.https(
      'apis.netstart.cn',
      '/yunyuedu/source/v2/searchBook.json',
      {'query': request.query.trim()},
    );
    try {
      final response = await httpClient.get(uri, headers: _neteaseRequestHeaders);
      if (response.statusCode >= 400) {
        return const [];
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        return const [];
      }
      final items = (decoded['list'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => _parseNeteaseNovelSearchItem(Map<String, dynamic>.from(item), request.query))
          .take(request.limit)
          .toList(growable: false);
      for (final item in items) {
        _detailCache[item.entity.handle.stableId] = ContentDetail(
          entity: item.entity,
          description: item.entity.summary,
          sections: {
            'paragraphs': [item.entity.summary],
          },
        );
      }
      return items;
    } catch (_) {
      return const [];
    }
  }

  Future<List<ContentSearchResult>> _searchQidianNovels(
    ContentSearchRequest request,
  ) async {
    final uri = Uri.https(
      'daosearch.io',
      '/api/v1/search',
      {'q': request.query.trim()},
    );
    try {
      final response = await httpClient.get(uri, headers: _jsonRequestHeaders);
      if (response.statusCode >= 400) {
        return const [];
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        return const [];
      }
      final items = (decoded['data'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (item) => _parseQidianSearchItem(
              Map<String, dynamic>.from(item),
              request.query,
            ),
          )
          .take(request.limit)
          .toList(growable: false);
      return items;
    } catch (_) {
      return const [];
    }
  }

  Future<List<ContentSearchResult>> _searchFanqieNovels(
    ContentSearchRequest request,
  ) async {
    final uri = Uri.http(
      '101.35.133.34:5000',
      '/api/search',
      {
        'key': request.query.trim(),
        'tab_type': '3',
        'offset': '0',
      },
    );
    try {
      final response = await httpClient.get(uri, headers: _jsonRequestHeaders);
      if (response.statusCode >= 400) {
        return const [];
      }
      final decoded = jsonDecode(response.body);
      final items = _extractFanqieSearchBooks(decoded)
          .map(
            (item) => _parseFanqieSearchItem(
              item,
              request.query,
            ),
          )
          .take(request.limit)
          .toList(growable: false);
      return items;
    } catch (_) {
      return const [];
    }
  }

  Future<ContentDetail> _getDevToDetail(ContentHandle handle) async {
    final articleId = handle.id.trim();
    final uri = Uri.https('dev.to', '/api/articles/$articleId');
    final response = await httpClient.get(uri);
    if (response.statusCode >= 400) {
      throw StateError('无法加载文章详情: HTTP ${response.statusCode}');
    }
    final json = jsonDecode(response.body);
    if (json is! Map) {
      throw StateError('文章详情格式错误');
    }
    final detail = _parseDevToDetail(Map<String, dynamic>.from(json));
    _detailCache[handle.stableId] = detail;
    return detail;
  }

  Future<ContentDetail> _getGutendexDetail(ContentHandle handle) async {
    final uri = Uri.https('gutendex.com', '/books', {'ids': handle.id});
    final response = await httpClient.get(uri);
    if (response.statusCode >= 400) {
      throw StateError('无法加载小说详情: HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw StateError('小说详情格式错误');
    }
    final results = (decoded['results'] as List? ?? const []).whereType<Map>();
    if (results.isEmpty) {
      throw StateError('未找到小说详情: ${handle.id}');
    }
    final json = Map<String, dynamic>.from(results.first);
    final entity = _parseGutendexSearchItem(json).entity;
    final textUrl = _pickGutendexTextUrl(json);
    final paragraphs = textUrl == null ? const <String>[] : await _loadTextBody(textUrl);
    final detail = ContentDetail(
      entity: entity,
      description: entity.summary,
      sections: {
        'paragraphs': paragraphs,
        'subjects': (json['subjects'] as List? ?? const [])
            .map((item) => '$item')
            .toList(growable: false),
      },
    );
    _detailCache[handle.stableId] = detail;
    return detail;
  }

  Future<ContentDetail> _getConfiguredFeedDetail(ContentHandle handle) async {
    final feed = _rssFeeds.firstWhere(
      (item) => item.id == handle.id,
      orElse: () => throw StateError('未找到 RSS feed: ${handle.id}'),
    );
    final uri = Uri.tryParse(feed.url);
    if (uri == null) {
      throw StateError('RSS feed 地址无效: ${feed.url}');
    }
    final response = await httpClient.get(uri);
    if (response.statusCode >= 400) {
      throw StateError('无法加载 RSS feed: HTTP ${response.statusCode}');
    }
    final parsed = _parseRssFeed(response.body);
    final entity = featuredItemsSnapshot().firstWhere(
      (item) => item.handle.id == feed.id,
      orElse: () => throw StateError('未找到 RSS 配置: ${feed.id}'),
    );
    final detail = ContentDetail(
      entity: entity,
      description: parsed.title.isNotEmpty ? parsed.title : entity.summary,
      sections: {
        'feedItems': parsed.items
            .take(20)
            .map(
              (item) => <String, String>{
                'title': item.title,
                'summary': item.summary,
                'publishedAt': item.publishedAt,
              },
            )
            .toList(growable: false),
      },
    );
    _detailCache[handle.stableId] = detail;
    return detail;
  }

  Future<ContentDetail> _getNeteaseNovelDetail(ContentHandle handle) async {
    final cached = _detailCache[handle.stableId];
    if (cached != null) {
      return cached;
    }
    final entity = ContentEntity(
      handle: handle,
      title: handle.id,
      summary: '',
      readerKind: ContentReaderKind.novel,
      canonicalUri: Uri.tryParse(handle.canonicalId),
      capabilities: const {
        ContentCapability.detail,
        ContentCapability.open,
        ContentCapability.save,
      },
    );
    final detail = ContentDetail(
      entity: entity,
      description: '该内容来自网易云阅读搜索结果，当前先展示摘要并支持打开原站继续阅读。',
      sections: const {},
    );
    _detailCache[handle.stableId] = detail;
    return detail;
  }

  Future<ContentDetail> _getQidianNovelDetail(ContentHandle handle) async {
    final detailUri = Uri.https('daosearch.io', '/api/v1/books/${handle.id}');
    final chapterUri = Uri.https(
      'daosearch.io',
      '/api/v1/books/${handle.id}/chapters',
    );
    final detailResponse = await httpClient.get(
      detailUri,
      headers: _jsonRequestHeaders,
    );
    if (detailResponse.statusCode >= 400) {
      throw StateError('无法加载起点小说详情: HTTP ${detailResponse.statusCode}');
    }
    final chapterResponse = await httpClient.get(
      chapterUri,
      headers: _jsonRequestHeaders,
    );
    if (chapterResponse.statusCode >= 400) {
      throw StateError('无法加载起点章节目录: HTTP ${chapterResponse.statusCode}');
    }

    final detailJson = jsonDecode(detailResponse.body);
    final chapterJson = jsonDecode(chapterResponse.body);
    if (detailJson is! Map || chapterJson is! Map) {
      throw StateError('起点小说详情格式错误');
    }

    final detailData = Map<String, dynamic>.from(
      detailJson['data'] as Map? ?? const {},
    );
    final chapters = (chapterJson['data'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);

    final entity = ContentEntity(
      handle: handle,
      title: '${detailData['title'] ?? handle.id}'.trim(),
      subtitle: '${detailData['author'] ?? _qidianNovelSource.displayName}'.trim(),
      summary: '${detailData['synopsis'] ?? ''}'.trim(),
      readerKind: ContentReaderKind.novel,
      coverUri: Uri.tryParse('${detailData['imageUrl'] ?? ''}'.trim()),
      canonicalUri: Uri.tryParse('${detailData['url'] ?? handle.canonicalId}'.trim()),
      capabilities: const {
        ContentCapability.detail,
        ContentCapability.open,
        ContentCapability.save,
      },
      metadata: {
        'author': '${detailData['author'] ?? ''}'.trim(),
        'genre': '${detailData['genreName'] ?? ''}'.trim(),
        'wordCount': detailData['wordCount'],
        'qidianId': detailData['qidianId'],
      },
      tags: [
        if ('${detailData['genreName'] ?? ''}'.trim().isNotEmpty)
          '${detailData['genreName']}'.trim(),
        if ('${detailData['status'] ?? ''}'.trim().isNotEmpty)
          '${detailData['status']}'.trim(),
      ],
    );
    final chapterSections = await _loadQidianChapterSections(chapters);
    final detail = ContentDetail(
      entity: entity,
      description: entity.summary,
      sections: {
        'chapters': chapterSections,
      },
    );
    _detailCache[handle.stableId] = detail;
    return detail;
  }

  Future<ContentDetail> _getFanqieNovelDetail(ContentHandle handle) async {
    final detailUri = Uri.http(
      '101.35.133.34:5000',
      '/api/detail',
      {'book_id': handle.id},
    );
    final directoryUri = Uri.http(
      '101.35.133.34:5000',
      '/api/directory',
      {'book_id': handle.id},
    );
    final detailResponse = await httpClient.get(
      detailUri,
      headers: _jsonRequestHeaders,
    );
    if (detailResponse.statusCode >= 400) {
      throw StateError('无法加载番茄小说详情: HTTP ${detailResponse.statusCode}');
    }
    final directoryResponse = await httpClient.get(
      directoryUri,
      headers: _jsonRequestHeaders,
    );
    if (directoryResponse.statusCode >= 400) {
      throw StateError('无法加载番茄章节目录: HTTP ${directoryResponse.statusCode}');
    }

    final detailJson = jsonDecode(detailResponse.body);
    final directoryJson = jsonDecode(directoryResponse.body);
    if (detailJson is! Map || directoryJson is! Map) {
      throw StateError('番茄小说详情格式错误');
    }

    final detailData = Map<String, dynamic>.from(
      (detailJson['data'] as Map?)?['data'] as Map? ?? const {},
    );
    final directoryItems = ((directoryJson['data'] as Map?)?['lists'] as List? ??
            const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);

    final entity = ContentEntity(
      handle: handle,
      title: '${detailData['book_name'] ?? handle.id}'.trim(),
      subtitle: '${detailData['author'] ?? _fanqieNovelSource.displayName}'.trim(),
      summary: '${detailData['abstract'] ?? detailData['content'] ?? ''}'.trim(),
      readerKind: ContentReaderKind.novel,
      coverUri: Uri.tryParse('${detailData['thumb_url'] ?? ''}'.trim()),
      canonicalUri: Uri.tryParse('https://www.fqnovel.com/page/${handle.id}'),
      capabilities: const {
        ContentCapability.detail,
        ContentCapability.open,
        ContentCapability.save,
      },
      metadata: {
        'author': '${detailData['author'] ?? ''}'.trim(),
        'category': '${detailData['category'] ?? ''}'.trim(),
        'wordCount': '${detailData['word_number'] ?? ''}'.trim(),
        'score': '${detailData['score'] ?? ''}'.trim(),
      },
      tags: _fanqieTags(detailData),
    );
    final chapterSections = await _loadFanqieChapterSections(
      bookId: handle.id,
      chapters: directoryItems,
    );
    final detail = ContentDetail(
      entity: entity,
      description: entity.summary,
      sections: {
        'chapters': chapterSections,
      },
    );
    _detailCache[handle.stableId] = detail;
    return detail;
  }

  Future<ContentDetail> _getConfiguredFeedItemDetail(ContentHandle handle) async {
    final cached = _detailCache[handle.stableId];
    if (cached != null) {
      return cached;
    }
    final uri = Uri.tryParse(handle.canonicalId);
    if (uri == null) {
      throw StateError('当前 RSS 条目缺少原文地址');
    }
    final entity = ContentEntity(
      handle: handle,
      title: handle.id,
      summary: '',
      readerKind: ContentReaderKind.rss,
      canonicalUri: uri,
      capabilities: const {
        ContentCapability.detail,
        ContentCapability.open,
        ContentCapability.save,
      },
    );
    final detail = ContentDetail(
      entity: entity,
      description: '该条目来自 RSS 搜索结果，正文需通过原文链接查看。',
      sections: const {},
    );
    _detailCache[handle.stableId] = detail;
    return detail;
  }

  ContentSearchResult _parseDevToSearchItem(Map<String, dynamic> json) {
    final id = '${json['id'] ?? ''}'.trim();
    final title = '${json['title'] ?? ''}'.trim();
    final description = '${json['description'] ?? ''}'.trim();
    final articleUrl = '${json['url'] ?? ''}'.trim();
    final coverImage = '${json['cover_image'] ?? ''}'.trim();
    final author = json['user'] is Map
        ? '${(json['user'] as Map)['name'] ?? ''}'.trim()
        : '';
    final tags = (json['tag_list'] as List? ?? const [])
        .map((item) => '$item'.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);

    final entity = ContentEntity(
      handle: ContentHandle(
        id: id,
        canonicalId: articleUrl,
        type: ContentType.webArticle,
        source: _devToSource,
      ),
      title: title,
      subtitle: author.isNotEmpty ? author : _devToSource.displayName,
      summary: description,
      readerKind: ContentReaderKind.webArticle,
      coverUri: Uri.tryParse(coverImage),
      canonicalUri: Uri.tryParse(articleUrl),
      publishedAt: DateTime.tryParse('${json['published_at'] ?? ''}'),
      capabilities: const {
        ContentCapability.search,
        ContentCapability.detail,
        ContentCapability.open,
        ContentCapability.save,
      },
      metadata: {'author': author},
      tags: tags,
    );
    return ContentSearchResult(
      entity: entity,
      score: _scoreTextMatch(title: title, summary: description),
      highlights: description.isNotEmpty ? [description] : const [],
    );
  }

  ContentDetail _parseDevToDetail(Map<String, dynamic> json) {
    final entity = _parseDevToSearchItem(json).entity;
    final bodyMarkdown = '${json['body_markdown'] ?? ''}'.trim();
    return ContentDetail(
      entity: entity,
      description: '${json['description'] ?? entity.summary}'.trim(),
      sections: {
        'paragraphs': _extractParagraphs(bodyMarkdown),
        'highlights': entity.tags,
      },
    );
  }

  ContentSearchResult _parseGutendexSearchItem(Map<String, dynamic> json) {
    final id = '${json['id'] ?? ''}'.trim();
    final title = '${json['title'] ?? ''}'.trim();
    final authors = (json['authors'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => '${item['name'] ?? ''}'.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    final subjects = (json['subjects'] as List? ?? const [])
        .map((item) => '$item'.trim())
        .where((item) => item.isNotEmpty)
        .take(4)
        .toList(growable: false);
    final coverUrl = _pickGutendexCoverUrl(json);
    final downloadUrl = _pickGutendexDownloadUrl(json);
    final canonicalUrl = 'https://www.gutenberg.org/ebooks/$id';
    final entity = ContentEntity(
      handle: ContentHandle(
        id: id,
        canonicalId: canonicalUrl,
        type: ContentType.novel,
        source: _gutendexSource,
      ),
      title: title,
      subtitle: authors.isEmpty ? _gutendexSource.displayName : authors.join(' · '),
      summary: subjects.join(' / '),
      readerKind: ContentReaderKind.novel,
      coverUri: coverUrl == null ? null : Uri.tryParse(coverUrl),
      canonicalUri: Uri.tryParse(canonicalUrl),
      capabilities: const {
        ContentCapability.search,
        ContentCapability.detail,
        ContentCapability.open,
        ContentCapability.save,
        ContentCapability.download,
      },
      metadata: {
        'author': authors.join(' · '),
        'subjects': subjects,
        if (downloadUrl != null) _legacyPlayUrlKey: downloadUrl,
      },
      tags: subjects,
    );
    return ContentSearchResult(
      entity: entity,
      score: _scoreTextMatch(title: title, summary: subjects.join(' ')) + 20,
      highlights: subjects,
    );
  }

  ContentSearchResult _parseNeteaseNovelSearchItem(
    Map<String, dynamic> json,
    String query,
  ) {
    final sourceUuid = '${json['sourceUuid'] ?? json['source_uuid'] ?? json['id'] ?? ''}'.trim();
    final id = '${json['id'] ?? sourceUuid}'.trim();
    final title = '${json['title'] ?? ''}'.trim();
    final author = '${json['author'] ?? ''}'.trim();
    final summary = '${json['content'] ?? json['recomContent'] ?? ''}'.trim();
    final cover = '${json['cover'] ?? ''}'.trim();
    final category = '${json['category'] ?? ''}'.trim();
    final extra = '${json['extra'] ?? ''}'.trim();
    final canonicalUrl = sourceUuid.isEmpty
        ? ''
        : 'https://m.yuedu.163.com/source/$sourceUuid';
    final entity = ContentEntity(
      handle: ContentHandle(
        id: id,
        canonicalId: canonicalUrl,
        type: ContentType.novel,
        source: _neteaseNovelSource,
      ),
      title: title,
      subtitle: author.isEmpty ? _neteaseNovelSource.displayName : author,
      summary: summary,
      readerKind: ContentReaderKind.novel,
      coverUri: Uri.tryParse(cover),
      canonicalUri: canonicalUrl.isEmpty ? null : Uri.tryParse(canonicalUrl),
      capabilities: const {
        ContentCapability.search,
        ContentCapability.detail,
        ContentCapability.open,
        ContentCapability.save,
      },
      metadata: {
        'author': author,
        'category': category,
        'wordCountLabel': extra,
        'sourceUuid': sourceUuid,
      },
      tags: [
        if (category.isNotEmpty) category,
        if (extra.isNotEmpty) extra,
      ],
    );
    final chineseBoost = RegExp(r'[\u4e00-\u9fff]').hasMatch(query) ? 40 : 0;
    return ContentSearchResult(
      entity: entity,
      score: _scoreTextMatch(title: title, summary: summary) + chineseBoost,
      highlights: [
        if (summary.isNotEmpty) summary,
        if (category.isNotEmpty) category,
      ],
    );
  }

  ContentSearchResult _parseQidianSearchItem(
    Map<String, dynamic> json,
    String query,
  ) {
    final id = '${json['id'] ?? ''}'.trim();
    final title = '${json['title'] ?? ''}'.trim();
    final author = '${json['author'] ?? ''}'.trim();
    final genre = '${json['genreName'] ?? ''}'.trim();
    final imageUrl = '${json['imageUrl'] ?? ''}'.trim();
    final canonicalUrl = 'https://daosearch.io/book/$id';
    final chineseBoost = RegExp(r'[\u4e00-\u9fff]').hasMatch(query) ? 40 : 0;
    final entity = ContentEntity(
      handle: ContentHandle(
        id: id,
        canonicalId: canonicalUrl,
        type: ContentType.novel,
        source: _qidianNovelSource,
      ),
      title: title,
      subtitle: author.isEmpty ? _qidianNovelSource.displayName : author,
      summary: genre,
      readerKind: ContentReaderKind.novel,
      coverUri: Uri.tryParse(imageUrl),
      canonicalUri: Uri.tryParse(canonicalUrl),
      capabilities: const {
        ContentCapability.search,
        ContentCapability.detail,
        ContentCapability.open,
        ContentCapability.save,
      },
      metadata: {
        'author': author,
        'genre': genre,
      },
      tags: [
        if (genre.isNotEmpty) genre,
      ],
    );
    return ContentSearchResult(
      entity: entity,
      score: _scoreTextMatch(title: title, summary: genre) + chineseBoost,
      highlights: [
        if (genre.isNotEmpty) genre,
      ],
    );
  }

  ContentSearchResult _parseFanqieSearchItem(
    Map<String, dynamic> json,
    String query,
  ) {
    final bookId = '${json['book_id'] ?? ''}'.trim();
    final title = '${json['book_name'] ?? json['title'] ?? ''}'.trim();
    final author = '${json['author'] ?? ''}'.trim();
    final summary = '${json['abstract'] ?? json['content'] ?? ''}'.trim();
    final cover = '${json['thumb_url'] ?? json['thumb_uri'] ?? ''}'.trim();
    final category = '${json['category'] ?? ''}'.trim();
    final canonicalUrl = 'https://www.fqnovel.com/page/$bookId';
    final chineseBoost = RegExp(r'[\u4e00-\u9fff]').hasMatch(query) ? 40 : 0;
    final entity = ContentEntity(
      handle: ContentHandle(
        id: bookId,
        canonicalId: canonicalUrl,
        type: ContentType.novel,
        source: _fanqieNovelSource,
      ),
      title: title,
      subtitle: author.isEmpty ? _fanqieNovelSource.displayName : author,
      summary: summary,
      readerKind: ContentReaderKind.novel,
      coverUri: Uri.tryParse(cover),
      canonicalUri: Uri.tryParse(canonicalUrl),
      capabilities: const {
        ContentCapability.search,
        ContentCapability.detail,
        ContentCapability.open,
        ContentCapability.save,
      },
      metadata: {
        'author': author,
        'category': category,
        'wordCount': '${json['word_number'] ?? ''}'.trim(),
      },
      tags: [
        if (category.isNotEmpty) category,
      ],
    );
    return ContentSearchResult(
      entity: entity,
      score: _scoreTextMatch(title: title, summary: summary) + chineseBoost,
      highlights: [
        if (summary.isNotEmpty) summary,
        if (category.isNotEmpty) category,
      ],
    );
  }

  ContentSearchResult _toConfiguredFeedSearchResult(
    RssFeedConfig feed,
    _ParsedRssItem item,
  ) {
    final entity = ContentEntity(
      handle: ContentHandle(
        id: item.title,
        canonicalId: item.link,
        type: ContentType.rss,
        source: _rssItemSource,
      ),
      title: item.title,
      subtitle: feed.title,
      summary: item.summary,
      readerKind: ContentReaderKind.rss,
      canonicalUri: Uri.tryParse(item.link),
      publishedAt: DateTime.tryParse(item.publishedAt),
      capabilities: const {
        ContentCapability.search,
        ContentCapability.detail,
        ContentCapability.open,
        ContentCapability.save,
      },
      metadata: {
        'author': feed.title,
        'feedId': feed.id,
        'feedUrl': feed.url,
      },
      tags: const ['RSS'],
    );
    final detail = ContentDetail(
      entity: entity,
      description: item.summary,
      sections: {
        'feedItems': [
          {
            'title': item.title,
            'summary': item.summary,
            'publishedAt': item.publishedAt,
          },
        ],
      },
    );
    _detailCache[entity.handle.stableId] = detail;
    return ContentSearchResult(
      entity: entity,
      score: _scoreTextMatch(title: item.title, summary: item.summary),
      highlights: item.summary.isNotEmpty ? [item.summary] : const [],
    );
  }

  Future<List<String>> _loadTextBody(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return const [];
    }
    final response = await httpClient.get(uri);
    if (response.statusCode >= 400) {
      return const [];
    }
    final contentType = response.headers['content-type'] ?? '';
    final raw = response.body;
    final normalized = contentType.contains('html') ? _stripHtml(raw) : raw;
    return normalized
        .split(RegExp(r'\n\s*\n'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .take(40)
        .toList(growable: false);
  }

  List<String> _extractParagraphs(String markdown) {
    return markdown
        .split(RegExp(r'\n\s*\n'))
        .map((item) => item.replaceAll(RegExp(r'[#>*`_\-\[\]]'), '').trim())
        .where((item) => item.isNotEmpty)
        .take(20)
        .toList(growable: false);
  }

  List<String> _splitPlainTextParagraphs(String raw) {
    return raw
        .replaceAll('\r', '')
        .split(RegExp(r'\n+'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .take(40)
        .toList(growable: false);
  }

  List<String> _extractHtmlParagraphsFromContainer(
    String html, {
    required String containerId,
  }) {
    final containerPattern = RegExp(
      '<div\\b[^>]*id=["\']$containerId["\'][^>]*>([\\s\\S]*?)</div>',
      caseSensitive: false,
      multiLine: true,
    );
    final containerMatch = containerPattern.firstMatch(html);
    final source = containerMatch?.group(1) ?? html;
    final matches = RegExp(
      r'<p\b[^>]*>([\s\S]*?)</p>',
      caseSensitive: false,
      multiLine: true,
    ).allMatches(source);
    return matches
        .map((match) => _stripHtml(_decodeHtml(match.group(1) ?? '')).trim())
        .where((item) => item.isNotEmpty)
        .take(40)
        .toList(growable: false);
  }

  _ParsedRssFeed _parseRssFeed(String xml) {
    final normalized = xml.replaceAll('\r', '');
    final title = _decodeHtml(_extractFirstTag(normalized, 'title'));
    final itemBlocks = RegExp(r'<item\b[^>]*>([\s\S]*?)</item>', multiLine: true)
        .allMatches(normalized)
        .map((match) => match.group(1) ?? '')
        .toList(growable: false);
    final items = itemBlocks.map((block) {
      final sourceMatch = RegExp(
        r'<source\b[^>]*>([\s\S]*?)</source>',
        multiLine: true,
      ).firstMatch(block);
      return _ParsedRssItem(
        title: _decodeHtml(_extractFirstTag(block, 'title')),
        link: _decodeHtml(_extractFirstTag(block, 'link')),
        summary: _stripHtml(_decodeHtml(_extractFirstTag(block, 'description'))),
        publishedAt: _decodeHtml(_extractFirstTag(block, 'pubDate')),
        source: _stripHtml(_decodeHtml(sourceMatch?.group(1) ?? '')),
      );
    }).where((item) => item.title.isNotEmpty).toList(growable: false);

    return _ParsedRssFeed(title: title, items: items);
  }

  List<Map<String, dynamic>> _extractFanqieSearchBooks(dynamic root) {
    final results = <Map<String, dynamic>>[];
    final seen = <String>{};

    void walk(dynamic node) {
      if (node is Map) {
        final map = Map<String, dynamic>.from(node);
        final bookId = '${map['book_id'] ?? ''}'.trim();
        final title = '${map['book_name'] ?? map['title'] ?? ''}'.trim();
        if (bookId.isNotEmpty && title.isNotEmpty && seen.add(bookId)) {
          results.add(map);
        }
        for (final value in map.values) {
          walk(value);
        }
        return;
      }
      if (node is List) {
        for (final item in node) {
          walk(item);
        }
      }
    }

    walk(root);
    return results;
  }

  List<String> _fanqieTags(Map<String, dynamic> detailData) {
    final category = '${detailData['category'] ?? ''}'.trim();
    final tags = '${detailData['tags'] ?? ''}'
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty);
    return <String>[
      if (category.isNotEmpty) category,
      ...tags.take(5),
    ];
  }

  List<RssFeedConfig> get _rssFeeds {
    final feeds = _settingsProvider?.enabledRssFeeds ?? _fallbackRssFeeds;
    return feeds.where((item) => item.url.trim().isNotEmpty).toList(growable: false);
  }

  bool _supportsRequestedType(ContentType type) {
    switch (type) {
      case ContentType.webArticle:
      case ContentType.rss:
      case ContentType.novel:
        return true;
      default:
        return false;
    }
  }

  Future<List<Map<String, Object?>>> _loadQidianChapterSections(
    List<Map<String, dynamic>> chapters,
  ) async {
    final previewChapters = chapters.take(8).toList(growable: false);
    final chaptersWithContent = previewChapters.take(3).toList(growable: false);
    final loaded = await Future.wait(
      chaptersWithContent.map((chapter) async {
        final chapterId = '${chapter['id'] ?? ''}'.trim();
        final chapterUrl = '${chapter['url'] ?? ''}'.trim();
        final paragraphs = chapterUrl.isEmpty
            ? const <String>[]
            : await _loadQidianChapterParagraphs(chapterUrl);
        return MapEntry(chapterId, paragraphs);
      }),
    );
    final paragraphsById = <String, List<String>>{
      for (final item in loaded) item.key: item.value,
    };
    return previewChapters
        .map(
          (chapter) => <String, Object?>{
            'id': '${chapter['id'] ?? ''}'.trim(),
            'title':
                '${chapter['title'] ?? chapter['titleTranslated'] ?? ''}'.trim(),
            'paragraphs':
                paragraphsById['${chapter['id'] ?? ''}'.trim()] ??
                    const <String>[],
          },
        )
        .toList(growable: false);
  }

  Future<List<Map<String, Object?>>> _loadFanqieChapterSections({
    required String bookId,
    required List<Map<String, dynamic>> chapters,
  }) async {
    final previewChapters = chapters.take(8).toList(growable: false);
    final preloadIds = previewChapters
        .take(3)
        .map((item) => '${item['item_id'] ?? ''}'.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    final paragraphsById = <String, List<String>>{};
    if (preloadIds.isNotEmpty) {
      final batchUri = Uri.http(
        '101.35.133.34:5000',
        '/api/content',
        {
          'tab': '批量',
          'item_ids': preloadIds.join(','),
          'book_id': bookId,
        },
      );
      try {
        final response = await httpClient.get(
          batchUri,
          headers: _jsonRequestHeaders,
        );
        if (response.statusCode < 400) {
          final decoded = jsonDecode(response.body);
          if (decoded is Map) {
            final chapterItems =
                ((decoded['data'] as Map?)?['chapters'] as List? ?? const [])
                    .whereType<Map>()
                    .map((item) => Map<String, dynamic>.from(item))
                    .toList(growable: false);
            for (var index = 0;
                index < chapterItems.length && index < preloadIds.length;
                index++) {
              final raw = '${chapterItems[index]['content'] ?? ''}';
              paragraphsById[preloadIds[index]] = _splitPlainTextParagraphs(raw);
            }
          }
        }
      } catch (_) {
        // Keep directory-only fallback when content loading fails.
      }
    }

    return previewChapters
        .map(
          (chapter) => <String, Object?>{
            'id': '${chapter['item_id'] ?? ''}'.trim(),
            'title': '${chapter['title'] ?? ''}'.trim(),
            'paragraphs':
                paragraphsById['${chapter['item_id'] ?? ''}'.trim()] ??
                    const <String>[],
          },
        )
        .toList(growable: false);
  }

  Future<List<String>> _loadQidianChapterParagraphs(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return const [];
    }
    try {
      final response = await httpClient.get(
        uri,
        headers: _browserRequestHeaders,
      );
      if (response.statusCode >= 400) {
        return const [];
      }
      return _extractHtmlParagraphsFromContainer(
        response.body,
        containerId: 'article',
      );
    } catch (_) {
      return const [];
    }
  }

  bool _shouldSearchArticles(Set<ContentType> requestedTypes) {
    return requestedTypes.isEmpty || requestedTypes.contains(ContentType.webArticle);
  }

  bool _shouldSearchRss(Set<ContentType> requestedTypes) {
    return requestedTypes.isEmpty || requestedTypes.contains(ContentType.rss);
  }

  bool _shouldSearchNovels(Set<ContentType> requestedTypes) {
    return requestedTypes.isEmpty || requestedTypes.contains(ContentType.novel);
  }

  bool _matchesQuery(String query, String haystack) {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) {
      return true;
    }
    return haystack.toLowerCase().contains(normalizedQuery);
  }

  double _scoreTextMatch({
    required String title,
    required String summary,
  }) {
    var score = 100.0;
    if (title.isNotEmpty) {
      score += 20;
    }
    if (summary.isNotEmpty) {
      score += 10;
    }
    return score;
  }

  String? _pickGutendexCoverUrl(Map<String, dynamic> json) {
    final formats = Map<String, dynamic>.from(json['formats'] as Map? ?? const {});
    return _pickFirstUrl(formats, const ['image/jpeg']);
  }

  String? _pickGutendexDownloadUrl(Map<String, dynamic> json) {
    final formats = Map<String, dynamic>.from(json['formats'] as Map? ?? const {});
    return _pickFirstUrl(
      formats,
      const [
        'text/plain; charset=utf-8',
        'text/plain; charset=us-ascii',
        'text/plain',
        'text/html; charset=utf-8',
        'text/html',
        'application/epub+zip',
      ],
    );
  }

  String? _pickGutendexTextUrl(Map<String, dynamic> json) {
    final formats = Map<String, dynamic>.from(json['formats'] as Map? ?? const {});
    return _pickFirstUrl(
      formats,
      const [
        'text/plain; charset=utf-8',
        'text/plain; charset=us-ascii',
        'text/plain',
        'text/html; charset=utf-8',
        'text/html',
      ],
    );
  }

  String? _pickFirstUrl(
    Map<String, dynamic> formats,
    List<String> candidates,
  ) {
    for (final key in candidates) {
      final value = '${formats[key] ?? ''}'.trim();
      if (value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  String _extractFirstTag(String xml, String tag) {
    final match = RegExp(
      '<$tag\\b[^>]*>([\\s\\S]*?)</$tag>',
      caseSensitive: false,
      multiLine: true,
    ).firstMatch(xml);
    return _stripCdata(match?.group(1)?.trim() ?? '');
  }

  String _stripHtml(String raw) {
    return raw
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _decodeHtml(String raw) {
    return raw
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ');
  }

  String _stripCdata(String raw) {
    return raw.replaceAll('<![CDATA[', '').replaceAll(']]>', '').trim();
  }
}

class _ParsedRssFeed {
  final String title;
  final List<_ParsedRssItem> items;

  const _ParsedRssFeed({
    required this.title,
    required this.items,
  });
}

class _ParsedRssItem {
  final String title;
  final String link;
  final String summary;
  final String publishedAt;
  final String source;

  const _ParsedRssItem({
    required this.title,
    required this.link,
    required this.summary,
    required this.publishedAt,
    required this.source,
  });
}
