import 'package:flutter/material.dart';

import '../models/yt_models.dart';
import '../screens/channel_screen.dart';
import '../services/app_services.dart';
import '../utils/format.dart';

/// Details of the video being played: channel, counters, chapters, description.
Future<void> showVideoInfo(
  BuildContext context,
  AppServices services,
  VideoDetails details,
  String? ratingText,
) {
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      final channelId = details.channelId;
      final channelName = details.channel ?? 'Unknown channel';
      final uploaded = details.uploadedAt;
      final stats = [
        if (details.viewCount != null) '${formatViews(details.viewCount!)} views',
        if (uploaded != null) 'Uploaded ${timeAgo(uploaded)}',
        if (ratingText != null) ratingText,
        if (details.chapters.isNotEmpty) '${details.chapters.length} chapters',
      ].join(' \u2022 ');

      return AlertDialog(
        title: Text(details.title, maxLines: 3, overflow: TextOverflow.ellipsis),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        channelName,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (channelId != null) ...[
                      TextButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ChannelScreen(
                                services: services,
                                channelId: channelId,
                                name: channelName,
                              ),
                            ),
                          );
                        },
                        child: const Text('Open channel'),
                      ),
                      ListenableBuilder(
                        listenable: services.subscriptions,
                        builder: (context, _) {
                          final subscribed =
                              services.subscriptions.isSubscribed(channelId);
                          return FilledButton.tonal(
                            onPressed: () {
                              if (subscribed) {
                                services.subscriptions.unsubscribe(channelId);
                              } else {
                                services.subscriptions.subscribe(
                                  YtChannel(
                                    channelId: channelId,
                                    name: channelName,
                                    subscribedAt: DateTime.now(),
                                  ),
                                );
                              }
                            },
                            child: Text(subscribed ? 'Subscribed' : 'Subscribe'),
                          );
                        },
                      ),
                    ],
                  ],
                ),
                if (stats.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    stats,
                    style: TextStyle(
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const Divider(height: 24),
                SelectableText(
                  (details.description ?? '').trim().isEmpty
                      ? 'No description.'
                      : details.description!.trim(),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      );
    },
  );
}
