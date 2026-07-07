import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/content/content_request.dart';
import '../../domain/media/media_graph.dart';
import '../../domain/runtime/runtime_session_state.dart';
import '../../features/settings/settings_provider.dart';
import 'runtime_coordinator.dart';

class RuntimePlaybackController extends ChangeNotifier {
  final RuntimeCoordinator runtimeCoordinator;
  final SettingsProvider settingsProvider;

  RuntimePlaybackController({
    required this.runtimeCoordinator,
    required this.settingsProvider,
  }) {
    runtimeCoordinator.addListener(_handleRuntimeStateChanged);
  }

  Player? _player;
  VideoController? _videoController;
  StreamSubscription<String>? _playerErrorSubscription;
  StreamSubscription<Duration>? _playerPositionSubscription;
  StreamSubscription<Duration>? _playerDurationSubscription;
  StreamSubscription<double>? _playerVolumeSubscription;
  StreamSubscription<bool>? _playerPlayingSubscription;

  ContentRequest? _request;
  bool _loading = false;
  String? _error;
  Duration _currentPosition = Duration.zero;
  Duration _currentDuration = Duration.zero;
  double _currentVolume = 100;
  double _lastNonZeroVolume = 100;
  bool _isPlaying = false;

  bool get loading => _loading;
  String? get error => _error ?? runtimeCoordinator.state.session.errorMessage;
  ContentRequest? get request => _request;
  Player? get player => _player;
  VideoController? get videoController => _videoController;
  MediaGraph? get mediaGraph => runtimeCoordinator.state.session.mediaGraph;
  RuntimeSessionState get session => runtimeCoordinator.state.session;
  Duration get currentPosition => _currentPosition;
  Duration get currentDuration => _currentDuration;
  double get currentVolume => _currentVolume;
  double get lastNonZeroVolume => _lastNonZeroVolume;
  bool get isPlaying => _isPlaying;

  bool get isNativeStream => mediaGraph != null && _player != null;
  bool get isNativeVideo =>
      isNativeStream &&
      request?.mediaType == ContentMediaType.video &&
      _videoController != null;

  String get title {
    final graph = mediaGraph;
    if (graph != null && graph.title.trim().isNotEmpty) {
      return graph.title.trim();
    }
    return request?.title ?? '';
  }

  String get displayLabel {
    final graph = mediaGraph;
    if (graph != null && graph.displayLabel.trim().isNotEmpty) {
      return graph.displayLabel.trim();
    }
    return 'Seeker Runtime';
  }

  String get sourceLabel => request?.sourceLabel ?? '';
  int get durationSeconds => request?.durationSeconds ?? 0;
  String get description => request?.description ?? '';

  String get playbackModeLabel {
    final graph = mediaGraph;
    if (graph == null) {
      return 'Unknown';
    }
    switch (graph.resolverKind) {
      case 'direct':
        return 'Runtime Direct';
      case 'extractor':
        return 'Runtime Extractor';
      case 'network-fallback':
        return 'Runtime Network';
      case 'local-fallback':
        return 'Runtime Local';
      default:
        return 'Runtime Stream';
    }
  }

  bool get canOpenFallback {
    final graph = mediaGraph;
    if (graph != null && graph.fallbacks.isNotEmpty) {
      return true;
    }
    final req = request;
    return req?.primaryUri != null || req?.fallbackUri != null;
  }

