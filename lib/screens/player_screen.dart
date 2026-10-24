import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../models/video_item.dart';
import '../services/app_exception.dart';
import '../services/app_services.dart';
import '../services/sponsorblock_service.dart';
import '../services/ytdlp_service.dart';
import '../widgets/player_controls.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.video, required this.services});

  final VideoItem video;
  final AppServices services;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late Player _player;
  late VideoController _controller;
  int _generation = 0;

  final List<StreamSubscription<dynamic>> _subs = [];
  final PlayerUiModel _ui = PlayerUiModel();

  Timer? _saveTimer;
  Timer? _volumeTimer;
  Timer? _noticeTimer;

  bool _loading = true;
  String? _error;
  bool _disposed = false;
  bool _tracking = false;
  bool _finished = false;
  bool _changingQuality = false;

  int _positionMs = 0;
  int _durationMs = 0;
  int? _selectedHeight;

  List<SponsorSegment> _segments = const [];
  final Set<int> _skipped = {};
  bool _segmentsRequested = false;

  AppServices get _services => widget.services;

  @override
  void initState() {
    super.initState();
    _ui.title = widget.video.title;
    _createPlayer();
    _saveTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _saveProgress(),
    );
    _load();
  }

  @override
  void dispose() {
    _disposed = true;
    _saveTimer?.cancel();
    _volumeTimer?.cancel();
    _noticeTimer?.cancel();

    _saveProgress();
    _services.settings.rememberVolume(_player.state.volume);
    _cancelSubs();

    // Redraw the library after this frame (progress bars, "Continue watching").
    scheduleMicrotask(_services.library.refresh);

    _ui.dispose();
    _player.dispose();
    super.dispose();
  }

  // ----------------------------------------------------------------- player

  void _createPlayer() {
    final player = Player();
    _player = player;
    _controller = VideoController(player);
    player.setVolume(_services.settings.volume);

    _subs
      ..add(player.stream.position.listen(_onPosition))
      ..add(player.stream.duration.listen((d) {
        if (d > Duration.zero) _durationMs = d.inMilliseconds;
      }))
      ..add(player.stream.completed.listen((done) {
        if (done && _tracking) {
          _finished = true;
          _saveProgress();
        }
      }))
      ..add(player.stream.volume.listen(_onVolume));
  }

  void _cancelSubs() {
    for (final sub in _subs) {
      sub.cancel();
    }
    _subs.clear();
  }

  /// Quality changes use a brand new player: it is the most reliable way to
  /// reload both the video and the separate audio stream.
  void _replacePlayer() {
    _cancelSubs();
    final old = _player;
    _tracking = false;
    _finished = false;
    _positionMs = 0;
    _durationMs = 0;
    setState(() {
      _createPlayer();
      _generation++;
    });
    WidgetsBinding.instance.endOfFrame.then((_) => old.dispose());
  }

  // --------------------------------------------------------------- loading

  int _resumePositionMs() {
    final current = _services.library.byId(widget.video.id) ?? widget.video;
    if (current.watched || current.positionMs <= 5000) return 0;
    final back = current.positionMs - 3000;
    return back > 0 ? back : 0;
  }

  Future<void> _load({bool force = false, int? startAtMs}) async {
    final video = widget.video;
    try {
      final resume = startAtMs ?? _resumePositionMs();

      switch (video.source) {
        case VideoSource.local:
          if (!File(video.originalUrl).existsSync()) {
            throw AppException(
              'File not found. It may have been moved or deleted:\n${video.originalUrl}',
            );
          }
          await _openAndPlay(video.originalUrl, resumeMs: resume);
        case VideoSource.direct:
          await _openAndPlay(video.originalUrl, resumeMs: resume);
        case VideoSource.web:
          // Direct stream links expire, so always ask yt-dlp for a fresh one.
          final stream = await _services.ytdlp.resolve(
            video.originalUrl,
            force: force,
            maxHeight: _selectedHeight,
          );
          if (_disposed) return;
          _ui.qualityLabel = stream.qualityLabel;
          _ui.heights = stream.availableHeights;
          _ui.selectedHeight = _selectedHeight;
          _ui.refresh();
          _maybeLoadSponsorBlock(stream);
          await _openAndPlay(
            stream.videoUrl,
            audioUrl: stream.audioUrl,
            resumeMs: resume,
          );
      }

      if (mounted) setState(() => _loading = false);
    } on AppException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not start playback: $e';
        });
      }
    }
  }

  Future<void> _openAndPlay(
    String url, {
    String? audioUrl,
    int resumeMs = 0,
  }) async {
    if (_disposed) return;
    final player = _player;
    final needsSetup = audioUrl != null || resumeMs > 0;

    await player.open(Media(url), play: !needsSetup);

    if (needsSetup) {
      try {
        if (player.state.duration <= Duration.zero) {
          await player.stream.duration
              .firstWhere((d) => d > Duration.zero)
              .timeout(const Duration(seconds: 15));
        }
        // High quality YouTube streams carry video and audio separately.
        final platform = player.platform;
        if (audioUrl != null && platform is NativePlayer && !_disposed) {
          await platform.command(['audio-add', audioUrl, 'select']);
        }
        if (resumeMs > 0 && !_disposed) {
          await player.seek(Duration(milliseconds: resumeMs));
        }
      } catch (_) {
        // Play anyway: a missing audio track or resume point is not fatal.
      }
      if (_disposed) return;
      await player.play();
    }

    if (_disposed) return;
    if (_ui.speed != 1.0) {
      await player.setRate(_ui.speed);
    }
    final knownDuration = player.state.duration.inMilliseconds;
    if (knownDuration > 0) _durationMs = knownDuration;
    _tracking = true;
  }

  void _retry() {
    setState(() {
      _loading = true;
      _error = null;
    });
    _load(force: true, startAtMs: _positionMs > 0 ? _positionMs : null);
  }

  // ---------------------------------------------------------------- progress

  void _onPosition(Duration position) {
    if (!_tracking) return;
    _positionMs = position.inMilliseconds;
    _checkSponsor();
  }

  void _saveProgress() {
    final id = widget.video.id;
    if (id == null || !_tracking || _durationMs <= 0) return;
    unawaited(
      _services.library
          .saveProgress(
            id,
            positionMs: _positionMs,
            durationMs: _durationMs,
            finished: _finished,
          )
          .catchError((Object _) {}),
    );
  }

  void _onVolume(double volume) {
    _volumeTimer?.cancel();
    _volumeTimer = Timer(const Duration(milliseconds: 600), () {
      _services.settings.rememberVolume(volume);
    });
  }

  // ------------------------------------------------------------- sponsorblock

  void _maybeLoadSponsorBlock(ResolvedStream stream) {
    final settings = _services.settings;
    final id = stream.youtubeId;
    if (_segmentsRequested || !settings.sponsorBlock || id == null) return;

    _segmentsRequested = true;
    _services.sponsorBlock.fetch(id, settings.sponsorCategories).then((list) {
      if (!_disposed) _segments = list;
    });
  }

  void _checkSponsor() {
    if (_segments.isEmpty) return;
    final seconds = _positionMs / 1000.0;

    for (var i = 0; i < _segments.length; i++) {
      if (_skipped.contains(i)) continue;
      final segment = _segments[i];
      if (seconds >= segment.start && seconds < segment.end - 0.3) {
        _skipped.add(i);
        _player.seek(Duration(milliseconds: (segment.end * 1000).round()));
        _showNotice(
          'Skipped ${segment.label.toLowerCase()} '
          '(${(segment.end - segment.start).round()} s)',
        );
        break;
      }
    }
  }

  void _showNotice(String text) {
    if (_disposed) return;
    _ui.notice = text;
    _ui.refresh();
    _noticeTimer?.cancel();
    _noticeTimer = Timer(const Duration(seconds: 3), () {
      if (_disposed) return;
      _ui.notice = null;
      _ui.refresh();
    });
  }

  // ------------------------------------------------------- speed and quality

  void _setSpeed(double value) {
    _ui.speed = value;
    _ui.refresh();
    _player.setRate(value);
  }

  Future<void> _changeQuality(int? height) async {
    if (_changingQuality || _disposed) return;
    _changingQuality = true;

    final startMs = _positionMs;
    try {
      _selectedHeight = height;
      if (mounted) {
        setState(() {
          _loading = true;
          _error = null;
        });
      }
      _replacePlayer();
      await _load(startAtMs: startMs);
    } finally {
      _changingQuality = false;
    }
  }

  // ------------------------------------------------------------------- build

  Widget _overlay(Widget child) {
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          widget.video.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Video(
            key: ValueKey(_generation),
            controller: _controller,
            controls: (state) => PlayerControls(
              state: state,
              model: _ui,
              onSpeedChanged: _setSpeed,
              onQualityChanged: _changeQuality,
            ),
          ),
          if (_loading)
            _overlay(
              const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text(
                    'Getting a fresh stream link...',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
          if (_error != null)
            _overlay(
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 40,
                    color: Colors.redAccent,
                  ),
                  const SizedBox(height: 12),
                  SelectableText(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 16),
                  if (widget.video.source == VideoSource.web)
                    FilledButton.icon(
                      onPressed: _retry,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try again'),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
