import 'package:flutter/material.dart';

import '../models/yt_models.dart';
import '../services/app_services.dart';
import '../widgets/subscription_tools.dart';
import '../widgets/yt_video_card.dart';

class SubscriptionsScreen extends StatefulWidget {
  const SubscriptionsScreen({super.key, required this.services});

  final AppServices services;

  @override
  State<SubscriptionsScreen> createState() => _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends State<SubscriptionsScreen> {
  late final YtActions _actions = YtActions(widget.services);
  String? _channelFilter;

  @override
  Widget build(BuildContext context) {
    final subs = widget.services.subscriptions;

    return ListenableBuilder(
      listenable: subs,
      builder: (context, _) {
        final feed = subs.visibleFeed
            .where((v) => _channelFilter == null || v.channelId == _channelFilter)
            .toList();

        return Scaffold(
          appBar: AppBar(
            title: const Text('Subscriptions'),
            actions: [
              IconButton(
                tooltip: 'Refresh',
                icon: subs.refreshing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                onPressed:
                    subs.refreshing ? null : () => subs.refreshFeed(force: true),
              ),
              IconButton(
                tooltip: 'Mark all as seen',
                icon: const Icon(Icons.done_all),
                onPressed: subs.markSeen,
              ),
              IconButton(
                tooltip: 'Your channels',
                icon: const Icon(Icons.people_outline),
                onPressed: () => showChannelsDialog(
                  context,
                  widget.services,
                  (id, name) => _actions.openChannel(context, id, name),
                ),
              ),
              IconButton(
                tooltip: 'Subscribe to a channel',
                icon: const Icon(Icons.person_add_alt),
                onPressed: () => addChannelFlow(context, widget.services),
              ),
              IconButton(
                tooltip: 'Import subscriptions',
                icon: const Icon(Icons.upload_file_outlined),
                onPressed: () =>
                    importSubscriptionsFlow(context, widget.services),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: subs.channels.isEmpty ? _empty(context) : _feed(subs, feed),
        );
      },
    );
  }

  Widget _empty(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'No subscriptions yet.\n\n'
              'Your feed shows new videos from your channels in plain '
              'chronological order, with no algorithm.',
              textAlign: TextAlign.center,
              style: TextStyle(color: muted),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: () => addChannelFlow(context, widget.services),
                  icon: const Icon(Icons.person_add_alt),
                  label: const Text('Add a channel'),
                ),
                OutlinedButton.icon(
                  onPressed: () =>
                      importSubscriptionsFlow(context, widget.services),
                  icon: const Icon(Icons.upload_file_outlined),
                  label: const Text('Import from file'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Import works with Google Takeout (subscriptions.csv or .json), '
              'NewPipe, FreeTube and OPML exports.',
              textAlign: TextAlign.center,
              style: TextStyle(color: muted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _feed(dynamic subs, List<YtVideo> feed) {
    final channels = widget.services.subscriptions.channels;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: const Text('All channels'),
                    selected: _channelFilter == null,
                    onSelected: (_) => setState(() => _channelFilter = null),
                  ),
                ),
                for (final c in channels)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(c.name),
                      selected: _channelFilter == c.channelId,
                      onSelected: (_) =>
                          setState(() => _channelFilter = c.channelId),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (feed.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                widget.services.subscriptions.refreshing
                    ? 'Loading the latest videos...'
                    : 'No videos yet. Press refresh to check your channels.',
                textAlign: TextAlign.center,
              ),
            ),
          )
        else
          ytVideoSliverGrid(
            services: widget.services,
            actions: _actions,
            videos: feed,
            isNew: widget.services.subscriptions.isNew,
            onHidden: () => setState(() {}),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }
}
