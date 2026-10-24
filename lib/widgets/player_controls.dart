import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../utils/format.dart';

const List<double> kPlaybackSpeeds = [
  0.5,
  0.75,
  1.0,
  1.25,
  1.5,
  1.75,
  2.0,
  2.5,
  3.0,
];

/// Data shared between the player screen and its on-screen controls.
class PlayerUiModel extends ChangeNotifier {
  double speed = 1.0;
  int? selectedHeight;
  String? qualityLabel;
  List<int> heights = const [];
  String? notice;
  String title = '';

  void refresh() => notifyListeners();
}

String _speedText(double s) {
  return s == s.roundToDouble() ? s.toStringAsFixed(0) : s.toString();
}

/// Custom controls: seek bar, volume, speed, quality, fullscreen and hotkeys.
/// Built through Video(controls: ...) so they also work in fullscreen.
class PlayerControls extends StatefulWidget {
  const PlayerControls({
    super.key,
    required this.state,
    required this.model,
    required this.onSpeedChanged,
    required this.onQualityChanged,
  });

  final VideoState state;
  final PlayerUiModel model;
  final ValueChanged<double> onSpeedChanged;
  final ValueChanged<int?> onQualityChanged;

  @override
  State<PlayerControls> createState() => _PlayerControlsState();
}

class _PlayerControlsState extends State<PlayerControls> {
  static const TextStyle _white = TextStyle(color: Colors.white, fontSize: 13);

  Timer? _hideTimer;
  StreamSubscription<bool>? _playingSub;
  bool _visible = true;
  double? _dragValue;
  double _lastVolume = 100;

  Player get _player => widget.state.widget.controller.player;

