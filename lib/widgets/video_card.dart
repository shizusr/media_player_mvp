import 'dart:io';

import 'package:flutter/material.dart';

import '../models/video_item.dart';
import '../utils/format.dart';

enum VideoMenuAction { edit, refresh, toggleWatched, delete }

List<PopupMenuEntry<VideoMenuAction>> _menuItems(VideoItem video) {
  return [
    const PopupMenuItem(value: VideoMenuAction.edit, child: Text('Edit')),
    PopupMenuItem(
      value: VideoMenuAction.toggleWatched,
      child: Text(video.watched ? 'Mark as unwatched' : 'Mark as watched'),
    ),
    if (video.source == VideoSource.web)
      const PopupMenuItem(
        value: VideoMenuAction.refresh,
        child: Text('Refresh title and cover'),
      ),
    const PopupMenuItem(value: VideoMenuAction.delete, child: Text('Delete')),
  ];
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, this.color);

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Cover image with source badge, "watched" check and progress bar on top.
class VideoCover extends StatelessWidget {
  const VideoCover({super.key, required this.video});

  final VideoItem video;

  Widget _placeholder(ColorScheme scheme) {
    return Container(
      color: scheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(
        video.source == VideoSource.local
            ? Icons.video_file_outlined
            : Icons.play_circle_outline,
        size: 40,
        color: scheme.onSurfaceVariant,
      ),
    );
  }

  Widget _image(ColorScheme scheme) {
    final path = video.thumbnailPath;
    if (path == null) {
      final url = video.thumbnailUrl;
      if (url == null) return _placeholder(scheme);
      return Image.network(
        url,
        fit: BoxFit.cover,
        cacheWidth: 640,
        errorBuilder: (_, __, ___) => _placeholder(scheme),
      );
    }
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      cacheWidth: 640,
      errorBuilder: (_, __, ___) => _placeholder(scheme),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Widget? badge;
    if (video.source == VideoSource.local) {
      final missing = !File(video.originalUrl).existsSync();
      badge = missing
          ? const _Badge('FILE MISSING', Colors.redAccent)
          : const _Badge('LOCAL', Colors.white);
    } else if (video.source == VideoSource.direct) {
      badge = const _Badge('DIRECT', Colors.white);
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        _image(scheme),
        if (badge != null) Positioned(left: 6, bottom: 10, child: badge),
        if (video.watched)
          Positioned(
            top: 6,
            right: 6,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(
                color: Colors.black87,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check, size: 14, color: Colors.greenAccent),
            ),
          ),
        if (video.inProgress)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: LinearProgressIndicator(
              value: video.progress,
              minHeight: 4,
              backgroundColor: Colors.black54,
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.redAccent),
            ),
          ),
      ],
    );
  }
}

class VideoCard extends StatelessWidget {
  const VideoCard({
    super.key,
    required this.video,
    required this.categoryName,
    required this.onTap,
    required this.onAction,
  });

  final VideoItem video;
  final String? categoryName;
  final VoidCallback onTap;
  final ValueChanged<VideoMenuAction> onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerHigh,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: VideoCover(video: video),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 4, 0, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            video.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (categoryName != null)
                            Text(
                              categoryName!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                    PopupMenuButton<VideoMenuAction>(
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.more_vert, size: 20),
                      tooltip: 'More',
                      onSelected: onAction,
                      itemBuilder: (context) => _menuItems(video),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class VideoListTile extends StatelessWidget {
  const VideoListTile({
    super.key,
    required this.video,
    required this.categoryName,
    required this.onTap,
    required this.onAction,
  });

  final VideoItem video;
  final String? categoryName;
  final VoidCallback onTap;
  final ValueChanged<VideoMenuAction> onAction;

  String? _statusText() {
    if (video.watched) return 'Watched';
    if (video.inProgress) {
      return '${formatMs(video.positionMs)} / ${formatMs(video.durationMs)}';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = TextStyle(fontSize: 12, color: scheme.onSurfaceVariant);
    final status = _statusText();

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerHigh,
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            SizedBox(
              width: 170,
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: VideoCover(video: video),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      video.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (categoryName != null) categoryName!,
                        if (status != null) status,
                      ].join('  -  '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: muted,
                    ),
                  ],
                ),
              ),
            ),
            PopupMenuButton<VideoMenuAction>(
              icon: const Icon(Icons.more_vert, size: 20),
              tooltip: 'More',
              onSelected: onAction,
              itemBuilder: (context) => _menuItems(video),
            ),
          ],
        ),
      ),
    );
  }
}
