import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:content_seeker/core/content/content.dart';
import 'package:content_seeker/features/settings/settings_provider.dart';
import 'package:content_seeker/infra/content/real_reading_source_hub.dart';

void main() {
  group('RealReadingSourceHub', () {
    test('searches DEV.to articles from live content port contract', () async {
      final hub = RealReadingSourceHub(
        httpClient: MockClient((request) async {
          if (request.url.toString().contains('/api/articles')) {
            return http.Response(
              '''
              [
                {
                  "id": 101,
                  "title": "Flutter Search in Practice",
                  "description": "Search cards now include real reading content.",
                  "cover_image": "https://example.com/flutter.png",
                  "url": "https://dev.to/example/flutter-search-in-practice",
                  "published_at": "2026-05-25T08:00:00Z",
                  "reading_time_minutes": 5,
                  "tag_list": ["flutter", "search"],
                  "user": {"name": "Example Author"}
                }
              ]
              ''',
              200,
            );
          }
          return http.Response('[]', 200);
        }),
      );

      final page = await hub.search(
        const ContentSearchRequest(
          query: 'flutter search',
          limit: 10,
        ),
      );

      expect(page.items, hasLength(1));
      final entity = page.items.first.entity;
      expect(entity.handle.type, ContentType.webArticle);
      expect(entity.readerKind, ContentReaderKind.webArticle);
      expect(entity.title, 'Flutter Search in Practice');
      expect(entity.subtitle, 'Example Author');
    });

    test('loads featured rss detail from real feed response', () async {
      final hub = RealReadingSourceHub(
        httpClient: MockClient((request) async {
          return http.Response(
            '''
            <rss version="2.0">
              <channel>
                <title>DEV.to Flutter Feed</title>
                <item>
                  <title>Article One</title>
                  <link>https://dev.to/example/article-one</link>
                  <description><![CDATA[First summary]]></description>
                  <pubDate>Mon, 25 May 2026 08:00:00 GMT</pubDate>
                </item>
                <item>
                  <title>Article Two</title>
                  <link>https://dev.to/example/article-two</link>
                  <description><![CDATA[Second summary]]></description>
                  <pubDate>Mon, 24 May 2026 08:00:00 GMT</pubDate>
                </item>
              </channel>
            </rss>
            ''',
            200,
          );
        }),
      );

      final detail = await hub.getDetail(
        ContentDetailRequest(handle: hub.featuredEntities.first.handle),
      );

      expect(detail.entity.handle.type, ContentType.rss);
      final items =
          (detail.sections['feedItems'] as List<dynamic>).cast<Map<String, String>>();
      expect(items, hasLength(2));
      expect(items.first['title'], 'Article One');
      expect(items.first['summary'], 'First summary');
    });

    test('searches real novel source from gutendex and exposes download capability', () async {
      final hub = RealReadingSourceHub(
        httpClient: MockClient((request) async {
          if (request.url.host == 'gutendex.com') {
            return http.Response(
              '''
              {
                "results": [
                  {
                    "id": 1342,
                    "title": "Pride and Prejudice",
                    "authors": [{"name": "Jane Austen"}],
                    "subjects": ["Love stories", "Social classes"],
                    "formats": {
                      "text/plain; charset=utf-8": "https://example.com/pride.txt",
                      "image/jpeg": "https://example.com/pride.jpg"
                    }
                  }
                ]
              }
              ''',
              200,
            );
          }
          return http.Response('{}', 404);
        }),
      );

      final page = await hub.search(
        const ContentSearchRequest(query: 'pride prejudice', limit: 10),
      );

      expect(page.items, isNotEmpty);
      final novel = page.items.first.entity;
      expect(novel.handle.type, ContentType.novel);
      expect(novel.readerKind, ContentReaderKind.novel);
      expect(novel.supports(ContentCapability.download), isTrue);
      expect(novel.metadata['legacy.playUrl'], 'https://example.com/pride.txt');
    });

    test('builds featured rss feeds from configurable settings list', () {
      final settings = SettingsProvider();
      settings.upsertRssFeed(
        const RssFeedConfig(
          id: 'feed.custom',
          title: 'Custom Feed',
          url: 'https://example.com/feed.xml',
          subtitle: '自定义测试源',
        ),
      );
      final hub = RealReadingSourceHub(settingsProvider: settings);

      final featured = hub.featuredEntities;

      expect(
        featured.any((item) => item.title == 'Custom Feed'),
        isTrue,
      );
    });

    test('searches chinese novel source from netease yunyuedu', () async {
      final hub = RealReadingSourceHub(
        httpClient: MockClient((request) async {
          if (request.url.host == 'apis.netstart.cn') {
            return http.Response.bytes(
              utf8.encode(
                '''
                {
                  "resCode": 0,
                  "list": [
                    {
                      "id": "book_1",
                      "sourceUuid": "book_1_4",
                      "title": "红楼梦",
                      "author": "曹雪芹",
                      "category": "古典名著",
                      "extra": "96万字",
                      "cover": "https://example.com/hongloumeng.jpg",
                      "content": "贾宝玉、林黛玉等人的兴衰故事。"
                    }
                  ]
                }
                ''',
              ),
              200,
              headers: const {'content-type': 'application/json; charset=utf-8'},
            );
          }
          return http.Response('[]', 200);
        }),
      );

      final page = await hub.search(
        const ContentSearchRequest(query: '红楼梦', limit: 10),
      );

      expect(page.items, isNotEmpty);
      final novel = page.items.first.entity;
      expect(novel.handle.type, ContentType.novel);
      expect(novel.title, '红楼梦');
      expect(novel.subtitle, '曹雪芹');
      expect(
        novel.canonicalUri?.toString(),
        'https://m.yuedu.163.com/source/book_1_4',
      );
      expect(novel.supports(ContentCapability.save), isTrue);
    });

    test('loads qidian novel chapters through unified novel sections', () async {
      final hub = RealReadingSourceHub(
        httpClient: MockClient((request) async {
          if (request.url.host == 'daosearch.io' &&
              request.url.path == '/api/v1/search') {
            return http.Response.bytes(
              utf8.encode(
                '''
                {
                  "data": [
                    {
                      "id": 290,
                      "title": "诡秘之主",
                      "author": "爱潜水的乌贼",
                      "imageUrl": "https://example.com/qidian.jpg",
                      "genreName": "玄幻"
                    }
                  ]
                }
                ''',
              ),
              200,
              headers: const {'content-type': 'application/json; charset=utf-8'},
            );
          }
          if (request.url.host == 'daosearch.io' &&
              request.url.path == '/api/v1/books/290') {
            return http.Response.bytes(
              utf8.encode(
                '''
                {
                  "data": {
                    "id": 290,
                    "url": "https://book.qq.com/book-detail/20868264",
                    "qidianId": 1010868264,
                    "imageUrl": "https://example.com/qidian.jpg",
                    "title": "诡秘之主",
                    "author": "爱潜水的乌贼",
                    "synopsis": "蒸汽与机械的浪潮中，谁能触及非凡？",
                    "wordCount": 4465030,
                    "genreName": "玄幻",
                    "status": "completed"
                  }
                }
                ''',
              ),
              200,
              headers: const {'content-type': 'application/json; charset=utf-8'},
            );
          }
          if (request.url.host == 'daosearch.io' &&
              request.url.path == '/api/v1/books/290/chapters') {
            return http.Response.bytes(
              utf8.encode(
                '''
                {
                  "data": [
                    {
                      "id": 95663,
                      "sequenceNumber": 1,
                      "title": "绯红",
                      "url": "https://book.qq.com/book-read/20868264/1"
                    },
                    {
                      "id": 95668,
                      "sequenceNumber": 2,
                      "title": "情况",
                      "url": "https://book.qq.com/book-read/20868264/2"
                    }
                  ]
                }
                ''',
              ),
              200,
              headers: const {'content-type': 'application/json; charset=utf-8'},
            );
          }
          if (request.url.host == 'book.qq.com') {
            return http.Response.bytes(
              utf8.encode(
                '''
                <html>
                  <body>
                    <div id="article" class="chapter-content isTxt">
                      <p>周明瑞猛地惊醒。</p>
                      <p>眼前是一片陌生的灰雾。</p>
                    </div>
                  </body>
                </html>
                ''',
              ),
              200,
              headers: const {'content-type': 'text/html; charset=utf-8'},
            );
          }
          return http.Response('{}', 404);
        }),
      );

      final page = await hub.search(
        const ContentSearchRequest(query: '诡秘之主', limit: 10),
      );
      final result = page.items.firstWhere(
        (item) => item.entity.handle.source.sourceId == 'qidian-books',
      );

      expect(result.entity.title, '诡秘之主');
      expect(result.entity.subtitle, '爱潜水的乌贼');

      final detail = await hub.getDetail(
        ContentDetailRequest(handle: result.entity.handle),
      );
      final chapters =
          (detail.sections['chapters'] as List<dynamic>).cast<Map<String, Object?>>();

      expect(chapters, hasLength(2));
      expect(chapters.first['title'], '绯红');
      expect(chapters.first['paragraphs'], isNotEmpty);
    });

    test('loads fanqie novel chapters through unified novel sections', () async {
      final hub = RealReadingSourceHub(
        httpClient: MockClient((request) async {
          if (request.url.host == '101.35.133.34' &&
              request.url.path == '/api/search') {
            return http.Response.bytes(
              utf8.encode(
                '''
                {
                  "code": 200,
                  "data": {
                    "search_tabs": [
                      {},
                      {},
                      {},
                      {},
                      {},
                      {
                        "data": [
                          {
                            "book_data": [
                              {
                                "book_id": "7494874354086333464",
                                "book_name": "拥有死神体质后：国家追着我喂饭",
                                "author": "琴涩晚风",
                                "abstract": "隋暖穿书后，转身投入钓鱼事业。",
                                "category": "现言脑洞",
                                "word_number": "1623207",
                                "thumb_url": "https://example.com/fanqie.jpg"
                              }
                            ]
                          }
                        ]
                      }
                    ]
                  }
                }
                ''',
              ),
              200,
              headers: const {'content-type': 'application/json; charset=utf-8'},
            );
          }
          if (request.url.host == '101.35.133.34' &&
              request.url.path == '/api/detail') {
            return http.Response.bytes(
              utf8.encode(
                '''
                {
                  "code": 200,
                  "data": {
                    "data": {
                      "book_id": "7494874354086333464",
                      "book_name": "拥有死神体质后：国家追着我喂饭",
                      "author": "琴涩晚风",
                      "abstract": "隋暖穿书后，转身投入钓鱼事业。",
                      "category": "现言脑洞",
                      "tags": "现言脑洞,穿书,无CP",
                      "word_number": "1623207",
                      "score": "9.2",
                      "thumb_url": "https://example.com/fanqie.jpg"
                    }
                  }
                }
                ''',
              ),
              200,
              headers: const {'content-type': 'application/json; charset=utf-8'},
            );
          }
          if (request.url.host == '101.35.133.34' &&
              request.url.path == '/api/directory') {
            return http.Response.bytes(
              utf8.encode(
                '''
                {
                  "code": 200,
                  "data": {
                    "lists": [
                      {
                        "item_id": "7494876459968299544",
                        "title": "第1章 人，泥嚎！"
                      },
                      {
                        "item_id": "7494876835885367832",
                        "title": "第2章 不出意外行李箱内能开出惊喜款"
                      }
                    ]
                  }
                }
                ''',
              ),
              200,
              headers: const {'content-type': 'application/json; charset=utf-8'},
            );
          }
          if (request.url.host == '101.35.133.34' &&
              request.url.path == '/api/content') {
            expect(request.url.queryParameters['tab'], '批量');
            return http.Response.bytes(
              utf8.encode(
                '''
                {
                  "code": 200,
                  "data": {
                    "chapters": [
                      {
                        "content": "隋暖挂断电话。\\n她发现自己穿书了。"
                      },
                      {
                        "content": "她提上渔具，准备出门。"
                      }
                    ]
                  }
                }
                ''',
              ),
              200,
              headers: const {'content-type': 'application/json; charset=utf-8'},
            );
          }
          return http.Response('{}', 404);
        }),
      );

      final page = await hub.search(
        const ContentSearchRequest(query: '钓鱼', limit: 10),
      );
      final result = page.items.firstWhere(
        (item) => item.entity.handle.source.sourceId == 'fanqie-books',
      );

      expect(result.entity.title, '拥有死神体质后：国家追着我喂饭');
      expect(result.entity.subtitle, '琴涩晚风');

      final detail = await hub.getDetail(
        ContentDetailRequest(handle: result.entity.handle),
      );
      final chapters =
          (detail.sections['chapters'] as List<dynamic>).cast<Map<String, Object?>>();

      expect(chapters, hasLength(2));
      expect(chapters.first['title'], '第1章 人，泥嚎！');
      expect(chapters.first['paragraphs'], isNotEmpty);
      expect(detail.entity.metadata['score'], '9.2');
    });
  });
}