  Future<void> initialize(ContentRequest request) async {
    _request = request;
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      await _disposePlayer();
      await runtimeCoordinator.prepare(request);
      final graph = mediaGraph;
      if (graph == null) {
        throw StateError('runtime media graph is missing');
      }
      final player = Player(
        configuration: const PlayerConfiguration(
          logLevel: MPVLogLevel.warn,
        ),
      );
      _player = player;
      _videoController = VideoController(player);
      _currentVolume = settingsProvider.playbackVolume;
      _lastNonZeroVolume =
          settingsProvider.playbackVolume > 0 ? settingsProvider.playbackVolume : 100;
      _bindPlayer(player);
      await player.setRate(settingsProvider.playbackRate);
      await player.setVolume(settingsProvider.playbackVolume);
      await player.open(
        Media(
          graph.primaryUrl.toString(),
          httpHeaders: graph.auth.headers,
        ),
      );
      if (graph.secondaryAudioUrl != null &&
          request.mediaType == ContentMediaType.video) {
        await player.setAudioTrack(
          AudioTrack.uri(
            graph.secondaryAudioUrl.toString(),
            title: 'Secondary Audio',
            language: 'und',
          ),
        );
      }
      await runtimeCoordinator.setRate(settingsProvider.playbackRate);
      await runtimeCoordinator.setVolume(settingsProvider.playbackVolume);
      await runtimeCoordinator.play();
    } catch (error) {
      _error = error.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> togglePlayPause() async {
    final player = _player;
    if (player == null) return;
    if (_isPlaying) {
      await player.pause();
      await runtimeCoordinator.pause();
    } else {
      await player.play();
      await runtimeCoordinator.play();
    }
  }

  Future<void> seekTo(Duration position) async {
    final player = _player;
    if (player == null) return;
    var target = position;
    if (target < Duration.zero) {
      target = Duration.zero;
    }
    if (_currentDuration > Duration.zero && target > _currentDuration) {
      target = _currentDuration;
    }
    await player.seek(target);
    await runtimeCoordinator.seek(target);
    _currentPosition = target;
    notifyListeners();
  }

  Future<void> seekBy(int seconds) async {
    await seekTo(_currentPosition + Duration(seconds: seconds));
  }

  Future<void> setPlaybackRate(double rate) async {
    final player = _player;
    if (player == null) return;
    final normalized = rate.clamp(0.5, 2.0);
    await player.setRate(normalized);
    await runtimeCoordinator.setRate(normalized);
    settingsProvider.setPlaybackRate(normalized);
  }

  Future<void> setPlaybackVolume(double volume) async {
    final player = _player;
    if (player == null) return;
    final normalized = volume.clamp(0.0, 100.0);
    await player.setVolume(normalized);
    await runtimeCoordinator.setVolume(normalized);
    _currentVolume = normalized;
    if (normalized > 0) {
      _lastNonZeroVolume = normalized;
    }
    settingsProvider.setPlaybackVolume(normalized);
    notifyListeners();
  }

  Future<void> toggleMute() async {
    final target = _currentVolume <= 0
        ? (_lastNonZeroVolume <= 0 ? 100.0 : _lastNonZeroVolume)
        : 0.0;
    await setPlaybackVolume(target);
  }

  Future<void> openFallback() async {
    final graph = mediaGraph;
    final target = graph != null && graph.fallbacks.isNotEmpty
        ? graph.fallbacks.first.url
        : (request?.fallbackUri ?? request?.primaryUri);
    if (target == null) {
      _error = '当前内容缺少可打开的播放地址。';
      notifyListeners();
      return;
    }
    await launchUrl(target, mode: LaunchMode.externalApplication);
  }

  void _bindPlayer(Player player) {
    _playerErrorSubscription = player.stream.error.listen((message) {
      _error = message;
      notifyListeners();
    });
    _playerPositionSubscription = player.stream.position.listen((position) {
      _currentPosition = position;
      notifyListeners();
    });
    _playerDurationSubscription = player.stream.duration.listen((duration) {
      _currentDuration = duration;
      notifyListeners();
    });
    _playerVolumeSubscription = player.stream.volume.listen((volume) {
      _currentVolume = volume;
      if (volume > 0) {
        _lastNonZeroVolume = volume;
      }
      notifyListeners();
    });
    _playerPlayingSubscription = player.stream.playing.listen((playing) {
      _isPlaying = playing;
      notifyListeners();
    });
  }

  void _handleRuntimeStateChanged() {
    notifyListeners();
  }

  Future<void> _disposePlayer() async {
    await _playerErrorSubscription?.cancel();
    await _playerPositionSubscription?.cancel();
    await _playerDurationSubscription?.cancel();
    await _playerVolumeSubscription?.cancel();
    await _playerPlayingSubscription?.cancel();
    _playerErrorSubscription = null;
    _playerPositionSubscription = null;
    _playerDurationSubscription = null;
    _playerVolumeSubscription = null;
    _playerPlayingSubscription = null;
    final player = _player;
    _player = null;
    _videoController = null;
    _currentPosition = Duration.zero;
    _currentDuration = Duration.zero;
    _isPlaying = false;
    if (player != null) {
      await player.dispose();
    }
  }

  @override
  void dispose() {
    runtimeCoordinator.removeListener(_handleRuntimeStateChanged);
    unawaited(_disposePlayer());
    unawaited(runtimeCoordinator.closeCurrentSession());
    super.dispose();
  }
}
