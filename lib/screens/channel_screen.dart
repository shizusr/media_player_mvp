import 'package:flutter/material.dart';

import '../models/yt_models.dart';
import '../services/app_exception.dart';
import '../services/app_services.dart';
import '../widgets/yt_video_card.dart';

class ChannelScreen extends StatefulWidget {
  const ChannelScreen({
    super.key,
    required this.services,
    required this.channelId,
    required this.name,
  });

  final AppServices services;
  final String channelId;
  final String name;

  @override
  State<ChannelScreen> createState() => _ChannelScreenState();
}

class _ChannelScreenState extends State<ChannelScreen> {
  late final YtActions _actions = YtActions(widget.services);

  List<YtVideo> _videos = [];
  String _name = '';
  bool _loading = true;
  String? _error;
  int _count = 30;
  bool _popular = false;

  @override
  void initState() {
    super.initState();
    _name = widget.name;
    _load();
  }

  Future<void> _load({bool more = false}) async {
    setState(() {
      _loading = true;
      _error = null;
      if (more) _count += 30;
    });
    try {
      final page = await widget.services.ytdlp
          .channelVideos(widget.channelId, count: _count);
      if (!mounted) return;
      setState(() {
        _videos = page.videos;
        _name = page.name;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is AppException ? e.message : 'Could not load the channel: $e';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<YtVideo> get _shown {
    final list = _videos.where((v) => !widget.services.store.isHidden(v)).toList();
    if (_popular) {
      list.sort((a, b) => (b.views ?? 0).compareTo(a.views ?? 0));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final subscriptions = widget.services.subscriptions;
    final shown = _shown;

    return Scaffold(
      appBar: AppBar(
        title: Text(_name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          ListenableBuilder(
            listenable: subscriptions,
            builder: (context, _) {
              final subscribed = subscriptions.isSubscribed(widget.channelId);
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: FilledButton.tonal(
                  onPressed: () {
                    if (subscribed) {
                      subscriptions.unsubscribe(widget.channelId);
                    } else {
                      subscriptions.subscribe(
                        YtChannel(
                          channelId: widget.channelId,
                          name: _name,
                          subscribedAt: DateTime.now(),
                        ),
                      );
                    }
                  },
                  child: Text(subscribed ? 'Subscribed' : 'Subscribe'),
                ),
              );
            },
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Latest'),
                    selected: !_popular,
                    onSelected: (_) => setState(() => _popular = false),
                  ),
                  ChoiceChip(
                    label: const Text('Most viewed (loaded)'),
                    selected: _popular,
                    onSelected: (_) => setState(() => _popular = true),
                  ),
                ],
              ),
            ),
          ),
          if (_error != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!, textAlign: TextAlign.center),
              ),
            ),
          ytVideoSliverGrid(
            services: widget.services,
            actions: _actions,
            videos: shown,
            onHidden: () => setState(() {}),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: _loading
                    ? const CircularProgressIndicator()
                    : (_videos.length >= _count
                        ? OutlinedButton(
                            onPressed: () => _load(more: true),
                            child: const Text('Load more'),
                          )
                        : const SizedBox.shrink()),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
