import 'app_error.dart';

class DownloadError extends AppError {
  const DownloadError({
    required super.code,
    required super.message,
    super.cause,
  });
}
