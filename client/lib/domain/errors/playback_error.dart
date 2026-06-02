import 'app_error.dart';

class PlaybackError extends AppError {
  const PlaybackError({
    required super.code,
    required super.message,
    super.cause,
  });
}
