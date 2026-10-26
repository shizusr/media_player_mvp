import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

import '../models/yt_models.dart';
import 'database_service.dart';

/// Local storage for the YouTube side: subscriptions, feed cache, interests,
/// hidden items, search history and the "already shown" memory of Discover.
class YtStore {
  YtStore(this._db);

  final DatabaseService _db;
  final Set<String> _hiddenVideos = {};
  final Set<String> _hiddenChannels = {};

  ffi.Database get _raw => _db.raw;

  Future<void> load() async {
    final rows = await _raw.query('hidden');
    for (final r in rows) {
      final value = r['value'] as String;
      if (r['kind'] == 'channel') {
        _hiddenChannels.add(value);
      } else {
        _hiddenVideos.add(value);
      }
    }
  }

  // ------------------------------------------------------------------ hidden

  bool isHidden(YtVideo v) {
    if (_hiddenVideos.contains(v.id)) return true;
    final channel = v.channelId;
    return channel != null && _hiddenChannels.contains(channel);
  }

  Future<void> hideVideo(String id) async {
    _hiddenVideos.add(id);
    await _raw.insert(
      'hidden',
      {'kind': 'video', 'value': id},
      conflictAlgorithm: ffi.ConflictAlgorithm.ignore,
    );
  }

  Future<void> hideChannel(String id) async {
    _hiddenChannels.add(id);
    await _raw.insert(
      'hidden',
      {'kind': 'channel', 'value': id},
      conflictAlgorithm: ffi.ConflictAlgorithm.ignore,
    );
  }

  Future<void> clearHidden() async {
    _hiddenVideos.clear();
    _hiddenChannels.clear();
    await _raw.delete('hidden');
  }

  // ---------------------------------------------------------------- channels

  Future<List<YtChannel>> channels() async {
    final rows = await _raw.query('channels', orderBy: 'name COLLATE NOCASE ASC');
    return rows
        .map(
          (r) => YtChannel(
            channelId: r['channel_id'] as String,
            name: r['name'] as String,
            subscribedAt:
                DateTime.fromMillisecondsSinceEpoch(r['subscribed_at'] as int),
          ),
        )
        .toList();
  }

  Future<void> upsertChannel(YtChannel c) async {
    await _raw.insert(
      'channels',
      {
        'channel_id': c.channelId,
        'name': c.name,
        'subscribed_at': c.subscribedAt.millisecondsSinceEpoch,
      },
      conflictAlgorithm: ffi.ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteChannel(String id) async {
    await _raw.delete('channels', where: 'channel_id = ?', whereArgs: [id]);
    await _raw.delete('feed_items', where: 'channel_id = ?', whereArgs: [id]);
  }

  // -------------------------------------------------------------------- feed

  Future<List<YtVideo>> feedItems() async {
    final rows = await _raw.query('feed_items', orderBy: 'published_at DESC');
    return rows
        .map(
          (r) => YtVideo(
            id: r['video_id'] as String,
            title: r['title'] as String,
            channelName: r['channel_name'] as String?,
            channelId: r['channel_id'] as String,
            views: r['views'] as int?,
            publishedAt:
                DateTime.fromMillisecondsSinceEpoch(r['published_at'] as int),
          ),
        )
        .toList();
  }

  Future<void> upsertFeed(List<YtVideo> items) async {
    if (items.isEmpty) return;
    final batch = _raw.batch();
    for (final v in items) {
      final published = v.publishedAt;
      final channel = v.channelId;
      if (published == null || channel == null) continue;
      batch.insert(
        'feed_items',
        {
          'video_id': v.id,
          'channel_id': channel,
          'channel_name': v.channelName,
          'title': v.title,
          'published_at': published.millisecondsSinceEpoch,
          'views': v.views,
        },
        conflictAlgorithm: ffi.ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  // ------------------------------------------------------------------ topics

  Future<List<YtTopic>> topics() async {
    final rows = await _raw.query('topics', orderBy: 'id ASC');
    return rows
        .map((r) => YtTopic(id: r['id'] as int, query: r['query'] as String))
        .toList();
  }

  Future<void> addTopic(String query) async {
    await _raw.insert('topics', {'query': query});
  }

  Future<void> deleteTopic(int id) async {
    await _raw.delete('topics', where: 'id = ?', whereArgs: [id]);
  }

  // ----------------------------------------------------------- search history

  Future<List<String>> searchHistory({int limit = 12}) async {
    final rows = await _raw.query(
      'search_history',
      orderBy: 'used_at DESC',
      limit: limit,
    );
    return rows.map((r) => r['query'] as String).toList();
  }

  Future<void> addSearch(String query) async {
    await _raw.insert(
      'search_history',
      {'query': query, 'used_at': DateTime.now().millisecondsSinceEpoch},
      conflictAlgorithm: ffi.ConflictAlgorithm.replace,
    );
  }

  Future<void> clearSearchHistory() async {
    await _raw.delete('search_history');
  }

  // -------------------------------------------------------------------- seen

  Future<Set<String>> seen() async {
    final rows = await _raw.query('seen', columns: ['video_id']);
    return rows.map((r) => r['video_id'] as String).toSet();
  }

  Future<void> markSeen(Iterable<String> ids) async {
    final batch = _raw.batch();
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final id in ids) {
      batch.insert(
        'seen',
        {'video_id': id, 'seen_at': now},
        conflictAlgorithm: ffi.ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> clearSeen() async {
    await _raw.delete('seen');
  }
}
