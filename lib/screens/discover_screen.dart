import 'package:flutter/material.dart';

import '../models/yt_models.dart';
import '../services/app_exception.dart';
import '../services/app_services.dart';
import '../widgets/topics_dialog.dart';
import '../widgets/yt_video_card.dart';

/// Home: latest from subscriptions plus a Discover feed built from the
/// user's own interests.
class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({
    super.key,
    required this.services,
    required this.onOpenSubscriptions,
  });

  final AppServices services;
  final VoidCallback onOpenSubscriptions;

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  late final YtActions _actions = YtActions(widget.services);

  List<YtVideo> _videos = [];
  bool _loading = false;
  bool _hasTopics = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final topics = await widget.services.store.topics();
      _hasTopics = topics.isNotEmpty;
      final list = await widget.services.discover.discover();
      if (!mounted) return;
      setState(() => _videos = list);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is AppException ? e.message : 'Could not load videos: $e';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editTopics() async {
    final changed = await showTopicsDialog(context, widget.services.store);
    if (changed) _load();
  }

  Widget _subscriptionsStrip() {
    final subs = widget.services.subscriptions;
    return ListenableBuilder(
      listenable: subs,
      builder: (context, _) {
        final items = subs.visibleFeed.take(12).toList();
        final muted = Theme.of(context).colorScheme.onSurfaceVariant;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'From your subscriptions',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                  TextButton(
                    onPressed: widget.onOpenSubscriptions,
                    child: const Text('See all'),
                  ),
                ],
              ),
            ),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  subs.channels.isEmpty
                      ? 'Subscribe to channels to see their latest videos here.'
                      : 'No new videos yet.',
                  style: TextStyle(color: muted),
                ),
              )
            else
              SizedBox(
                height: 260 * 9 / 16 + 92,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    final video = items[index];
                    return SizedBox(
                      width: 260,
                      child: YtVideoCard(
                        services: widget.services,
                        video: video,
                        isNew: subs.isNew(video),
                        onTap: () => _actions.play(context, items, index),
                        onAction: (action) => _actions.handle(
                          context,
                          action,
                          video,
                          list: items,
                          index: index,
                          onHidden: () => setState(() {}),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
        actions: [
          IconButton(
            tooltip: 'Your interests',
            icon: const Icon(Icons.tune),
            onPressed: _editTopics,
          ),
          IconButton(
            tooltip: 'Show different videos',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _subscriptionsStrip()),
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Discover',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          if (_loading)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
            )
          else if (_error != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!, textAlign: TextAlign.center),
              ),
            )
          else if (!_hasTopics)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Text(
                      'Tell the app what you like and it will build your own home feed.\n'
                      'Unlike YouTube, it never repeats videos you have already seen.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: muted),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _editTopics,
                      icon: const Icon(Icons.tune),
                      label: const Text('Choose interests'),
                    ),
                  ],
                ),
              ),
            )
          else if (_videos.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Nothing found right now. Try refreshing or add more interests.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else
            ytVideoSliverGrid(
              services: widget.services,
              actions: _actions,
              videos: _videos,
              onHidden: () => setState(() {
                _videos = _videos
                    .where((v) => !widget.services.store.isHidden(v))
                    .toList();
              }),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}
