import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:content_seeker/features/settings/settings_provider.dart';

void main() {
  group('SettingsProvider RSS import/export', () {
    test('exports feeds and re-imports custom entries', () {
      final settings = SettingsProvider();
      settings.upsertRssFeed(
        const RssFeedConfig(
          id: 'feed.custom.import',
          title: 'Custom Import Feed',
          url: 'https://example.com/custom.xml',
          subtitle: '测试导入导出',
        ),
      );

      final exported = settings.exportRssFeedsJson();
      final decoded = jsonDecode(exported) as Map<String, dynamic>;

      expect(decoded['version'], 1);
      expect((decoded['feeds'] as List).isNotEmpty, isTrue);

      final imported = SettingsProvider();
      final count = imported.importRssFeedsJson(exported);

      expect(count, greaterThan(0));
      expect(
        imported.rssFeeds.any((feed) => feed.id == 'feed.custom.import'),
        isTrue,
      );
    });
  });
}
