import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/video_item.dart';
import '../models/yt_models.dart';
import '../screens/channel_screen.dart';
import '../screens/player_screen.dart';
import '../services/app_exception.dart';
import '../services/app_services.dart';
import '../utils/format.dart';

enum YtMenuAction {
  play,
  addToLibrary,
  openChannel,
  subscribe,
  unsubscribe,
  hideVideo,
  hideChannel,
}

/// Shared behaviour of YouTube cards: play, add, subscribe, hide.
class YtActions {
  YtActions(this.services);

  final AppServices services;

  void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  VideoItem playable(YtVideo v) {
    return services.library.byUrl(v.url) ??
        VideoItem(
          source: VideoSource.web,
          originalUrl: v.url,
          title: v.title,
          thumbnailUrl: v.coverUrl,
          addedAt: DateTime.now(),
        );
  }

  /// Opens the player on [list][index]; the rest of the list becomes the
  /// autoplay queue.
  void play(BuildContext context, List<YtVideo> list, int index) {
    final queue = list.map(playable).toList();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          video: queue[index],
          services: services,
          queue: queue,
          queueIndex: index,
        ),
      ),
    );
  }

  void openChannel(BuildContext context, String channelId, String name) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChannelScreen(
          services: services,
          channelId: channelId,
          name: name,
        ),
      ),
    );
  }

  Future<void> handle(
    BuildContext context,
    YtMenuAction action,
    YtVideo video, {
    required List<YtVideo> list,
    required int index,
    VoidCallback? onHidden,
  }) async {
    final channelId = video.channelId;
    final channelName = video.channelName ?? 'Channel';

    try {
      switch (action) {
        case YtMenuAction.play:
          play(context, list, index);
        case YtMenuAction.addToLibrary:
          await services.library.addWebVideo(
            url: video.url,
            title: video.title,
            thumbnailUrl: video.coverUrl,
          );
          if (context.mounted) _toast(context, 'Added to library');
        case YtMenuAction.openChannel:
          if (channelId != null) openChannel(context, channelId, channelName);
        case YtMenuAction.subscribe:
          if (channelId == null) {
            _toast(context, 'The channel of this video is unknown.');
            return;
          }
          await services.subscriptions.subscribe(
            YtChannel(
              channelId: channelId,
              name: channelName,
              subscribedAt: DateTime.now(),
            ),
          );
          if (context.mounted) _toast(context, 'Subscribed to $channelName');
        case YtMenuAction.unsubscribe:
          if (channelId != null) {
            await services.subscriptions.unsubscribe(channelId);
            if (context.mounted) _toast(context, 'Unsubscribed from $channelName');
          }
        case YtMenuAction.hideVideo:
          await services.store.hideVideo(video.id);
          onHidden?.call();
        case YtMenuAction.hideChannel:
          if (channelId != null) {
            await services.store.hideChannel(channelId);
            onHidden?.call();
            if (context.mounted) {
              _toast(context, 'Hidden: $channelName (Settings can undo this)');
            }
          }
      }
    } catch (e) {
      if (context.mounted) {
        _toast(context, e is AppException ? e.message : 'Something went wrong: $e');
      }
    }
  }
}

List<PopupMenuEntry<YtMenuAction>> ytMenuItems(AppServices services, YtVideo v) {
  final subscribed = services.subscriptions.isSubscribed(v.channelId);
  final inLibrary = services.library.byUrl(v.url) != null;
  final hasChannel = v.channelId != null;

  return [
    const PopupMenuItem(value: YtMenuAction.play, child: Text('Play')),
    if (!inLibrary)
      const PopupMenuItem(
        value: YtMenuAction.addToLibrary,
        child: Text('Add to library'),
      ),
    if (hasChannel)
      const PopupMenuItem(
        value: YtMenuAction.openChannel,
        child: Text('Open channel'),
      ),
    if (hasChannel)
      PopupMenuItem(
        value: subscribed ? YtMenuAction.unsubscribe : YtMenuAction.subscribe,
        child: Text(subscribed ? 'Unsubscribe' : 'Subscribe'),
      ),
    const PopupMenuDivider(),
    const PopupMenuItem(
      value: YtMenuAction.hideVideo,
      child: Text('Not interested'),
    ),
    if (hasChannel)
      const PopupMenuItem(
        value: YtMenuAction.hideChannel,
        child: Text('Hide this channel'),
      ),
  ];
}

