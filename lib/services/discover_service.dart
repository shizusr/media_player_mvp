import 'dart:math';

import '../models/yt_models.dart';
import 'yt_store.dart';
import 'ytdlp_service.dart';

/// Builds a home feed from the user's own interests. Unlike YouTube's
/// recommendations it never repeats what was already shown, and every refresh
/// takes a different slice of the search results.
class DiscoverService {
  DiscoverService({required this.ytdlp, required this.store});

  final YtDlpService ytdlp;
  final YtStore store;
  final Random _random = Random();

  Future<List<YtVideo>> discover({int limit = 24}) async {
    final topics = await store.topics();
    if (topics.isEmpty) return const [];

    final shuffled = [...topics]..shuffle(_random);
    final chosen = shuffled.take(3).toList();

    final futures = <Future<List<YtVideo>>>[
      for (final topic in chosen)
        ytdlp
            .search(topic.query, count: 15, offset: _random.nextInt(4) * 10)
            .catchError((Object _) => <YtVideo>[]),
      // One extra look at the newest uploads for a random interest.
      ytdlp
          .search(chosen.first.query, count: 8, byDate: true)
          .catchError((Object _) => <YtVideo>[]),
    ];
    final batches = await Future.wait(futures);

    final merged = <String, YtVideo>{};
    for (final batch in batches) {
      for (final v in batch) {
        if (v.isShort || store.isHidden(v)) continue;
        merged.putIfAbsent(v.id, () => v);
      }
    }

    final seen = await store.seen();
    var fresh = merged.values.where((v) => !seen.contains(v.id)).toList();
    if (fresh.length < limit ~/ 2) {
      // Everything was shown already: start a new round.
      await store.clearSeen();
      fresh = merged.values.toList();
    }

    fresh.shuffle(_random);
    final result = fresh.take(limit).toList();
    await store.markSeen(result.map((v) => v.id));
    return result;
  }
}
