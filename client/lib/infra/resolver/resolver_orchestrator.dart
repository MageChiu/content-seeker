import '../../domain/errors/resolver_error.dart';
import '../../domain/media/resolved_media.dart';
import '../../models/play_request.dart';
import 'resolver_strategy.dart';

class ResolverOrchestrator {
  final List<ResolverStrategy> strategies;

  const ResolverOrchestrator({required this.strategies});

  Future<ResolvedMedia> resolve(PlayRequest request) async {
    for (final strategy in strategies) {
      final resolved = await strategy.resolve(request);
      if (resolved != null) {
        return resolved;
      }
    }

    throw const ResolverError(
      code: 'resolver.unavailable',
      message: '当前没有可用的播放解析策略。',
    );
  }
}
