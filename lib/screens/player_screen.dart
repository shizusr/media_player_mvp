import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../models/video_item.dart';

class PlayerScreen extends StatefulWidget {
  final VideoItem video;

  const PlayerScreen({super.key, required this.video});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final Player _player;
  late final VideoController _controller;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);
    _start();
  }

  Future<void> _start() async {
    final audio = widget.video.audioUrl;

    if (audio == null) {
      await _player.open(Media(widget.video.streamUrl), play: true);
      return;
    }

    // Раздельные потоки: открываем видео, ждём загрузки и подключаем звук.
    await _player.open(Media(widget.video.streamUrl), play: false);
    try {
      await _player.stream.duration
          .firstWhere((d) => d > Duration.zero)
          .timeout(const Duration(seconds: 20));
      final platform = _player.platform;
      if (platform is NativePlayer) {
        await platform.command(['audio-add', audio, 'select']);
      }
    } catch (_) {
      // Если звук не подключился, видео всё равно запустится.
    }
    if (mounted) {
      await _player.play();
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
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
      body: SafeArea(
        child: Column(
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Video(controller: _controller),
            ),
            Expanded(
              child: Container(
                width: double.infinity,
                color: Theme.of(context).scaffoldBackgroundColor,
                padding: const EdgeInsets.all(16),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.video.title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (widget.video.qualityLabel != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Quality: ${widget.video.qualityLabel}',
                          style: const TextStyle(color: Colors.white54),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}