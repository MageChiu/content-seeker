import '../../core/content/content.dart';

class ContentDetailFallbackPort implements ContentDetailPort {
  final List<ContentDetailPort> ports;

  const ContentDetailFallbackPort({
    required this.ports,
  });

  @override
  Future<ContentDetail> getDetail(ContentDetailRequest request) async {
    Object? lastError;
    for (final port in ports) {
      try {
        return await port.getDetail(request);
      } catch (error) {
        lastError = error;
      }
    }
    throw StateError(
      '当前没有可用的内容详情来源: ${lastError ?? request.handle.stableId}',
    );
  }
}
