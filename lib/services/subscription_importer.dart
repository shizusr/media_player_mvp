import 'dart:convert';

import '../models/yt_models.dart';

/// Reads subscription exports: Google Takeout (CSV or JSON), NewPipe JSON,
/// FreeTube export, OPML, or any text that contains channel ids (UC...).
class SubscriptionImporter {
  static final RegExp _idPattern = RegExp(r'UC[0-9A-Za-z_-]{22}');

  static List<YtChannel> parse(String raw) {
    final text = raw.replaceFirst('\uFEFF', '').trim();
    final found = <String, String>{};

    void add(String? id, String? name) {
      if (id == null || !RegExp(r'^UC[0-9A-Za-z_-]{22}$').hasMatch(id)) return;
      final clean = (name ?? '').trim();
      found.putIfAbsent(id, () => clean.isEmpty ? id : clean);
    }

    String? idFrom(Object? value) {
      if (value is! String) return null;
      return _idPattern.firstMatch(value)?.group(0);
    }

    void fromList(List<dynamic> list) {
      for (final item in list) {
        if (item is! Map) continue;
        // Google Takeout JSON
        final snippet = item['snippet'];
        if (snippet is Map) {
          final resource = snippet['resourceId'];
          if (resource is Map) {
            add(resource['channelId'] as String?, snippet['title'] as String?);
            continue;
          }
        }
        // FreeTube (id) and NewPipe (url)
        add(idFrom(item['id']) ?? idFrom(item['url']), item['name'] as String?);
      }
    }

    // Whole file as JSON (NewPipe, FreeTube new format, Takeout JSON).
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map && decoded['subscriptions'] is List) {
        fromList(decoded['subscriptions'] as List);
      } else if (decoded is List) {
        fromList(decoded);
      }
    } catch (_) {
      // Not a single JSON document: try the other formats.
    }

    if (found.isEmpty) {
      // FreeTube .db: one JSON object per line.
      for (final line in const LineSplitter().convert(text)) {
        final trimmed = line.trim();
        if (!trimmed.startsWith('{')) continue;
        try {
          final obj = jsonDecode(trimmed);
          if (obj is Map && obj['subscriptions'] is List) {
            fromList(obj['subscriptions'] as List);
          }
        } catch (_) {
          // Skip broken lines.
        }
      }
    }

    if (found.isEmpty && text.toLowerCase().contains('<outline')) {
      // OPML
      for (final tag in RegExp(r'<outline[^>]*>').allMatches(text)) {
        final s = tag.group(0)!;
        final title = RegExp(r'title="([^"]*)"').firstMatch(s)?.group(1);
        add(_idPattern.firstMatch(s)?.group(0), title);
      }
    }

    if (found.isEmpty) {
      // Takeout CSV: "Channel Id,Channel Url,Channel Title".
      for (final line in const LineSplitter().convert(text)) {
        final m = RegExp(r'^(UC[0-9A-Za-z_-]{22}),[^,]*,\s*"?(.*?)"?\s*$')
            .firstMatch(line.trim());
        if (m != null) add(m.group(1), m.group(2));
      }
    }

    if (found.isEmpty) {
      // Last resort: every channel id in the file.
      for (final m in _idPattern.allMatches(text)) {
        add(m.group(0), null);
      }
    }

    final now = DateTime.now();
    return [
      for (final e in found.entries)
        YtChannel(channelId: e.key, name: e.value, subscribedAt: now),
    ];
  }
}
