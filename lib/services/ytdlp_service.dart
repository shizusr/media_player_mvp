import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'app_exception.dart';
import 'settings_service.dart';

class ResolvedStream {
  const ResolvedStream({
    required this.videoUrl,
    this.audioUrl,
    this.qualityLabel,
    this.availableHeights = const [],
    this.youtubeId,
  });

  final String videoUrl;

  /// Set when video and audio are separate streams (typical for 1080p+).
  final String? audioUrl;
  final String? qualityLabel;

  /// Video heights offered by the site, highest first (for the quality menu).
  final List<int> availableHeights;

  /// Set only for YouTube videos (used by SponsorBlock).
  final String? youtubeId;
}

class SourceMeta {
  const SourceMeta({
    required this.title,
    this.thumbnailUrl,
    required this.stream,
  });

  final String title;
  final String? thumbnailUrl;
  final ResolvedStream stream;
}

class _CacheEntry {
  _CacheEntry(this.stream) : time = DateTime.now();

  final ResolvedStream stream;
  final DateTime time;
}

/// Talks to the external yt-dlp program. Direct stream links are never stored
/// in the database: they expire, so they are fetched again when a video opens.
class YtDlpService {
  YtDlpService(this._settings);

  final SettingsService _settings;
  final Map<String, _CacheEntry> _cache = {};

  static const Duration _cacheTtl = Duration(minutes: 30);

  String get _executable {
    final path = _settings.ytDlpPath.trim();
    return path.isEmpty ? 'yt-dlp' : path;
  }

  String _formatFor(int height) {
    return 'bv*[height<=$height][vcodec^=avc1]+ba'
        '/bv*[height<=$height]+ba'
        '/b[height<=$height]'
        '/b';
  }

  String _cacheKey(String url, int height) => '$url|$height';

  void clearCache() => _cache.clear();

  /// Returns yt-dlp's version string, or throws [AppException].
  Future<String> version() async {
    final ProcessResult result;
    try {
      result = await Process.run(
        _executable,
        ['--version'],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      ).timeout(const Duration(seconds: 15));
    } on ProcessException {
      throw const AppException(_notFoundMessage);
    } on TimeoutException {
      throw const AppException('yt-dlp did not respond in time.');
    }
    if (result.exitCode != 0) {
      throw AppException(_errorText(result.stderr as String));
    }
    return (result.stdout as String).trim();
  }

  /// Title, cover URL and a fresh stream for a page link.
  Future<SourceMeta> fetchMeta(String url) async {
    final height = _settings.maxQuality;
    final data = _unwrap(await _fetchJson(url, height));
    final stream = _parseStream(data);
    _cache[_cacheKey(url, height)] = _CacheEntry(stream);

    final title = (data['title'] as String?)?.trim();
    return SourceMeta(
      title: (title == null || title.isEmpty) ? Uri.parse(url).host : title,
      thumbnailUrl: data['thumbnail'] as String?,
      stream: stream,
    );
  }

  /// A playable stream for a page link (cached for 30 minutes).
  /// [maxHeight] overrides the quality limit from Settings (quality menu).
  Future<ResolvedStream> resolve(
    String url, {
    bool force = false,
    int? maxHeight,
  }) async {
    final height = maxHeight ?? _settings.maxQuality;
    final key = _cacheKey(url, height);
    if (!force) {
      final cached = _cache[key];
      if (cached != null && DateTime.now().difference(cached.time) < _cacheTtl) {
        return cached.stream;
      }
    }
    final data = _unwrap(await _fetchJson(url, height));
    final stream = _parseStream(data);
    _cache[key] = _CacheEntry(stream);
    return stream;
  }

  static const String _notFoundMessage =
      'yt-dlp was not found. Install it (winget install yt-dlp.yt-dlp), '
      'restart the app, or set the full path in Settings.';

  Future<Map<String, dynamic>> _fetchJson(String url, int height) async {
    final ProcessResult result;
    try {
      result = await Process.run(
        _executable,
        [
          '-J',
          '--no-playlist',
          '--no-warnings',
          '--encoding',
          'utf-8',
          '-f',
          _formatFor(height),
          url,
        ],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      ).timeout(const Duration(seconds: 90));
    } on ProcessException {
      throw const AppException(_notFoundMessage);
    } on TimeoutException {
      throw const AppException('yt-dlp took too long to respond.');
    }

    if (result.exitCode != 0) {
      throw AppException(_errorText(result.stderr as String));
    }

    try {
      final decoded = jsonDecode(result.stdout as String);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } on FormatException {
      // Falls through to the error below.
    }
    throw const AppException('yt-dlp returned data the app cannot read.');
  }

  Map<String, dynamic> _unwrap(Map<String, dynamic> root) {
    final entries = root['entries'];
    if (entries is List && entries.isNotEmpty && entries.first is Map) {
      return Map<String, dynamic>.from(entries.first as Map);
    }
    return root;
  }

  List<int> _availableHeights(Map<String, dynamic> data) {
    final formats = data['formats'];
    final heights = <int>{};
    if (formats is List) {
      for (final f in formats) {
        if (f is! Map) continue;
        final vcodec = f['vcodec'];
        final height = f['height'];
        if (vcodec != null && vcodec != 'none' && height is num && height > 0) {
          heights.add(height.toInt());
        }
      }
    }
    final list = heights.toList()..sort((a, b) => b.compareTo(a));
    return list;
  }

  ResolvedStream _parseStream(Map<String, dynamic> data) {
    String? videoUrl;
    String? audioUrl;
    int? height;

    final requested = data['requested_formats'];
    if (requested is List && requested.length >= 2) {
      final formats = requested
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();

      bool hasVideo(Map<String, dynamic> f) =>
          f['vcodec'] != null && f['vcodec'] != 'none';
      bool hasAudio(Map<String, dynamic> f) =>
          f['acodec'] != null && f['acodec'] != 'none';

      final video = formats.firstWhere(hasVideo, orElse: () => formats.first);
      final audio = formats.firstWhere(
        (f) => hasAudio(f) && !hasVideo(f),
        orElse: () => formats.last,
      );

      videoUrl = video['url'] as String?;
      audioUrl = audio['url'] as String?;
      height = (video['height'] as num?)?.toInt();
    } else {
      videoUrl = data['url'] as String?;
      height = (data['height'] as num?)?.toInt();
    }

    if (videoUrl == null || videoUrl.isEmpty) {
      throw const AppException('No playable stream was found for this link.');
    }

    String? youtubeId;
    final extractor = (data['extractor_key'] as String?)?.toLowerCase();
    if (extractor == 'youtube' && data['id'] is String) {
      youtubeId = data['id'] as String;
    }

    return ResolvedStream(
      videoUrl: videoUrl,
      audioUrl: audioUrl,
      qualityLabel: height != null ? '${height}p' : null,
      availableHeights: _availableHeights(data),
      youtubeId: youtubeId,
    );
  }

  String _errorText(String stderr) {
    final lines = stderr
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty) return 'yt-dlp failed with an unknown error.';

    final line = lines.lastWhere(
      (l) => l.startsWith('ERROR'),
      orElse: () => lines.last,
    );
    var text = line.replaceFirst(RegExp(r'^ERROR:\s*'), '');
    if (text.length > 300) {
      text = '${text.substring(0, 300)}...';
    }
    return text;
  }
}
