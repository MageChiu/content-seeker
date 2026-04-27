import 'app_error.dart';

class ResolverError extends AppError {
  const ResolverError({
    required super.code,
    required super.message,
    super.cause,
  });
}
