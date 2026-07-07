import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';

import '../../app/bootstrap/app_bootstrap.dart';
import '../../app/content/content_request.dart';
import '../../app/runtime/runtime_playback_controller.dart';
import '../settings/settings_provider.dart';

class PlayerPage extends StatefulWidget {
  final ContentRequest request;

  const PlayerPage({super.key, required this.request});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late final RuntimePlaybackController _controller;
  bool _isScrubbing = false;
  double _scrubPositionMs = 0;
  bool _presentingFullscreen = false;

  @override
  void initState() {
    super.initState();
    final bootstrap = context.read<AppBootstrap>();
    final settings = context.read<SettingsProvider>();
    _controller = RuntimePlaybackController(
      runtimeCoordinator: bootstrap.container.runtimeCoordinator,
      settingsProvider: settings,
    );
    unawaited(_controller.initialize(widget.request));
  }

  int get _seekStepSeconds =>
      context.read<SettingsProvider>().playbackSeekSeconds;

  Future<void> _openFullscreen() async {
    final controller = _controller.videoController;
    if (!_controller.isNativeVideo || controller == null) return;
    setState(() {
      _presentingFullscreen = true;
    });
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: Stack(
              children: [
                Center(
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Video(controller: controller),
                  ),
                ),
                Positioned(
                  top: 8,
                  left: 8,
                  child: IconButton(
                    tooltip: '退出全屏',
                    color: Colors.white,
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.fullscreen_exit),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!mounted) return;
    setState(() {
      _presentingFullscreen = false;
    });
  }

  Map<ShortcutActivator, VoidCallback> _shortcutBindings() {
    return <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.space): () {
        unawaited(_controller.togglePlayPause());
      },
      const SingleActivator(LogicalKeyboardKey.arrowLeft): () {
        unawaited(_controller.seekBy(-_seekStepSeconds));
      },
      const SingleActivator(LogicalKeyboardKey.arrowRight): () {
        unawaited(_controller.seekBy(_seekStepSeconds));
      },
      const SingleActivator(LogicalKeyboardKey.arrowUp): () {
        unawaited(
          _controller.setPlaybackVolume(
            (_controller.currentVolume + 10).clamp(0.0, 100.0),
          ),
        );
      },
      const SingleActivator(LogicalKeyboardKey.arrowDown): () {
        unawaited(
          _controller.setPlaybackVolume(
            (_controller.currentVolume - 10).clamp(0.0, 100.0),
          ),
        );
      },
      const SingleActivator(LogicalKeyboardKey.keyM): () {
        unawaited(_controller.toggleMute());
      },
      const SingleActivator(LogicalKeyboardKey.keyF): () {
        if (!_presentingFullscreen) {
          unawaited(_openFullscreen());
        }
      },
    };
  }

  String _formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Widget _buildPlayerSurface() {
    final videoController = _controller.videoController;
    if (_controller.isNativeVideo && videoController != null) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Video(controller: videoController),
        ),
      );
    }
    if (_controller.isNativeStream) {
      return Card(
        child: SizedBox(
          height: 140,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.request.mediaType == ContentMediaType.audio
                      ? Icons.music_note
                      : Icons.play_circle_outline,
                  size: 56,
                ),
                const SizedBox(height: 12),
                Text(_controller.displayLabel),
              ],
            ),
          ),
        ),
      );
    }
    return Card(
      child: SizedBox(
        height: 180,
        child: Center(
          child: Text(_controller.error ?? '当前内容不可站内播放'),
        ),
      ),
    );
  }

  Widget _buildNativePlaybackControls(BuildContext context) {
    final rate = context.watch<SettingsProvider>().playbackRate;
    final effectivePosition = _isScrubbing
        ? Duration(milliseconds: _scrubPositionMs.round())
        : _controller.currentPosition;
    final totalMs = _controller.currentDuration.inMilliseconds <= 0
        ? 1.0
        : _controller.currentDuration.inMilliseconds.toDouble();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: '后退 ${_seekStepSeconds}s',
                  onPressed: () => _controller.seekBy(-_seekStepSeconds),
                  icon: const Icon(Icons.replay_10),
                ),
                IconButton(
                  tooltip: '播放/暂停',
                  onPressed: _controller.togglePlayPause,
                  icon: Icon(
                    _controller.isPlaying ? Icons.pause : Icons.play_arrow,
                  ),
                ),
                IconButton(
                  tooltip: '前进 ${_seekStepSeconds}s',
                  onPressed: () => _controller.seekBy(_seekStepSeconds),
                  icon: const Icon(Icons.forward_10),
                ),
                const Spacer(),
                if (_controller.isNativeVideo)
                  IconButton(
                    tooltip: '全屏',
                    onPressed: _openFullscreen,
                    icon: const Icon(Icons.fullscreen),
                  ),
              ],
            ),
            Slider(
              value: effectivePosition.inMilliseconds.clamp(0, totalMs.toInt()).toDouble(),
              min: 0,
              max: totalMs,
              onChanged: (value) {
                setState(() {
                  _isScrubbing = true;
                  _scrubPositionMs = value;
                });
              },
              onChangeEnd: (value) async {
                setState(() {
                  _isScrubbing = false;
                  _scrubPositionMs = value;
                });
                await _controller.seekTo(Duration(milliseconds: value.round()));
              },
            ),
            Row(
              children: [
                Text(_formatDuration(effectivePosition)),
                const Spacer(),
                Text(_formatDuration(_controller.currentDuration)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton(
                  tooltip: '静音',
                  onPressed: _controller.toggleMute,
                  icon: Icon(
                    _controller.currentVolume <= 0
                        ? Icons.volume_off
                        : Icons.volume_up,
                  ),
                ),
                Expanded(
                  child: Slider(
                    value: _controller.currentVolume.clamp(0.0, 100.0),
                    min: 0,
                    max: 100,
                    onChanged: (value) => _controller.setPlaybackVolume(value),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<double>(
                  value: rate.clamp(0.5, 2.0),
                  items: const [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
                      .map(
                        (value) => DropdownMenuItem<double>(
                          value: value,
                          child: Text('${value}x'),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value != null) {
                      unawaited(_controller.setPlaybackRate(value));
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: _shortcutBindings(),
      child: Focus(
        autofocus: true,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final title = _controller.title.isNotEmpty
                ? _controller.title
                : widget.request.title;
            return Scaffold(
              appBar: AppBar(
                title: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                actions: [
                  IconButton(
                    tooltip: '浏览器打开',
                    onPressed:
                        _controller.canOpenFallback ? _controller.openFallback : null,
                    icon: const Icon(Icons.open_in_browser),
                  ),
                ],
              ),
              body: SafeArea(
                child: _controller.loading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          _buildPlayerSurface(),
                          if (_controller.isNativeStream) ...[
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
                              if (_controller.sourceLabel.isNotEmpty)
                                Chip(label: Text(_controller.sourceLabel)),
                              Chip(label: Text(_controller.playbackModeLabel)),
                              Chip(
                                label: Text(
                                  widget.request.mediaType == ContentMediaType.video
                                      ? '视频'
                                      : '音频',
                                ),
                              ),
                              if (_controller.durationSeconds > 0)
                                Chip(
                                  label: Text(
                                    _formatDuration(
                                      Duration(seconds: _controller.durationSeconds),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          if (_controller.isNativeStream) ...[
                            const SizedBox(height: 12),
                            Text(
                              '快捷键: Space 播放/暂停, ←/→ 快退快进, ↑/↓ 调整音量, M 静音${_controller.isNativeVideo ? ', F 全屏' : ''}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                          if (_controller.description.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Text(_controller.description),
                          ],
                          if (_controller.error != null) ...[
                            const SizedBox(height: 16),
                            Card(
                              color: Theme.of(context).colorScheme.errorContainer,
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Text(_controller.error!),
                              ),
                            ),
                          ],
                        ],
                      ),
              ),
            );
          },
        ),
      ),
    );
  }
}
