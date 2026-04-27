import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_all/webview_all.dart';

import '../../native_bridge/seeker_native.dart';
import '../../platform/directory_access.dart';

import '../../app/bootstrap/app_bootstrap.dart';
import '../../app/content/content_bridge.dart';
import '../../domain/media/resolved_media.dart';
import '../../models/play_request.dart';
import '../settings/settings_provider.dart';

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
  final PlayRequest request;

  const PlayerPage({super.key, required this.request});

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
  ResolvedMedia? _playback;
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

  // 边播边存：mpv 的 stream-record 属性会把当前播放流并行写到磁盘
  bool _isRecording = false;
  String? _recordingPath; // 视频流写入路径（主轨）
  String? _recordingExportPath; // 最终导出路径（用户可见）
  String? _audioRecordingPath; // 音频流写入路径（DASH 第二轨）
  http.Client? _audioDownloadClient;
  Future<void>? _audioDownloadDone;

  @override
  void initState() {
    super.initState();
    unawaited(_preparePlayback());
  }

  Future<void> _preparePlayback() async {
    try {
      final settings = context.read<SettingsProvider>();
      final bootstrap = context.read<AppBootstrap>();
      final session = await bootstrap.container.contentEngine.preparePlayback(
        widget.request.toContentRequest(),
      );
      final playback = session.media;
      _playback = playback;
      // #region debug-point A:resolved-playback
      unawaited(_reportDebugEvent(
        hypothesisId: playback.secondaryAudioUri != null ? 'A' : 'B',
        location: 'player_page.dart:_preparePlayback:resolve',
        message: 'Resolved playback media',
        data: {
          'source': widget.request.sourceHint,
          'mediaType': widget.request.mediaType == PlayMediaType.video ? '视频' : '音频',
          'kind': playback.kind.name,
          'mimeType': playback.mimeType,
          'displayLabel': playback.displayLabel,
          'primaryUrl': _debugShortUrl(playback.primaryUri.toString()),
          'primaryHost': playback.primaryUri.host,
          'hasSecondary': playback.secondaryAudioUri != null,
          'secondaryUrl': playback.secondaryAudioUri == null
              ? null
              : _debugShortUrl(playback.secondaryAudioUri.toString()),
          'headerKeys': playback.headers.keys.toList(),
        },
      ));
      // #endregion

      switch (playback.kind) {
        case ResolvedMediaKind.nativeStream:
          final player = Player(
            configuration: const PlayerConfiguration(
              logLevel: MPVLogLevel.warn,
            ),
          );
          final controller = VideoController(player);
          _player = player;
          _videoController = controller;
          _currentVolume = settings.playbackVolume;
          _lastNonZeroVolume =
              settings.playbackVolume > 0 ? settings.playbackVolume : 100;
          _playerErrorSubscription = player.stream.error.listen((message) {
            // 调试：打印到控制台便于诊断
            debugPrint('[mpv-error] $message');
            // #region debug-point C:player-error-stream
            unawaited(_reportDebugEvent(
              hypothesisId: 'C',
              location: 'player_page.dart:player.stream.error',
              message: 'Player emitted error',
              data: {
                'message': message,
                'kind': playback.kind.name,
                'mediaType': widget.request.mediaType == PlayMediaType.video ? '视频' : '音频',
                'primaryUrl': _debugShortUrl(playback.primaryUri.toString()),
                'secondaryAttached': playback.secondaryAudioUri != null,
              },
            ));
            // #endregion
            if (!mounted) return;
            setState(() {
              _error = message;
            });
          });
          // 监听 mpv 内部日志（包括网络请求失败等关键信息）
          player.stream.log.listen((log) {
            debugPrint('[mpv-log] ${log.level} ${log.prefix}: ${log.text}');
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
              'primaryUrl': _debugShortUrl(playback.primaryUri.toString()),
              'primaryHost': playback.primaryUri.host,
              'mimeType': playback.mimeType,
              'headerCount': playback.headers.length,
            },
          ));
          // #endregion
          try {
            await player.setRate(settings.playbackRate);
            await player.setVolume(settings.playbackVolume);
            // 参考 aiplayer：通过 mpv 原生 property 显式设置 headers
            // 这是在网络请求实际发起前最稳妥的方式（macOS 上 Media.httpHeaders 不可靠）
            try {
              final platform = player.platform as dynamic;
              final headers = playback.headers;
              if (headers.isNotEmpty) {
                final headerFields = headers.entries
                    .where((e) =>
                        e.key.toLowerCase() != 'user-agent' &&
                        e.key.toLowerCase() != 'referer')
                    .map((e) => '${e.key}: ${e.value}')
                    .join('\n');
                if (headerFields.isNotEmpty) {
                  await platform.setProperty(
                      'http-header-fields', headerFields);
                }
                if (headers['User-Agent'] case final ua?) {
                  await platform.setProperty('user-agent', ua);
                }
                if (headers['Referer'] case final ref?) {
                  await platform.setProperty('referrer', ref);
                }
              }
              // 边播边缓存（透明缓存）：根据用户设置决定
              await _applyPlaybackCacheConfig(platform);
            } catch (e) {
              debugPrint('[mpv] set header properties failed: $e');
            }
            await player.open(
              Media(
                playback.primaryUri.toString(),
                httpHeaders: playback.headers,
              ),
            );
            // #region debug-point B:player-open-success
            unawaited(_reportDebugEvent(
              hypothesisId: 'B',
              location: 'player_page.dart:_preparePlayback:open:success',
              message: 'Player open succeeded',
              data: {
                'primaryUrl': _debugShortUrl(playback.primaryUri.toString()),
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
                'primaryUrl': _debugShortUrl(playback.primaryUri.toString()),
              },
            ));
            // #endregion
            rethrow;
          }
          if (playback.secondaryAudioUri != null &&
              widget.request.mediaType == PlayMediaType.video) {
            await _attachSecondaryAudioTrack(
              player: player,
              audioUrl: playback.secondaryAudioUri.toString(),
              headers: playback.headers,
            );
          }
          break;
        case ResolvedMediaKind.embeddedWeb:
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
            ..loadRequest(playback.primaryUri);
          _webViewController = controller;
          await _syncWebNavigationState();
          break;
        case ResolvedMediaKind.external:
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
          'resultSource': widget.request.sourceHint,
          'resultId': widget.request.contentId,
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
        : widget.request.url;
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

  /// 切换边播边存：使用 mpv 的 stream-record 属性
  /// - 启动：写当前播放流到磁盘文件（不影响播放，原样保存容器格式）
  ///         如果是 DASH 双流场景，同时启动一个 http 下载器把 audio 写到另一个文件
  /// - 停止：清空 stream-record，等待 audio 下载结束后用 ffmpeg mux 成完整 mp4
  Future<void> _toggleRecording() async {
    final player = _player;
    if (player == null) return;
    final platform = player.platform as dynamic;

    if (_isRecording) {
      // 1) 停止 mpv 视频写入
      try {
        await platform.setProperty('stream-record', '');
      } catch (e) {
        debugPrint('[record] stop failed: $e');
      }
      // 给 mpv 一点时间刷盘（stream-record 是异步写入）
      await Future<void>.delayed(const Duration(milliseconds: 300));
      // 2) 停止 audio 旁路下载
      _audioDownloadClient?.close();
      _audioDownloadClient = null;
      try {
        await _audioDownloadDone;
      } catch (e) {
        debugPrint('[record] audio download error: $e');
      }
      _audioDownloadDone = null;

      final videoPath = _recordingPath;
      final exportPath = _recordingExportPath;
      final audioPath = _audioRecordingPath;
      if (!mounted) return;
      setState(() {
        _isRecording = false;
      });

      if (videoPath == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('录制已停止')),
        );
        return;
      }

      // 校验视频文件是否真的写入了（沙箱可能阻止 mpv 写入到自定义路径）
      final videoFile = File(videoPath);
      bool videoOk = false;
      int videoSize = 0;
      try {
        if (await videoFile.exists()) {
          videoSize = await videoFile.length();
          videoOk = videoSize > 0;
        }
      } catch (_) {}

      if (!videoOk) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '录制失败：mpv 未能写入 $videoPath\n'
              'macOS 沙箱可能拒绝了该路径写入，请到「设置 → 边播边存」'
              '通过「浏览选择目录」重新授权一个目录。',
            ),
            duration: const Duration(seconds: 8),
          ),
        );
        return;
      }
      debugPrint('[record] video saved: $videoPath ($videoSize bytes)');

      // 3) 如果有音频旁路文件，调 ffmpeg mux
      if (audioPath != null && await File(audioPath).exists()) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('正在合并音视频...')),
        );
        try {
          final muxedStagingPath = await _muxAvWithNative(
            videoPath: videoPath,
            audioPath: audioPath,
          );
          final outputPath = await _exportRecordedFile(
            sourcePath: muxedStagingPath,
            preferredOutputPath: exportPath,
          );
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('录制已保存：$outputPath'),
              duration: const Duration(seconds: 6),
              action: SnackBarAction(
                label: '打开目录',
                onPressed: () {
                  launchUrl(Directory(p.dirname(outputPath)).uri);
                },
              ),
            ),
          );
        } catch (e) {
          debugPrint('[record] mux failed: $e');
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'ffmpeg 合并失败：$e\n已保留分轨：$videoPath / $audioPath',
              ),
              duration: const Duration(seconds: 8),
            ),
          );
        }
      } else {
        if (!mounted) return;
        try {
          final outputPath = await _exportRecordedFile(
            sourcePath: videoPath,
            preferredOutputPath: exportPath,
          );
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('录制已保存：$outputPath'),
              duration: const Duration(seconds: 4),
              action: SnackBarAction(
                label: '打开目录',
                onPressed: () {
                  launchUrl(Directory(p.dirname(outputPath)).uri);
                },
              ),
            ),
          );
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('录制文件导出失败：$e\n已保留临时文件：$videoPath'),
              duration: const Duration(seconds: 8),
            ),
          );
        }
      }
      return;
    }

    // 启动录制
    try {
      Directory exportDir = await _resolveRecordingDir();
      // 最终导出目录仍尊重用户设置，但 mpv 实际录制一律先落到应用沙箱内，
      // 避免 stream-record 直接写用户目录时被沙箱拒绝。
      exportDir = await _ensureWritable(exportDir);
      final stagingDir = await _recordingStagingDir();
      final ts = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final safeTitle = (widget.request.title.isEmpty
              ? 'recording'
              : widget.request.title)
          .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final ext = _guessRecordingExtension();
      final basename = '${safeTitle}_$ts';
      final finalExt =
          _playback?.secondaryAudioUri != null ? 'mp4' : ext;
      final videoPath = p.join(stagingDir.path, '$basename.$ext');
      final exportPath = p.join(exportDir.path, '$basename.$finalExt');
      await Directory(p.dirname(videoPath)).create(recursive: true);
      debugPrint('[record] start: ext=$ext, staging=${stagingDir.path}, '
          'export=${exportDir.path}, '
          'hasSecondaryAudio=${_playback?.secondaryAudioUri != null}');
      await platform.setProperty('stream-record', videoPath);

      // 如果是 DASH（有独立音频流），同时旁路下载 audio
      String? audioPath;
      final audioUri = _playback?.secondaryAudioUri;
      if (audioUri != null) {
        audioPath = p.join(stagingDir.path, '$basename.audio.m4s');
        _audioRecordingPath = audioPath;
        _audioDownloadClient = http.Client();
        _audioDownloadDone = _downloadAudioStream(
          uri: audioUri,
          targetPath: audioPath,
          headers: _playback?.headers ?? const {},
        );
      } else {
        _audioRecordingPath = null;
      }

      if (!mounted) return;
      setState(() {
        _isRecording = true;
        _recordingPath = videoPath;
        _recordingExportPath = exportPath;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(audioPath == null
              ? '开始录制，停止后将导出到 → $exportPath'
              : '开始录制（含音频旁路），停止后将导出到 → $exportPath'),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      debugPrint('[record] start failed: $e');
      if (!mounted) return;
      final hint = e is PathAccessException
          ? '没有权限写入该目录。可在「设置 → 边播边存」自定义路径，'
              'macOS 沙箱模式建议改到 ~/Movies 或 ~/Downloads 内。\n$e'
          : '$e';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('录制失败：$hint'),
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  /// 旁路下载 DASH 音频流到本地文件，与 mpv 视频录制并行
  Future<void> _downloadAudioStream({
    required Uri uri,
    required String targetPath,
    required Map<String, String> headers,
  }) async {
    final client = _audioDownloadClient;
    if (client == null) return;
    final req = http.Request('GET', uri);
    req.headers.addAll(headers);
    // Bilibili CDN 必须的 Referer
    req.headers.putIfAbsent('Referer', () => 'https://www.bilibili.com');
    req.headers.putIfAbsent('User-Agent', () => 'Mozilla/5.0');
    final resp = await client.send(req);
    final sink = File(targetPath).openWrite();
    try {
      await resp.stream.pipe(sink);
    } finally {
      await sink.flush();
      await sink.close();
    }
  }

  /// 调用 libseeker 原生 mux（macOS/iOS 走 AVFoundation，沙箱友好）
  /// 把 video.m4s + audio.m4s 合并为完整 mp4，不重编码
  Future<String> _muxAvWithNative({
    required String videoPath,
    required String audioPath,
  }) async {
    final outPath = p.setExtension(videoPath, '.mp4');
    final seeker = SeekerNative.instance;
    if (!seeker.isInitialized) {
      throw Exception('libseeker 未初始化，无法执行音视频合并');
    }
    final result = await seeker.muxAvToMp4(
      videoPath: videoPath,
      audioPath: audioPath,
      outputPath: outPath,
    );
    // 合并成功 → 删除分轨临时文件
    try {
      await File(videoPath).delete();
      await File(audioPath).delete();
    } catch (_) {}
    return result;
  }

  Future<String> _exportRecordedFile({
    required String sourcePath,
    String? preferredOutputPath,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw Exception('cannot read recorded file: $sourcePath');
    }
    final outputPath = preferredOutputPath?.trim();
    if (outputPath == null || outputPath.isEmpty || outputPath == sourcePath) {
      return sourcePath;
    }
    final target = File(outputPath);
    await target.parent.create(recursive: true);
    try {
      final moved = await source.rename(target.path);
      return moved.path;
    } on FileSystemException {
      await source.copy(target.path);
      await source.delete();
      return target.path;
    }
  }


  /// 解析录制目录：
  /// 1. 用户在设置中自定义的目录（最高优先级）
  /// 2. 应用文档目录下的 content_seeker_recordings/（沙箱内必可写）
  /// 3. Downloads 目录（需 entitlement，但无法保证有创建子目录权限）
  Future<Directory> _resolveRecordingDir() async {
    // 1) 用户自定义路径
    final settings = context.read<SettingsProvider>();
    final custom = settings.recordingDir.trim();
    if (custom.isNotEmpty) {
      if (_requiresBookmarkButMissing(
        custom,
        settings.recordingDirBookmark,
      )) {
        final fallback = await _defaultRecordingDir();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                '录制目录是旧配置或手动输入路径，macOS 未保存授权信息。'
                '已自动改用应用内目录，请到「设置 → 边播边存（手动录制）」重新用“浏览选择目录”选择一次。',
              ),
              duration: Duration(seconds: 6),
            ),
          );
        }
        return fallback;
      }
      final dir = await _resolveUserScopedDirectory(
        custom,
        settings.recordingDirBookmark,
      );
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return dir;
    }
    // 2) 默认：应用文档目录（沙箱内一定可写）
    return _defaultRecordingDir();
  }

  /// 验证目录是否真的可写（macOS 沙箱可能拒绝用户主目录下的子目录创建/写入）。
  /// 不可写时自动 fallback 到应用 Application Support 目录，避免录制完才发现没文件。
  Future<Directory> _ensureWritable(Directory dir) async {
    final probe = File(p.join(dir.path, '.seeker_write_probe'));
    try {
      await dir.create(recursive: true);
      await probe.writeAsString('ok', flush: true);
      await probe.delete();
      return dir;
    } catch (e) {
      debugPrint('[record] dir not writable: ${dir.path} ($e), '
          'fallback to ApplicationSupport');
      final fallbackBase = await getApplicationSupportDirectory();
      final fallback =
          Directory(p.join(fallbackBase.path, 'content_seeker_recordings'));
      await fallback.create(recursive: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '所选目录无写入权限，已临时改用应用支持目录：${fallback.path}\n'
              '建议到「设置 → 边播边存」用「浏览选择目录」重新授权。',
            ),
            duration: const Duration(seconds: 6),
          ),
        );
      }
      return fallback;
    }
  }

  /// 应用边播边缓存（透明缓存）配置：
  /// 开启时让 mpv 把网络流写入本地缓存目录，加速重播 + 提升网络抖动下的稳定性。
  /// 关闭或缓存目录不可写时退化为内存缓存（不再产生 "Failed to create file cache"）。
  Future<void> _applyPlaybackCacheConfig(dynamic platform) async {
    final settings = context.read<SettingsProvider>();
    if (!settings.playbackCacheEnabled) {
      // 关闭：内存缓存（默认行为），但禁用 cache-on-disk 以避免在沙箱拒写位置反复尝试
      try {
        await platform.setProperty('cache', 'auto');
        await platform.setProperty('cache-on-disk', 'no');
      } catch (_) {}
      return;
    }
    Directory? cacheDir;
    try {
      cacheDir = await _resolveCacheDir();
      cacheDir = await _ensureWritable(cacheDir);
    } catch (e) {
      debugPrint('[cache] resolve dir failed: $e, fallback to memory cache');
      cacheDir = null;
    }
    try {
      if (cacheDir != null) {
        await platform.setProperty('cache', 'yes');
        await platform.setProperty('cache-on-disk', 'yes');
        await platform.setProperty('cache-dir', cacheDir.path);
        // 缓存预读窗口（秒）。注意 mpv 实际下载边界由 demuxer-max-bytes 控制，
        // 而不是 cache-secs。这里给一个"激进预读"配置：
        // - demuxer-max-bytes：前向缓冲上限（默认 150MiB），调大让 mpv 持续下载
        // - demuxer-max-back-bytes：回看缓冲上限（默认 75MiB），保留一些便于回退
        // - demuxer-readahead-secs：预读时长上限（默认 20s）
        await platform.setProperty('cache-secs', '3600');
        await platform.setProperty('demuxer-max-bytes', '4294967296'); // 4 GiB
        await platform.setProperty('demuxer-max-back-bytes', '1073741824'); // 1 GiB
        await platform.setProperty('demuxer-readahead-secs', '3600');
        debugPrint('[cache] enabled at ${cacheDir.path}, '
            'max=4GiB, readahead=3600s');
        _startCacheProbe(platform, cacheDir);
      } else {
        await platform.setProperty('cache', 'yes');
        await platform.setProperty('cache-on-disk', 'no');
      }
    } catch (e) {
      debugPrint('[cache] apply failed: $e');
    }
  }

  Timer? _cacheProbeTimer;

  /// 定期上报缓存状态到日志，方便用户/开发者确认 cache-on-disk 是否真的在工作
  void _startCacheProbe(dynamic platform, Directory cacheDir) {
    _cacheProbeTimer?.cancel();
    _cacheProbeTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      try {
        final state = await platform.getProperty('demuxer-cache-state');
        // 同时 du 一下缓存目录占用
        int totalBytes = 0;
        try {
          await for (final entity in cacheDir.list(recursive: true)) {
            if (entity is File) {
              totalBytes += await entity.length();
            }
          }
        } catch (_) {}
        final mb = (totalBytes / 1024 / 1024).toStringAsFixed(1);
        debugPrint('[cache] state=$state, dir_size=${mb}MiB');
      } catch (e) {
        debugPrint('[cache] probe error: $e');
      }
    });
  }

  /// 解析播放缓存目录：用户自定义 → 应用支持目录默认子目录（沙箱可写）
  Future<Directory> _resolveCacheDir() async {
    final settings = context.read<SettingsProvider>();
    final custom = settings.playbackCacheDir.trim();
    if (custom.isNotEmpty) {
      if (_requiresBookmarkButMissing(
        custom,
        settings.playbackCacheDirBookmark,
      )) {
        final fallback = await _defaultCacheDir();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                '缓存目录是旧配置或手动输入路径，macOS 未保存授权信息。'
                '已自动改用应用内目录，请到「设置 → 边播边缓存」重新用“浏览选择目录”选择一次。',
              ),
              duration: Duration(seconds: 6),
            ),
          );
        }
        return fallback;
      }
      return _resolveUserScopedDirectory(
        custom,
        settings.playbackCacheDirBookmark,
      );
    }
    return _defaultCacheDir();
  }

  Future<Directory> _resolveUserScopedDirectory(
    String path,
    String bookmark,
  ) async {
    final resolved = await DirectoryAccess.resolveBookmark(bookmark);
    final effectivePath = resolved?.path.trim().isNotEmpty == true
        ? resolved!.path
        : path;
    return Directory(effectivePath);
  }

  bool _requiresBookmarkButMissing(String path, String bookmark) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) {
      return false;
    }
    return path.trim().isNotEmpty && bookmark.trim().isEmpty;
  }

  Future<Directory> _defaultRecordingDir() async {
    final base = await getApplicationDocumentsDirectory();
    final target = Directory(p.join(base.path, 'content_seeker_recordings'));
    if (!await target.exists()) {
      await target.create(recursive: true);
    }
    return target;
  }

  Future<Directory> _defaultCacheDir() async {
    final base = await getApplicationSupportDirectory();
    final target = Directory(p.join(base.path, 'content_seeker_cache'));
    if (!await target.exists()) {
      await target.create(recursive: true);
    }
    return target;
  }

  Future<Directory> _recordingStagingDir() async {
    final base = await getApplicationSupportDirectory();
    final target = Directory(
      p.join(base.path, 'content_seeker_recordings_staging'),
    );
    if (!await target.exists()) {
      await target.create(recursive: true);
    }
    return target;
  }

  String _guessRecordingExtension() {
    // DASH 双流场景：视频流是 fragmented mp4 (m4s) 单轨，
    // 必须用 .m4s 扩展名让 mpv 直通写入；后续会和 audio 合并为 .mp4
    if (_playback?.secondaryAudioUri != null) {
      return 'm4s';
    }
    final mime = _playback?.mimeType ?? '';
    if (mime.contains('mp4')) return 'mp4';
    if (mime.contains('webm')) return 'webm';
    if (mime.contains('mpegURL') || mime.contains('m3u8')) return 'ts';
    final url = _playback?.primaryUri.path.toLowerCase() ?? '';
    if (url.contains('.m4s')) return 'm4s';
    if (url.contains('.mp4')) return 'mp4';
    if (url.contains('.webm')) return 'webm';
    if (url.contains('.m3u8')) return 'ts';
    return 'mp4';
  }

  bool get _isNativeStream =>
      _playback?.kind == ResolvedMediaKind.nativeStream && _player != null;

  bool get _isNativeVideo =>
      _isNativeStream &&
      widget.request.mediaType == PlayMediaType.video &&
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

    if (playback.secondaryAudioUri != null) {
      final settings = context.read<SettingsProvider>();
      await player.open(
        Media(
          playback.primaryUri.toString(),
          httpHeaders: playback.headers,
        ),
      );
      await player.setRate(settings.playbackRate);
      await player.setVolume(_currentVolume.clamp(0.0, 100.0));
      await _attachSecondaryAudioTrack(
        player: player,
        audioUrl: playback.secondaryAudioUri.toString(),
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
                                    : widget.request.title,
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
    _cacheProbeTimer?.cancel();
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
        : widget.request.title;

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
              if (_isNativeStream)
                IconButton(
                  tooltip: _isRecording ? '停止录制' : '边播边存',
                  onPressed: _toggleRecording,
                  icon: Icon(
                    _isRecording
                        ? Icons.stop_circle
                        : Icons.fiber_manual_record,
                    color: _isRecording ? Colors.redAccent : null,
                  ),
                ),
              if (playback?.kind == ResolvedMediaKind.embeddedWeb)
                IconButton(
                  tooltip: '后退',
                  onPressed: _webCanGoBack ? _goBackInWebView : null,
                  icon: const Icon(Icons.arrow_back),
                ),
              if (playback?.kind == ResolvedMediaKind.embeddedWeb)
                IconButton(
                  tooltip: '前进',
                  onPressed: _webCanGoForward ? _goForwardInWebView : null,
                  icon: const Icon(Icons.arrow_forward),
                ),
              if (playback?.kind == ResolvedMediaKind.embeddedWeb)
                IconButton(
                  tooltip: '刷新',
                  onPressed: _reloadWebView,
                  icon: const Icon(Icons.refresh),
                ),
              IconButton(
                tooltip: '浏览器打开',
                onPressed: widget.request.hasUrl ? _openFallback : null,
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
                                  Chip(label: Text(widget.request.sourceLabel)),
                                  Chip(label: Text(_playbackModeLabel)),
                                  Chip(label: Text(widget.request.mediaType == PlayMediaType.video ? '视频' : '音频')),
                                  if (widget.request.durationSeconds > 0)
                                    Chip(
                                      label: Text(
                                        widget.request.durationFormatted,
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
                              if (widget.request.description.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                Text(
                                  widget.request.description,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ],
                              if (playback?.kind ==
                                      ResolvedMediaKind.embeddedWeb &&
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
                              if (playback?.kind ==
                                  ResolvedMediaKind.embeddedWeb) ...[
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
                                onPressed: widget.request.hasUrl
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

    if (playback.kind == ResolvedMediaKind.nativeStream &&
        _error == null &&
        widget.request.mediaType == PlayMediaType.video &&
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

    if (playback.kind == ResolvedMediaKind.nativeStream &&
        widget.request.mediaType == PlayMediaType.audio &&
        _player != null) {
      return _buildAudioSurface(context);
    }

    if (playback.kind == ResolvedMediaKind.embeddedWeb &&
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
          child: widget.request.thumbnailUrl.isNotEmpty
              ? Image.network(
                  widget.request.thumbnailUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Center(
                    child: Icon(Icons.play_circle_outline, size: 72),
                  ),
                )
              : Center(
                  child: Icon(
                    widget.request.mediaType == PlayMediaType.audio
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
                child: widget.request.thumbnailUrl.isNotEmpty
                    ? Image.network(
                        widget.request.thumbnailUrl,
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