class YtThumb extends StatelessWidget {
  const YtThumb({super.key, required this.video, this.isNew = false});

  final YtVideo video;
  final bool isNew;

  Widget _badge(String text, Color background) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final duration = video.durationSec;

    return Container(
      color: scheme.surfaceContainerHighest,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            video.thumbnailUrl,
            fit: BoxFit.cover,
            cacheWidth: 480,
            errorBuilder: (_, __, ___) => Icon(
              Icons.play_circle_outline,
              size: 40,
              color: scheme.onSurfaceVariant,
            ),
          ),
          if (duration != null && duration > 0)
            Positioned(
              right: 6,
              bottom: 6,
              child: _badge(
                formatDuration(Duration(seconds: duration)),
                Colors.black87,
              ),
            ),
          if (isNew)
            Positioned(
              left: 6,
              top: 6,
              child: _badge('NEW', Colors.redAccent),
            ),
        ],
      ),
    );
  }
}

String ytMetaLine(YtVideo v) {
  return [
    if (v.views != null) '${formatViews(v.views!)} views',
    if (v.publishedAt != null) timeAgo(v.publishedAt!),
  ].join(' \u2022 ');
}

class YtVideoCard extends StatelessWidget {
  const YtVideoCard({
    super.key,
    required this.services,
    required this.video,
    required this.onTap,
    required this.onAction,
    this.isNew = false,
  });

  final AppServices services;
  final YtVideo video;
  final VoidCallback onTap;
  final ValueChanged<YtMenuAction> onAction;
  final bool isNew;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = TextStyle(fontSize: 12, color: scheme.onSurfaceVariant);
    final meta = ytMetaLine(video);

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
              child: YtThumb(video: video, isNew: isNew),
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
                          if (video.channelName != null)
                            Text(
                              video.channelName!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: muted,
                            ),
                          if (meta.isNotEmpty)
                            Text(
                              meta,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: muted,
                            ),
                        ],
                      ),
                    ),
                    PopupMenuButton<YtMenuAction>(
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.more_vert, size: 20),
                      tooltip: 'More',
                      onSelected: onAction,
                      itemBuilder: (context) => ytMenuItems(services, video),
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

class YtVideoTile extends StatelessWidget {
  const YtVideoTile({
    super.key,
    required this.services,
    required this.video,
    required this.onTap,
    required this.onAction,
  });

  final AppServices services;
  final YtVideo video;
  final VoidCallback onTap;
  final ValueChanged<YtMenuAction> onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = TextStyle(fontSize: 12, color: scheme.onSurfaceVariant);
    final meta = ytMetaLine(video);

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerHigh,
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            SizedBox(
              width: 200,
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: YtThumb(video: video),
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
                    if (video.channelName != null)
                      Text(
                        video.channelName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: muted,
                      ),
                    if (meta.isNotEmpty)
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: muted,
                      ),
                  ],
                ),
              ),
            ),
            PopupMenuButton<YtMenuAction>(
              icon: const Icon(Icons.more_vert, size: 20),
              tooltip: 'More',
              onSelected: onAction,
              itemBuilder: (context) => ytMenuItems(services, video),
            ),
          ],
        ),
      ),
    );
  }
}

/// A responsive grid of YouTube cards for use inside a CustomScrollView.
Widget ytVideoSliverGrid({
  required AppServices services,
  required YtActions actions,
  required List<YtVideo> videos,
  VoidCallback? onHidden,
  bool Function(YtVideo video)? isNew,
  double maxExtent = 300,
}) {
  return SliverLayoutBuilder(
    builder: (context, constraints) {
      const padding = 12.0;
      const gap = 12.0;
      final available = constraints.crossAxisExtent - padding * 2;
      final columns =
          math.max(1, ((available + gap) / (maxExtent + gap)).ceil());
      final itemWidth = (available - gap * (columns - 1)) / columns;

      return SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: padding),
        sliver: SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: gap,
            mainAxisSpacing: gap,
            mainAxisExtent: itemWidth * 9 / 16 + 92,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final video = videos[index];
              return YtVideoCard(
                key: ValueKey(video.id),
                services: services,
                video: video,
                isNew: isNew?.call(video) ?? false,
                onTap: () => actions.play(context, videos, index),
                onAction: (action) => actions.handle(
                  context,
                  action,
                  video,
                  list: videos,
                  index: index,
                  onHidden: onHidden,
                ),
              );
            },
            childCount: videos.length,
          ),
        ),
      );
    },
  );
}
