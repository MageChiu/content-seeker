import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_all/webview_all.dart';

import '../settings/settings_provider.dart';
import '../../models/media_playback.dart';
import '../../models/search_result.dart';
import 'playback_resolver.dart';

String _debugShortUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return url;
  final lastSegment =
      uri.pathSegments.isNotEmpty ? uri.pathSegments.last : uri.path;
  return '${uri.scheme}://${uri.host}/$lastSegment';
}

// #region debug-point shared:reporter
Future<void> _reportDebugEvent({
  required String hypothesisId,
  required String location,
  required String message,
  Map<String, Object?> data = const {},
}) async {
  try {
    await http.post(
      Uri.parse('http://127.0.0.1:7777/event'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'sessionId': 'ios-audio-playback',
        'runId': 'pre-fix',
        'hypothesisId': hypothesisId,
        'location': location,
        'msg': '[DEBUG] $message',
        'data': data,
        'ts': DateTime.now().millisecondsSinceEpoch,
      }),
    );
  } catch (_) {}
}
// #endregion

class PlayerPage extends StatefulWidget {
  final SearchResult result;

  const PlayerPage({super.key, required this.result});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  Player? _player;
  VideoController? _videoController;
  WebViewController? _webViewController;

  StreamSubscription<String>? _playerErrorSubscription;
  StreamSubscription<Duration>? _playerPositionSubscription;
  StreamSubscription<Duration>? _playerDurationSubscription;
  StreamSubscription<double>? _playerVolumeSubscription;
  PlaybackDescriptor? _playback;
  bool _loading = true;
  String? _error;
  int _webProgress = 0;
  bool _webCanGoBack = false;
  bool _webCanGoForward = false;
  String? _webCurrentUrl;
  bool _isScrubbing = false;
  double _scrubPositionMs = 0;
  bool _presentingFullscreen = false;
  Duration _currentPosition = Duration.zero;
  Duration _currentDuration = Duration.zero;
  double _currentVolume = 100;
  double _lastNonZeroVolume = 100;

  @override
  void initState() {
    super.initState();
    unawaited(_preparePlayback());
  }

