import 'package:flutter/foundation.dart';

import '../models/yt_models.dart';
import 'database_service.dart';
import 'feed_service.dart';
import 'yt_store.dart';

/// Channels the user follows and the chronological feed built from them.
class SubscriptionsController extends ChangeNotifier {
  SubscriptionsController({
    required this.db,
    required this.store,
    required this.feedService,
  });

  final DatabaseService db;
  final YtStore store;
  final FeedService feedService;

  List<YtChannel> _channels = [];
  List<YtVideo> _feed = [];
  bool _refreshing = false;
  DateTime? _lastRefresh;
  int _lastSeenMs = 0;

  List<YtChannel> get channels => _channels;
  bool get refreshing => _refreshing;

  List<YtVideo> get visibleFeed {
    return _feed.where((v) => !store.isHidden(v)).toList();
  }

  Future<void> load() async {
    _channels = await store.channels();
    _feed = await store.feedItems();

    final saved = int.tryParse(await db.getSetting('feed_last_seen') ?? '');
    if (saved == null) {
      _lastSeenMs = DateTime.now().millisecondsSinceEpoch;
      await db.setSetting('feed_last_seen', _lastSeenMs.toString());
    } else {
      _lastSeenMs = saved;
    }
    notifyListeners();
  }

  bool isSubscribed(String? channelId) {
    if (channelId == null) return false;
    return _channels.any((c) => c.channelId == channelId);
  }

  bool isNew(YtVideo v) {
    final published = v.publishedAt;
    return published != null && published.millisecondsSinceEpoch > _lastSeenMs;
  }

  int get unseenCount => visibleFeed.where(isNew).length;

  Future<void> markSeen() async {
    _lastSeenMs = DateTime.now().millisecondsSinceEpoch;
    await db.setSetting('feed_last_seen', _lastSeenMs.toString());
    notifyListeners();
  }

  Future<void> subscribe(YtChannel channel) async {
    if (isSubscribed(channel.channelId)) return;
    await store.upsertChannel(channel);
    _channels = await store.channels();
    notifyListeners();
    await _refreshChannels([channel]);
  }

  Future<void> unsubscribe(String channelId) async {
    await store.deleteChannel(channelId);
    _channels = await store.channels();
    _feed = await store.feedItems();
    notifyListeners();
  }

  /// Adds channels from an import file. Returns how many were new.
  Future<int> importChannels(List<YtChannel> imported) async {
    final existing = _channels.map((c) => c.channelId).toSet();
    final fresh = <YtChannel>[];
    for (final c in imported) {
      if (existing.add(c.channelId)) {
        await store.upsertChannel(c);
        fresh.add(c);
      }
    }
    _channels = await store.channels();
    notifyListeners();
    if (fresh.isNotEmpty) {
      await _refreshChannels(fresh);
    }
    return fresh.length;
  }

  Future<void> refreshFeed({bool force = false}) async {
    if (_refreshing || _channels.isEmpty) return;
    final last = _lastRefresh;
    if (!force &&
        last != null &&
        DateTime.now().difference(last) < const Duration(minutes: 20)) {
      return;
    }
    await _refreshChannels([..._channels]);
    _lastRefresh = DateTime.now();
  }

  Future<void> _refreshChannels(List<YtChannel> list) async {
    if (_refreshing) return;
    _refreshing = true;
    notifyListeners();
    try {
      for (var i = 0; i < list.length; i += 4) {
        final chunk = list.skip(i).take(4).toList();
        final results = await Future.wait(chunk.map(feedService.fetchChannel));
        for (final items in results) {
          await store.upsertFeed(items);
        }
      }
      _feed = await store.feedItems();
    } finally {
      _refreshing = false;
      notifyListeners();
    }
  }
}
