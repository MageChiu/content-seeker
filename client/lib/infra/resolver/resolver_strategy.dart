import '../../domain/media/resolved_media.dart';
import '../../models/play_request.dart';

abstract class ResolverStrategy {
  Future<ResolvedMedia?> resolve(PlayRequest request);
}
