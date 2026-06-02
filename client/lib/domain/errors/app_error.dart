abstract class AppError {
  final String code;
  final String message;
  final Object? cause;

  const AppError({
    required this.code,
    required this.message,
    this.cause,
  });

  @override
  String toString() => '$code: $message';
}