  @override
  void initState() {
    super.initState();
    _poke();
    _playingSub = _player.stream.playing.listen((_) {
      if (mounted) _poke();
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _playingSub?.cancel();
    super.dispose();
  }

  // ------------------------------------------------------------- visibility

  void _poke() {
    if (!_visible) setState(() => _visible = true);
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _player.state.playing && _dragValue == null) {
        setState(() => _visible = false);
      }
    });
  }

  // ---------------------------------------------------------------- actions

  void _togglePlay() {
    _player.playOrPause();
    _poke();
  }

  void _seekBy(int seconds) {
    final max = _player.state.duration;
    var target = _player.state.position + Duration(seconds: seconds);
    if (target < Duration.zero) target = Duration.zero;
    if (max > Duration.zero && target > max) target = max;
    _player.seek(target);
    _poke();
  }

  void _seekToFraction(double fraction) {
    final total = _player.state.duration;
    if (total <= Duration.zero) return;
    _player.seek(
      Duration(milliseconds: (total.inMilliseconds * fraction).round()),
    );
    _poke();
  }

  void _changeVolume(double delta) {
    final next = (_player.state.volume + delta).clamp(0.0, 100.0).toDouble();
    _player.setVolume(next);
    _poke();
  }

  void _toggleMute() {
    final current = _player.state.volume;
    if (current > 0) {
      _lastVolume = current;
      _player.setVolume(0);
    } else {
      _player.setVolume(_lastVolume > 0 ? _lastVolume : 100);
    }
    _poke();
  }

  void _stepSpeed(int direction) {
    var index = 0;
    var best = double.infinity;
    for (var i = 0; i < kPlaybackSpeeds.length; i++) {
      final diff = (kPlaybackSpeeds[i] - widget.model.speed).abs();
      if (diff < best) {
        best = diff;
        index = i;
      }
    }
    final next = (index + direction).clamp(0, kPlaybackSpeeds.length - 1).toInt();
    widget.onSpeedChanged(kPlaybackSpeeds[next]);
    _poke();
  }

  void _toggleFullscreen() {
    widget.state.toggleFullscreen();
  }

  Future<void> _exitFullscreen() async {
    try {
      await widget.state.exitFullscreen();
    } catch (_) {
      // Not in fullscreen: nothing to do.
    }
  }

  Future<void> _selectQuality(int value) async {
    // Switching quality rebuilds the player, so leave fullscreen first.
    await _exitFullscreen();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    widget.onQualityChanged(value == 0 ? null : value);
  }

  Map<ShortcutActivator, VoidCallback> _bindings() {
    const digits = <LogicalKeyboardKey>[
      LogicalKeyboardKey.digit0,
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit6,
      LogicalKeyboardKey.digit7,
      LogicalKeyboardKey.digit8,
      LogicalKeyboardKey.digit9,
    ];

    final map = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.space): _togglePlay,
      const SingleActivator(LogicalKeyboardKey.keyK): _togglePlay,
      const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _seekBy(-5),
      const SingleActivator(LogicalKeyboardKey.arrowRight): () => _seekBy(5),
      const SingleActivator(LogicalKeyboardKey.keyJ): () => _seekBy(-10),
      const SingleActivator(LogicalKeyboardKey.keyL): () => _seekBy(10),
      const SingleActivator(LogicalKeyboardKey.arrowUp): () => _changeVolume(5),
      const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
          _changeVolume(-5),
      const SingleActivator(LogicalKeyboardKey.keyM): _toggleMute,
      const SingleActivator(LogicalKeyboardKey.keyF): _toggleFullscreen,
      const SingleActivator(LogicalKeyboardKey.escape): _exitFullscreen,
      const SingleActivator(LogicalKeyboardKey.bracketLeft): () =>
          _stepSpeed(-1),
      const SingleActivator(LogicalKeyboardKey.bracketRight): () =>
          _stepSpeed(1),
      const SingleActivator(LogicalKeyboardKey.backspace): () =>
          widget.onSpeedChanged(1.0),
    };

    for (var i = 0; i < digits.length; i++) {
      map[SingleActivator(digits[i])] = () => _seekToFraction(i / 10);
    }
    return map;
  }

  // ----------------------------------------------------------------- widgets

  SliderThemeData _sliderTheme(BuildContext context) {
    return SliderTheme.of(context).copyWith(
      trackHeight: 3,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
      activeTrackColor: Colors.redAccent,
      thumbColor: Colors.redAccent,
      inactiveTrackColor: Colors.white30,
    );
  }

  Widget _seekBar(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: _player.stream.duration,
      initialData: _player.state.duration,
      builder: (context, durationSnap) {
        final duration = durationSnap.data ?? Duration.zero;
        return StreamBuilder<Duration>(
          stream: _player.stream.position,
          initialData: _player.state.position,
          builder: (context, positionSnap) {
            final totalMs = duration.inMilliseconds.toDouble();
            final max = totalMs > 0 ? totalMs : 1.0;
            final posMs =
                (positionSnap.data ?? Duration.zero).inMilliseconds.toDouble();
            final value = (_dragValue ?? posMs).clamp(0.0, max).toDouble();

            return Row(
              children: [
                SizedBox(
                  width: 52,
                  child: Text(formatMs(value.round()), style: _white),
                ),
                Expanded(
                  child: ExcludeFocus(
                    child: SliderTheme(
                      data: _sliderTheme(context),
                      child: Slider(
                        value: value,
                        min: 0,
                        max: max,
                        onChanged: totalMs > 0
                            ? (v) {
                                setState(() => _dragValue = v);
                                _poke();
                              }
                            : null,
                        onChangeEnd: (v) {
                          _player.seek(Duration(milliseconds: v.round()));
                          setState(() => _dragValue = null);
                          _poke();
                        },
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 52,
                  child: Text(
                    formatDuration(duration),
                    textAlign: TextAlign.end,
                    style: _white,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _volume(BuildContext context) {
    return StreamBuilder<double>(
      stream: _player.stream.volume,
      initialData: _player.state.volume,
      builder: (context, snap) {
        final volume = (snap.data ?? 100.0).clamp(0.0, 100.0).toDouble();
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Mute (M)',
              color: Colors.white,
              onPressed: _toggleMute,
              icon: Icon(
                volume == 0
                    ? Icons.volume_off
                    : (volume < 50 ? Icons.volume_down : Icons.volume_up),
              ),
            ),
            SizedBox(
              width: 90,
              child: ExcludeFocus(
                child: SliderTheme(
                  data: _sliderTheme(context),
                  child: Slider(
                    value: volume,
                    min: 0,
                    max: 100,
                    onChanged: (v) {
                      _player.setVolume(v);
                      _poke();
                    },
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _speedMenu() {
    return PopupMenuButton<double>(
      tooltip: 'Playback speed ([ and ])',
      onSelected: widget.onSpeedChanged,
      itemBuilder: (context) => [
        for (final s in kPlaybackSpeeds)
          CheckedPopupMenuItem<double>(
            value: s,
            checked: s == widget.model.speed,
            child: Text('${_speedText(s)}x'),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Text(
          '${_speedText(widget.model.speed)}x',
          style: _white.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Widget _qualityMenu() {
    final model = widget.model;
    return PopupMenuButton<int>(
      tooltip: 'Quality',
      onSelected: _selectQuality,
      itemBuilder: (context) => [
        CheckedPopupMenuItem<int>(
          value: 0,
          checked: model.selectedHeight == null,
          child: const Text('Auto'),
        ),
        for (final h in model.heights)
          CheckedPopupMenuItem<int>(
            value: h,
            checked: model.selectedHeight == h,
            child: Text('${h}p'),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.hd_outlined, color: Colors.white, size: 20),
            const SizedBox(width: 4),
            Text(model.qualityLabel ?? 'Auto', style: _white),
          ],
        ),
      ),
    );
  }

  Widget _bottomBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 28, 12, 8),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _seekBar(context),
          Row(
            children: [
              StreamBuilder<bool>(
                stream: _player.stream.playing,
                initialData: _player.state.playing,
                builder: (context, snap) {
                  final playing = snap.data ?? false;
                  return IconButton(
                    tooltip: 'Play / pause (Space)',
                    color: Colors.white,
                    onPressed: _togglePlay,
                    icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                  );
                },
              ),
              IconButton(
                tooltip: 'Back 10 s (J)',
                color: Colors.white,
                onPressed: () => _seekBy(-10),
                icon: const Icon(Icons.replay_10),
              ),
              IconButton(
                tooltip: 'Forward 10 s (L)',
                color: Colors.white,
                onPressed: () => _seekBy(10),
                icon: const Icon(Icons.forward_10),
              ),
              _volume(context),
              const Spacer(),
              ListenableBuilder(
                listenable: widget.model,
                builder: (context, _) {
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _speedMenu(),
                      if (widget.model.heights.isNotEmpty) _qualityMenu(),
                    ],
                  );
                },
              ),
              IconButton(
                tooltip: 'Fullscreen (F)',
                color: Colors.white,
                onPressed: _toggleFullscreen,
                icon: const Icon(Icons.fullscreen),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _topBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      child: Text(
        widget.model.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _notice() {
    return ListenableBuilder(
      listenable: widget.model,
      builder: (context, _) {
        final text = widget.model.notice;
        if (text == null) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(text, style: _white),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: _bindings(),
      child: Focus(
        autofocus: true,
        child: MouseRegion(
          cursor: _visible ? MouseCursor.defer : SystemMouseCursors.none,
          onHover: (_) => _poke(),
          child: Stack(
            fit: StackFit.expand,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _togglePlay,
                onDoubleTap: _toggleFullscreen,
                child: const SizedBox.expand(),
              ),
              Center(
                child: StreamBuilder<bool>(
                  stream: _player.stream.buffering,
                  initialData: _player.state.buffering,
                  builder: (context, snap) {
                    if (snap.data ?? false) {
                      return const CircularProgressIndicator();
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ),
              Positioned(left: 16, bottom: 96, child: _notice()),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: AnimatedOpacity(
                  opacity: _visible ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: IgnorePointer(ignoring: !_visible, child: _topBar()),
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: AnimatedOpacity(
                  opacity: _visible ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: IgnorePointer(
                    ignoring: !_visible,
                    child: _bottomBar(context),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
