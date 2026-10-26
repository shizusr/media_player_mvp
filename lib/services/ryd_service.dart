import 'dart:convert';

import 'http_helper.dart';

class RydStats {
  const RydStats({required this.likes, required this.dislikes});

  final int likes;
  final int dislikes;
}

/// Return YouTube Dislike: estimated dislike counts from a public API.
class RydService {
  Future<RydStats?> fetch(String videoId) async {
    final body = await httpGetString(
      Uri.https('returnyoutubedislikeapi.com', '/votes', {'videoId': videoId}),
      timeout: const Duration(seconds: 8),
    );
    if (body == null) return null;
    try {
      final data = jsonDecode(body);
      if (data is! Map) return null;
      final likes = (data['likes'] as num?)?.toInt();
      final dislikes = (data['dislikes'] as num?)?.toInt();
      if (likes == null || dislikes == null) return null;
      return RydStats(likes: likes, dislikes: dislikes);
    } catch (_) {
      return null;
    }
  }
}