  Future<void> _preparePlayback() async {
    try {
      final settings = context.read<SettingsProvider>();
      final playback = await const PlaybackResolver().resolve(widget.result);
      _playback = playback;
      // #region debug-point A:resolved-playback
      unawaited(_reportDebugEvent(
        hypothesisId: playback.secondaryUrl?.isNotEmpty == true ? 'A' : 'B',
        location: 'player_page.dart:_preparePlayback:resolve',
        message: 'Resolved playback descriptor',
        data: {
          'source': widget.result.source,
          'mediaType': widget.result.mediaTypeLabel,
          'kind': playback.kind.name,
          'mimeType': playback.mimeType,
          'displayLabel': playback.displayLabel,
          'primaryUrl': _debugShortUrl(playback.primaryUrl),
          'primaryHost': Uri.tryParse(playback.primaryUrl)?.host,
          'hasSecondary': playback.secondaryUrl?.isNotEmpty == true,
          'secondaryUrl': playback.secondaryUrl == null
              ? null
              : _debugShortUrl(playback.secondaryUrl!),
          'headerKeys': playback.headers.keys.toList(),
        },
      ));
      // #endregion

      switch (playback.kind) {
        case PlaybackKind.nativeStream:
          final player = Player();
          final controller = VideoController(player);
          _player = player;
          _videoController = controller;
          _currentVolume = settings.playbackVolume;
          _lastNonZeroVolume =
              settings.playbackVolume > 0 ? settings.playbackVolume : 100;
          _playerErrorSubscription = player.stream.error.listen((message) {
            // #region debug-point C:player-error-stream
            unawaited(_reportDebugEvent(
              hypothesisId: 'C',
              location: 'player_page.dart:player.stream.error',
              message: 'Player emitted error',
              data: {
                'message': message,
                'kind': playback.kind.name,
                'mediaType': widget.result.mediaTypeLabel,
                'primaryUrl': _debugShortUrl(playback.primaryUrl),
                'secondaryAttached': playback.secondaryUrl?.isNotEmpty == true,
              },
            ));
            // #endregion
            if (!mounted) return;
            setState(() {
              _error = message;
            });
          });
          _playerPositionSubscription = player.stream.position.listen((
            position,
          ) {
            _currentPosition = position;
          });
          _playerDurationSubscription = player.stream.duration.listen((
            duration,
          ) {
            _currentDuration = duration;
          });
          _playerVolumeSubscription = player.stream.volume.listen((volume) {
            _currentVolume = volume;
            if (volume > 0) {
              _lastNonZeroVolume = volume;
            }
          });
          // #region debug-point B:player-open-start
          unawaited(_reportDebugEvent(
            hypothesisId: 'B',
            location: 'player_page.dart:_preparePlayback:open:start',
            message: 'Opening player media',
            data: {
              'primaryUrl': _debugShortUrl(playback.primaryUrl),
              'primaryHost': Uri.tryParse(playback.primaryUrl)?.host,
              'mimeType': playback.mimeType,
              'headerCount': playback.headers.length,
            },
          ));
          // #endregion
          try {
            await player.setRate(settings.playbackRate);
            await player.setVolume(settings.playbackVolume);
            await player.open(
              Media(
                playback.primaryUrl,
                httpHeaders: playback.headers,
              ),
            );
            // #region debug-point B:player-open-success
            unawaited(_reportDebugEvent(
              hypothesisId: 'B',
              location: 'player_page.dart:_preparePlayback:open:success',
              message: 'Player open succeeded',
              data: {
                'primaryUrl': _debugShortUrl(playback.primaryUrl),
                'kind': playback.kind.name,
              },
            ));
            // #endregion
          } catch (error) {
            // #region debug-point B:player-open-failed
            unawaited(_reportDebugEvent(
              hypothesisId: 'B',
              location: 'player_page.dart:_preparePlayback:open:failed',
              message: 'Player open threw exception',
              data: {
                'error': error.toString(),
                'primaryUrl': _debugShortUrl(playback.primaryUrl),
              },
            ));
            // #endregion
            rethrow;
          }
          if (playback.secondaryUrl != null &&
              playback.secondaryUrl!.isNotEmpty &&
              widget.result.mediaType == MediaType.video) {
            await _attachSecondaryAudioTrack(
              player: player,
              audioUrl: playback.secondaryUrl!,
              headers: playback.headers,
            );
          }
          break;
        case PlaybackKind.embeddedWeb:
          final controller = WebViewController()
            ..setJavaScriptMode(JavaScriptMode.unrestricted)
            ..setNavigationDelegate(
              NavigationDelegate(
                onProgress: (progress) {
                  if (!mounted) return;
                  setState(() {
                    _webProgress = progress;
                  });
                },
                onWebResourceError: (error) {
                  if (!mounted) return;
                  setState(() {
                    _error = error.description;
                  });
                },
                onPageFinished: (_) {
                  unawaited(_syncWebNavigationState());
                },
              ),
            )
            ..loadRequest(Uri.parse(playback.primaryUrl));
          _webViewController = controller;
          await _syncWebNavigationState();
          break;
        case PlaybackKind.external:
          _error = '当前内容暂不支持站内播放，请使用浏览器打开。';
          break;
      }
    } catch (e) {
      // #region debug-point B:prepare-playback-failed
      unawaited(_reportDebugEvent(
        hypothesisId: 'B',
        location: 'player_page.dart:_preparePlayback:catch',
        message: 'Prepare playback failed',
        data: {
          'error': e.toString(),
          'resultSource': widget.result.source,
          'resultId': widget.result.id,
        },
      ));
      // #endregion
      _error = e.toString();
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _syncWebNavigationState() async {
    final controller = _webViewController;
    if (controller == null) return;

    final canGoBack = await controller.canGoBack();
    final canGoForward = await controller.canGoForward();
    final currentUrl = await controller.currentUrl();

    if (!mounted) return;
    setState(() {
      _webCanGoBack = canGoBack;
      _webCanGoForward = canGoForward;
      _webCurrentUrl = currentUrl;
    });
  }

  Future<void> _goBackInWebView() async {
    final controller = _webViewController;
    if (controller == null || !_webCanGoBack) return;
    await controller.goBack();
    await _syncWebNavigationState();
  }

  Future<void> _goForwardInWebView() async {
    final controller = _webViewController;
    if (controller == null || !_webCanGoForward) return;
    await controller.goForward();
    await _syncWebNavigationState();
  }

  Future<void> _reloadWebView() async {
    final controller = _webViewController;
    if (controller == null) return;
    setState(() {
      _webProgress = 0;
      _error = null;
    });
    await controller.reload();
  }

  Future<void> _attachSecondaryAudioTrack({
    required Player player,
    required String audioUrl,
    required Map<String, String> headers,
  }) async {
    final headerFields = headers.entries
        .map((entry) => '${entry.key}: ${entry.value}')
        .join(',');

    try {
      // #region debug-point D:attach-audio-start
      unawaited(_reportDebugEvent(
        hypothesisId: 'D',
        location: 'player_page.dart:_attachSecondaryAudioTrack:start',
        message: 'Attaching secondary audio track',
        data: {
          'audioUrl': _debugShortUrl(audioUrl),
          'audioHost': Uri.tryParse(audioUrl)?.host,
          'headerKeys': headers.keys.toList(),
        },
      ));
      // #endregion
      final platform = player.platform as dynamic;
      if (headerFields.isNotEmpty) {
        await platform.setProperty('http-header-fields', headerFields);
      }
      if (headers['User-Agent'] case final userAgent?) {
        await platform.setProperty('user-agent', userAgent);
      }
      if (headers['Referer'] case final referer?) {
        await platform.setProperty('referrer', referer);
      }
    } catch (_) {
      // Fallback to audio-add even if setting extra properties is unavailable.
    }

    try {
      await player.setAudioTrack(
        AudioTrack.uri(
          audioUrl,
          title: 'DASH Audio',
          language: 'und',
        ),
      );
      // #region debug-point D:attach-audio-success
      unawaited(_reportDebugEvent(
        hypothesisId: 'D',
        location: 'player_page.dart:_attachSecondaryAudioTrack:success',
        message: 'Secondary audio track attached',
        data: {
          'audioUrl': _debugShortUrl(audioUrl),
        },
      ));
      // #endregion
    } catch (error) {
      // #region debug-point D:attach-audio-failed
      unawaited(_reportDebugEvent(
        hypothesisId: 'D',
        location: 'player_page.dart:_attachSecondaryAudioTrack:failed',
        message: 'Secondary audio track attachment failed',
        data: {
          'audioUrl': _debugShortUrl(audioUrl),
          'error': error.toString(),
        },
      ));
      // #endregion
      rethrow;
    }
  }

  Future<void> _openFallback() async {
    final playback = _playback;
    final target = playback != null && playback.fallbackUrl.isNotEmpty
        ? playback.fallbackUrl
        : widget.result.playUrl;
    if (target.trim().isEmpty) {
      if (!mounted) return;
      setState(() {
        _error = '当前内容缺少可打开的播放地址。';
      });
      return;
    }
    final uri = Uri.parse(target);
    if (kIsWeb) {
      await launchUrl(uri);
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  bool get _isNativeStream =>
      _playback?.kind == PlaybackKind.nativeStream && _player != null;

  bool get _isNativeVideo =>
      _isNativeStream &&
      widget.result.mediaType == MediaType.video &&
      _videoController != null;

  int get _seekStepSeconds => context.read<SettingsProvider>().playbackSeekSeconds;

  Future<void> _togglePlayPause() async {
    final player = _player;
    if (player == null) return;
    if (_shouldRestartFromBeginning) {
      await _restartPlaybackFromBeginning();
      return;
    }
    await player.playOrPause();
  }

  bool get _shouldRestartFromBeginning {
    if (!_isNativeStream || _currentDuration <= Duration.zero) {
      return false;
    }
    final remaining = _currentDuration - _currentPosition;
    return remaining <= const Duration(milliseconds: 800);
  }

  Future<void> _restartPlaybackFromBeginning() async {
    final player = _player;
    final playback = _playback;
    if (player == null || playback == null) return;

    setState(() {
      _error = null;
      _isScrubbing = false;
      _scrubPositionMs = 0;
    });

    if (playback.secondaryUrl != null && playback.secondaryUrl!.isNotEmpty) {
      final settings = context.read<SettingsProvider>();
      await player.open(
        Media(
          playback.primaryUrl,
          httpHeaders: playback.headers,
        ),
      );
      await player.setRate(settings.playbackRate);
      await player.setVolume(_currentVolume.clamp(0.0, 100.0));
      await _attachSecondaryAudioTrack(
        player: player,
        audioUrl: playback.secondaryUrl!,
        headers: playback.headers,
      );
      await player.play();
      return;
    }

    await _seekTo(Duration.zero);
    await player.play();
  }

  Future<void> _seekTo(Duration position) async {
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
  }

  Future<void> _seekBy(int seconds) async {
    await _seekTo(
      _currentPosition + Duration(seconds: seconds),
    );
  }

  Future<void> _setPlaybackRate(double rate) async {
    final player = _player;
    if (player == null) return;
    final normalized = rate.clamp(0.5, 2.0);
    await player.setRate(normalized);
    if (!mounted) return;
    context.read<SettingsProvider>().setPlaybackRate(normalized);
  }

  Future<void> _setPlaybackVolume(double volume) async {
    final player = _player;
    if (player == null) return;
    final normalized = volume.clamp(0.0, 100.0);
    await player.setVolume(normalized);
    _currentVolume = normalized;
    if (normalized > 0) {
      _lastNonZeroVolume = normalized;
    }
    if (!mounted) return;
    context.read<SettingsProvider>().setPlaybackVolume(normalized);
  }

  Future<void> _toggleMute() async {
    final target = _currentVolume <= 0
        ? (_lastNonZeroVolume <= 0 ? 100.0 : _lastNonZeroVolume)
        : 0.0;
    await _setPlaybackVolume(target);
  }

  Future<void> _openFullscreen() async {
    if (!_isNativeVideo || _videoController == null) return;
    setState(() {
      _presentingFullscreen = true;
    });
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: true,
        pageBuilder: (context, _, __) {
          return Scaffold(
            backgroundColor: Colors.black,
            body: CallbackShortcuts(
              bindings: _shortcutBindings(fullscreenOnly: true),
              child: Focus(
                autofocus: true,
                child: SafeArea(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                        child: Row(
                          children: [
                            IconButton(
                              tooltip: '退出全屏',
                              onPressed: () => Navigator.of(context).maybePop(),
                              color: Colors.white,
                              icon: const Icon(Icons.fullscreen_exit),
                            ),
                            Expanded(
                              child: Text(
                                _playback?.title.isNotEmpty == true
                                    ? _playback!.title
                                    : widget.result.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Center(
                          child: AspectRatio(
                            aspectRatio: 16 / 9,
                            child: Video(controller: _videoController!),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: _buildNativePlaybackControls(
                          context,
                          fullscreen: true,
                          showFullscreenButton: false,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
    if (!mounted) return;
    setState(() {
      _presentingFullscreen = false;
    });
  }

  Map<ShortcutActivator, VoidCallback> _shortcutBindings({
    bool fullscreenOnly = false,
  }) {
    return <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.space): _togglePlayPause,
      const SingleActivator(LogicalKeyboardKey.arrowLeft): () {
        unawaited(_seekBy(-_seekStepSeconds));
      },
      const SingleActivator(LogicalKeyboardKey.arrowRight): () {
        unawaited(_seekBy(_seekStepSeconds));
      },
      const SingleActivator(LogicalKeyboardKey.arrowUp): () {
        unawaited(_setPlaybackVolume((_currentVolume + 10).clamp(0.0, 100.0)));
      },
      const SingleActivator(LogicalKeyboardKey.arrowDown): () {
        unawaited(_setPlaybackVolume((_currentVolume - 10).clamp(0.0, 100.0)));
      },
      const SingleActivator(LogicalKeyboardKey.keyM): () {
        unawaited(_toggleMute());
      },
      const SingleActivator(LogicalKeyboardKey.keyF): () {
        if (!fullscreenOnly) {
          unawaited(_openFullscreen());
        }
      },
      const SingleActivator(LogicalKeyboardKey.escape): () {
        if (fullscreenOnly && Navigator.of(context).canPop()) {
          Navigator.of(context).maybePop();
        }
      },
    };
  }

  @override
  void dispose() {
    _playerErrorSubscription?.cancel();
    _playerPositionSubscription?.cancel();
    _playerDurationSubscription?.cancel();
    _playerVolumeSubscription?.cancel();
    final player = _player;
    if (player != null) {
      unawaited(player.dispose());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playback = _playback;
    final title = playback != null && playback.title.isNotEmpty
        ? playback.title
        : widget.result.title;

    return CallbackShortcuts(
      bindings: _shortcutBindings(),
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            title: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              if (_isNativeVideo)
                IconButton(
                  tooltip: '全屏',
                  onPressed: _openFullscreen,
                  icon: const Icon(Icons.fullscreen),
                ),
              if (playback?.kind == PlaybackKind.embeddedWeb)
                IconButton(
                  tooltip: '后退',
                  onPressed: _webCanGoBack ? _goBackInWebView : null,
                  icon: const Icon(Icons.arrow_back),
                ),
              if (playback?.kind == PlaybackKind.embeddedWeb)
                IconButton(
                  tooltip: '前进',
                  onPressed: _webCanGoForward ? _goForwardInWebView : null,
                  icon: const Icon(Icons.arrow_forward),
                ),
              if (playback?.kind == PlaybackKind.embeddedWeb)
                IconButton(
                  tooltip: '刷新',
                  onPressed: _reloadWebView,
                  icon: const Icon(Icons.refresh),
                ),
              IconButton(
                tooltip: '浏览器打开',
                onPressed: widget.result.hasPlayUrl ? _openFallback : null,
                icon: const Icon(Icons.open_in_browser),
              ),
            ],
          ),
          body: SafeArea(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.maxWidth;
                      final playerWidth = width > 960 ? 960.0 : width;
                      return Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: playerWidth),
                          child: ListView(
                            padding: const EdgeInsets.all(16),
                            children: [
                              _buildPlayerSurface(context),
                              if (_isNativeStream) ...[
                                const SizedBox(height: 12),
                                _buildNativePlaybackControls(context),
                              ],
                              const SizedBox(height: 16),
                              Text(
                                title,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  Chip(label: Text(widget.result.sourceLabel)),
                                  Chip(label: Text(_playbackModeLabel)),
                                  Chip(label: Text(widget.result.mediaTypeLabel)),
                                  if (widget.result.durationSeconds > 0)
                                    Chip(
                                      label: Text(
                                        widget.result.durationFormatted,
                                      ),
                                    ),
                                ],
                              ),
                              if (_isNativeStream) ...[
                                const SizedBox(height: 12),
                                Text(
                                  '快捷键: Space 播放/暂停, ←/→ 快退快进, ↑/↓ 调整音量, M 静音${_isNativeVideo ? ', F 全屏, Esc 退出全屏' : ''}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                              if (widget.result.description.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                Text(
                                  widget.result.description,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ],
                              if (playback?.kind == PlaybackKind.embeddedWeb &&
                                  _webCurrentUrl != null &&
                                  _webCurrentUrl!.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                Text(
                                  _webCurrentUrl!,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                ),
                              ],
                              const SizedBox(height: 16),
                              if (_error != null)
                                Card(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .errorContainer,
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Text(_error!),
                                  ),
                                ),
                              if (playback?.kind == PlaybackKind.embeddedWeb) ...[
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    OutlinedButton.icon(
                                      onPressed: _reloadWebView,
                                      icon: const Icon(Icons.refresh),
                                      label: const Text('刷新页面'),
                                    ),
                                    OutlinedButton.icon(
                                      onPressed: _webCanGoBack
                                          ? _goBackInWebView
                                          : null,
                                      icon: const Icon(Icons.arrow_back),
                                      label: const Text('返回上一页'),
                                    ),
                                  ],
                                ),
                              ],
                              const SizedBox(height: 12),
                              FilledButton.icon(
                                onPressed: widget.result.hasPlayUrl
                                    ? _openFallback
                                    : null,
                                icon: const Icon(Icons.open_in_new),
                                label: const Text('浏览器打开'),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlayerSurface(BuildContext context) {
    final playback = _playback;
    if (playback == null) {
      return _buildPosterSurface(context);
    }

    if (playback.kind == PlaybackKind.nativeStream &&
        _error == null &&
        widget.result.mediaType == MediaType.video &&
        _videoController != null &&
        _player != null) {
      if (_presentingFullscreen) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: ColoredBox(
              color: Colors.black,
              child: Center(
                child: Text(
                  '正在全屏播放',
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(color: Colors.white70),
                ),
              ),
            ),
          ),
        );
      }
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: ColoredBox(
            color: Colors.black,
            child: Stack(
              children: [
                Video(controller: _videoController!),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: StreamBuilder<bool>(
                    stream: _player!.stream.buffering,
                    initialData: false,
                    builder: (context, snapshot) {
                      if (snapshot.data != true) {
                        return const SizedBox.shrink();
                      }
                      return const LinearProgressIndicator(minHeight: 2);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (playback.kind == PlaybackKind.nativeStream &&
        widget.result.mediaType == MediaType.audio &&
        _player != null) {
      return _buildAudioSurface(context);
    }

    if (playback.kind == PlaybackKind.embeddedWeb &&
        _webViewController != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            children: [
              WebViewWidget(controller: _webViewController!),
              if (_webProgress > 0 && _webProgress < 100)
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: LinearProgressIndicator(value: _webProgress / 100),
                ),
            ],
          ),
        ),
      );
    }

    return _buildPosterSurface(context);
  }

  Widget _buildPosterSurface(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: ColoredBox(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: widget.result.thumbnailUrl.isNotEmpty
              ? Image.network(
                  widget.result.thumbnailUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Center(
                    child: Icon(Icons.play_circle_outline, size: 72),
                  ),
                )
              : Center(
                  child: Icon(
                    widget.result.mediaType == MediaType.audio
                        ? Icons.audiotrack
                        : Icons.play_circle_outline,
                    size: 72,
                  ),
                ),
        ),
      ),
    );
  }

  String get _playbackModeLabel {
    return _playback?.displayLabel ?? '准备播放';
  }

  Widget _buildAudioSurface(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 88,
                height: 88,
                child: widget.result.thumbnailUrl.isNotEmpty
                    ? Image.network(
                        widget.result.thumbnailUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.audiotrack,
                          size: 40,
                        ),
                      )
                    : const Icon(Icons.audiotrack, size: 40),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '正在使用原生播放器播放音频',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '支持快进快退、倍速和音量调节，适合长音频和播客场景。',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNativePlaybackControls(
    BuildContext context, {
    bool fullscreen = false,
    bool showFullscreenButton = true,
  }) {
    final player = _player;
    if (player == null) {
      return const SizedBox.shrink();
    }

    final settings = context.watch<SettingsProvider>();
    final scheme = Theme.of(context).colorScheme;
    final containerColor = fullscreen ? Colors.white10 : null;
    final onContainerColor = fullscreen ? Colors.white : scheme.onSurface;
    final seekStepSeconds = settings.playbackSeekSeconds;
    const availableRates = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

    return Card(
      color: containerColor,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StreamBuilder<Duration>(
              stream: player.stream.duration,
              initialData: _currentDuration,
              builder: (context, durationSnapshot) {
                final duration = durationSnapshot.data ?? Duration.zero;
                final maxMs = duration.inMilliseconds.toDouble();
                return StreamBuilder<Duration>(
                  stream: player.stream.position,
                  initialData: _currentPosition,
                  builder: (context, positionSnapshot) {
                    final livePosition =
                        positionSnapshot.data ?? Duration.zero;
                    final displayPosition = _isScrubbing
                        ? Duration(milliseconds: _scrubPositionMs.round())
                        : livePosition;
                    final sliderMax = maxMs <= 0 ? 1.0 : maxMs;
                    final sliderValue = (_isScrubbing
                        ? _scrubPositionMs.clamp(0, sliderMax)
                        : livePosition.inMilliseconds
                            .toDouble()
                            .clamp(0, sliderMax))
                        .toDouble();

                    return Column(
                      children: [
                        Row(
                          children: [
                            Text(
                              _formatDuration(displayPosition),
                              style: TextStyle(color: onContainerColor),
                            ),
                            const Spacer(),
                            Text(
                              duration > Duration.zero
                                  ? _formatDuration(duration)
                                  : '直播 / 未知时长',
                              style: TextStyle(color: onContainerColor),
                            ),
                          ],
                        ),
                        Slider(
                          value: sliderValue,
                          min: 0,
                          max: sliderMax,
                          onChangeStart: duration > Duration.zero
                              ? (_) {
                                  setState(() {
                                    _isScrubbing = true;
                                  });
                                }
                              : null,
                          onChanged: duration > Duration.zero
                              ? (value) {
                                  setState(() {
                                    _isScrubbing = true;
                                    _scrubPositionMs = value;
                                  });
                                }
                              : null,
                          onChangeEnd: duration > Duration.zero
                              ? (value) {
                                  setState(() {
                                    _isScrubbing = false;
                                    _scrubPositionMs = value;
                                  });
                                  unawaited(
                                    _seekTo(
                                      Duration(milliseconds: value.round()),
                                    ),
                                  );
                                }
                              : null,
                        ),
                      ],
                    );
                  },
                );
              },
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                StreamBuilder<bool>(
                  stream: player.stream.playing,
                  initialData: false,
                  builder: (context, snapshot) {
                    final playing = snapshot.data ?? false;
                    return FilledButton.icon(
                      onPressed: _togglePlayPause,
                      icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                      label: Text(playing ? '暂停' : '播放'),
                    );
                  },
                ),
                OutlinedButton.icon(
                  onPressed: () => _seekBy(-seekStepSeconds),
                  icon: const Icon(Icons.replay_10),
                  label: Text('快退 ${seekStepSeconds}s'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _seekBy(seekStepSeconds),
                  icon: const Icon(Icons.forward_10),
                  label: Text('快进 ${seekStepSeconds}s'),
                ),
                PopupMenuButton<double>(
                  tooltip: '倍速',
                  initialValue: settings.playbackRate,
                  onSelected: (value) {
                    unawaited(_setPlaybackRate(value));
                  },
                  itemBuilder: (context) {
                    return availableRates
                        .map(
                          (rate) => PopupMenuItem<double>(
                            value: rate,
                            child: Text('${_formatRate(rate)} 倍速'),
                          ),
                        )
                        .toList(growable: false);
                  },
                  child: Chip(
                    avatar: const Icon(Icons.speed, size: 18),
                    label: Text('${_formatRate(settings.playbackRate)} 倍速'),
                  ),
                ),
                StreamBuilder<bool>(
                  stream: player.stream.buffering,
                  initialData: false,
                  builder: (context, snapshot) {
                    if (snapshot.data != true) {
                      return const SizedBox.shrink();
                    }
                    return const Chip(
                      avatar: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      label: Text('缓冲中'),
                    );
                  },
                ),
                if (showFullscreenButton && _isNativeVideo)
                  OutlinedButton.icon(
                    onPressed: _openFullscreen,
                    icon: const Icon(Icons.fullscreen),
                    label: const Text('全屏'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                IconButton(
                  tooltip: _currentVolume <= 0 ? '取消静音' : '静音',
                  onPressed: _toggleMute,
                  icon: Icon(
                    _currentVolume <= 0
                        ? Icons.volume_off
                        : _currentVolume < 50
                            ? Icons.volume_down
                            : Icons.volume_up,
                    color: onContainerColor,
                  ),
                ),
                Expanded(
                  child: Slider(
                    value: _currentVolume.clamp(0, 100),
                    min: 0,
                    max: 100,
                    divisions: 20,
                    label: '${_currentVolume.round()}%',
                    onChanged: (value) {
                      unawaited(_setPlaybackVolume(value));
                    },
                  ),
                ),
                SizedBox(
                  width: 52,
                  child: Text(
                    '${_currentVolume.round()}%',
                    textAlign: TextAlign.right,
                    style: TextStyle(color: onContainerColor),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration value) {
    if (value.isNegative) {
      value = Duration.zero;
    }
    final totalSeconds = value.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  String _formatRate(double rate) {
    return rate
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }
}
