import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../models/video_item.dart';
import '../models/yt_models.dart';
import '../services/app_exception.dart';
import '../services/app_services.dart';
import '../services/sponsorblock_service.dart';
import '../services/ytdlp_service.dart';
import '../utils/format.dart';
import '../widgets/player_controls.dart';
import '../widgets/video_info_dialog.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.video,
    required this.services,
    this.queue = const [],
    this.queueIndex = 0,
  });

  final VideoItem video;
  final AppServices services;

  /// Videos that play after this one (autoplay). May be empty.
  final List<VideoItem> queue;
  final int queueIndex;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late Player _player;
  late VideoController _controller;
  int _generation = 0;

  late VideoItem _video;
  List<VideoItem> _queue = const [];
  int _index = 0;

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
  bool _switching = false;
  bool _tracksApplied = false;

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
    _video = widget.video;
    _queue = widget.queue.isEmpty ? [widget.video] : widget.queue;
    _index = widget.queueIndex.clamp(0, _queue.length - 1).toInt();
    _ui
      ..title = _video.title
      ..hasNext = _index < _queue.length - 1
      ..hasPrev = _index > 0;

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
    _tracksApplied = false;
    player.setVolume(_services.settings.volume);

    _subs
      ..add(player.stream.position.listen(_onPosition))
      ..add(player.stream.duration.listen((d) {
        if (d > Duration.zero) _durationMs = d.inMilliseconds;
      }))
      ..add(player.stream.completed.listen(_onCompleted))
      ..add(player.stream.volume.listen(_onVolume))
      ..add(player.stream.tracks.listen(_onTracks));
  }

  void _cancelSubs() {
    for (final sub in _subs) {
      sub.cancel();
    }
    _subs.clear();
  }

  /// Quality or video changes use a brand new player: it is the most reliable
  /// way to reload both the video and the separate audio stream.
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
    final current = _services.library.byId(_video.id) ?? _video;
    if (current.watched || current.positionMs <= 5000) return 0;
    final back = current.positionMs - 3000;
    return back > 0 ? back : 0;
  }

  Future<void> _load({bool force = false, int? startAtMs}) async {
    final video = _video;
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
          _ui
            ..qualityLabel = stream.qualityLabel
            ..heights = stream.availableHeights
            ..selectedHeight = _selectedHeight
            ..details = stream.details
            ..chapters = stream.details?.chapters ?? const []
            ..subtitleOptions = stream.details?.subtitles ?? const []
            ..refresh();
          _maybeLoadSponsorBlock(stream);
          _maybeLoadRating(stream);
          await _openAndPlay(
            stream.videoUrl,
            audioUrl: stream.audioUrl,
            resumeMs: resume,
            subtitles: stream.details?.subtitles ?? const [],
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

  Future<void> _waitForLoaded(Player player) async {
    if (player.state.duration > Duration.zero) return;
    await player.stream.duration
        .firstWhere((d) => d > Duration.zero)
        .timeout(const Duration(seconds: 15));
  }

  SubtitleOption? _preferredSubtitle(List<SubtitleOption> options) {
    final pref = _services.settings.subLang;
    if (pref == 'off') return null;
    for (final auto in const [false, true]) {
      for (final o in options) {
        if (o.auto == auto && _langMatches(o.lang, pref)) return o;
      }
    }
    return null;
  }

  Future<void> _openAndPlay(
    String url, {
    String? audioUrl,
    int resumeMs = 0,
    List<SubtitleOption> subtitles = const [],
  }) async {
    if (_disposed) return;
    final player = _player;
    final subtitle = _preferredSubtitle(subtitles);
    final needsSetup = audioUrl != null || resumeMs > 0 || subtitle != null;

    await player.open(Media(url), play: !needsSetup);

    if (needsSetup) {
      try {
        await _waitForLoaded(player);
        final platform = player.platform;
        if (platform is NativePlayer && !_disposed) {
          // High quality YouTube streams carry video and audio separately.
          if (audioUrl != null) {
            await platform.command(['audio-add', audioUrl, 'select']);
          }
          if (subtitle != null) {
            await platform.command(
              ['sub-add', subtitle.url, 'select', subtitle.label, subtitle.lang],
            );
          }
        }
        if (resumeMs > 0 && !_disposed) {
          await player.seek(Duration(milliseconds: resumeMs));
        }
      } catch (_) {
        // Play anyway: a missing track or resume point is not fatal.
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

  // ------------------------------------------------------------ tracks

  bool _langMatches(String? code, String pref) {
    if (code == null) return false;
    final c = code.toLowerCase();
    const names = {
      'ru': ['ru', 'rus', 'russian'],
      'en': ['en', 'eng', 'english'],
    };
    return (names[pref] ?? [pref]).contains(c) || c.startsWith('$pref-');
  }

  /// Applies the preferred audio and subtitle language once, when the file's
  /// own tracks become known (movies with several dubs or subtitle tracks).
  void _onTracks(Tracks tracks) {
    if (_tracksApplied || _disposed) return;

    final audio = tracks.audio.where((t) => t.id != 'auto' && t.id != 'no').toList();
    final subs = tracks.subtitle.where((t) => t.id != 'auto' && t.id != 'no').toList();
    if (audio.isEmpty && subs.isEmpty) return;
    _tracksApplied = true;

    final settings = _services.settings;
    if (settings.audioLang != 'auto') {
      for (final t in audio) {
        if (_langMatches(t.language, settings.audioLang)) {
          _player.setAudioTrack(t);
          break;
        }
      }
    }
    if (settings.subLang != 'off') {
      for (final t in subs) {
        if (_langMatches(t.language, settings.subLang)) {
          _player.setSubtitleTrack(t);
          break;
        }
      }
    }
  }

  // ---------------------------------------------------------------- progress

  void _onPosition(Duration position) {
    if (!_tracking) return;
    _positionMs = position.inMilliseconds;
    _checkSponsor();
  }

  void _onCompleted(bool done) {
    if (!done || !_tracking) return;
    _finished = true;
    _saveProgress();
    if (_services.settings.autoplayNext && _ui.hasNext) {
      _playIndex(_index + 1);
    }
  }

  void _saveProgress() {
    final id = _video.id;
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

  // ------------------------------------------------- sponsorblock and rating

  void _maybeLoadSponsorBlock(ResolvedStream stream) {
    final settings = _services.settings;
    final id = stream.youtubeId;
    if (_segmentsRequested || !settings.sponsorBlock || id == null) return;

    _segmentsRequested = true;
    _services.sponsorBlock.fetch(id, settings.sponsorCategories).then((list) {
      if (!_disposed) _segments = list;
    });
  }

  void _maybeLoadRating(ResolvedStream stream) {
    final id = stream.youtubeId;
    if (!_services.settings.returnDislike || id == null) return;

    final current = _video;
    _services.ryd.fetch(id).then((stats) {
      if (_disposed || stats == null || !identical(current, _video)) return;
      _ui.ratingText =
          '\u{1F44D} ${formatViews(stats.likes)}  \u{1F44E} ${formatViews(stats.dislikes)}';
      _ui.refresh();
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

  // --------------------------------------------- speed, quality, queue, info

  void _setSpeed(double value) {
    _ui.speed = value;
    _ui.refresh();
    _player.setRate(value);
  }

  Future<void> _changeQuality(int? height) async {
    if (_switching || _disposed) return;
    _switching = true;

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
      _switching = false;
    }
  }

  Future<void> _playIndex(int index) async {
    if (_switching || _disposed || index < 0 || index >= _queue.length) return;
    _switching = true;

    try {
      _saveProgress();
      _index = index;
      _video = _queue[index];
      _segments = const [];
      _skipped.clear();
      _segmentsRequested = false;
      _selectedHeight = null;
      _ui
        ..resetForVideo(_video.title)
        ..hasNext = _index < _queue.length - 1
        ..hasPrev = _index > 0
        ..refresh();

      if (mounted) {
        setState(() {
          _loading = true;
          _error = null;
        });
      }
      _replacePlayer();
      await _load();
    } finally {
      _switching = false;
    }
  }

  void _showInfo() {
    final details = _ui.details;
    if (details == null || !mounted) return;
    showVideoInfo(context, _services, details, _ui.ratingText);
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
          _video.title,
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
              onNext: () => _playIndex(_index + 1),
              onPrev: () => _playIndex(_index - 1),
              onShowInfo: _showInfo,
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
                  Wrap(
                    spacing: 8,
                    children: [
                      if (_video.source == VideoSource.web)
                        FilledButton.icon(
                          onPressed: _retry,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Try again'),
                        ),
                      if (_ui.hasNext)
                        OutlinedButton.icon(
                          onPressed: () => _playIndex(_index + 1),
                          icon: const Icon(Icons.skip_next),
                          label: const Text('Next video'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
