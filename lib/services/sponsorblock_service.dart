import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'settings_service.dart';

class SponsorSegment {
  const SponsorSegment({
    required this.start,
    required this.end,
    required this.category,
  });

  /// Seconds from the start of the video.
  final double start;
  final double end;
  final String category;

  String get label => sponsorCategoryLabels[category] ?? category;
}

/// Looks up skippable segments on the public SponsorBlock database.
/// Only the first 4 characters of the video id hash are sent, not the id.
class SponsorBlockService {
  static const String _host = 'sponsor.ajay.app';

  Future<List<SponsorSegment>> fetch(
    String videoId,
    Set<String> categories,
  ) async {
    if (categories.isEmpty) return const [];

    final prefix =
        sha256.convert(utf8.encode(videoId)).toString().substring(0, 4);
    final uri = Uri.https(
      _host,
      '/api/skipSegments/$prefix',
      {'categories': jsonEncode(categories.toList())},
    );

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response =
          await request.close().timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        await response.drain<void>();
        return const [];
      }

      final body = await response.transform(utf8.decoder).join();
      final decoded = jsonDecode(body);
      final result = <SponsorSegment>[];

      if (decoded is List) {
        for (final entry in decoded) {
          if (entry is! Map) continue;
          final segments = entry['segments'];
          if (segments is List) {
            if (entry['videoID'] != videoId) continue;
            for (final s in segments) {
              _addSegment(result, s);
            }
          } else {
            _addSegment(result, entry);
          }
        }
      }

      result.sort((a, b) => a.start.compareTo(b.start));
      return result;
    } catch (_) {
      return const [];
    } finally {
      client.close(force: true);
    }
  }

  void _addSegment(List<SponsorSegment> out, Object? raw) {
    if (raw is! Map) return;

    final action = raw['actionType'];
    if (action != null && action != 'skip') return;

    final segment = raw['segment'];
    if (segment is! List || segment.length < 2) return;

    final start = (segment[0] as num?)?.toDouble();
    final end = (segment[1] as num?)?.toDouble();
    if (start == null || end == null || end <= start) return;

    out.add(
      SponsorSegment(
        start: start,
        end: end,
        category: (raw['category'] as String?) ?? 'sponsor',
      ),
    );
  }
}
