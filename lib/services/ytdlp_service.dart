import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/yt_models.dart';
import 'app_exception.dart';
import 'settings_service.dart';

class ResolvedStream {
  const ResolvedStream({
    required this.videoUrl,
    this.audioUrl,
    this.qualityLabel,
    this.availableHeights = const [],
    this.youtubeId,
    this.details,
  });

  final String videoUrl;

  /// Set when video and audio are separate streams (typical for 1080p+).
  final String? audioUrl;
  final String? qualityLabel;

  /// Video heights offered by the site, highest first (for the quality menu).
  final List<int> availableHeights;

  /// Set only for YouTube videos (used by SponsorBlock and dislikes).
  final String? youtubeId;

  /// Description, channel, chapters, subtitles, counters.
  final VideoDetails? details;
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
  static const String _notFoundMessage =
      'yt-dlp was not found. Install it (winget install yt-dlp.yt-dlp), '
      'restart the app, or set the full path in Settings.';

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

  // ------------------------------------------------------------------ process

  Future<Map<String, dynamic>> _runJson(
    List<String> args, {
    Duration timeout = const Duration(seconds: 90),
  }) async {
    final ProcessResult result;
    try {
      result = await Process.run(
        _executable,
        args,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      ).timeout(timeout);
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

  // ------------------------------------------------------------ single video

  Future<Map<String, dynamic>> _fetchVideoJson(String url, int height) {
    return _runJson([
      '-J',
      '--no-playlist',
      '--no-warnings',
      '--encoding',
      'utf-8',
      '-f',
      _formatFor(height),
      url,
    ]);
  }

  /// Title, cover URL and a fresh stream for a page link.
  Future<SourceMeta> fetchMeta(String url) async {
    final height = _settings.maxQuality;
    final data = _unwrap(await _fetchVideoJson(url, height));
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
    final data = _unwrap(await _fetchVideoJson(url, height));
    final stream = _parseStream(data);
    _cache[key] = _CacheEntry(stream);
    return stream;
  }

  // --------------------------------------------------- search, channels, lists

  static const List<String> _flat = [
    '-J',
    '--flat-playlist',
    '--no-warnings',
    '--encoding',
    'utf-8',
  ];

  /// YouTube search. [offset] skips the first results (used by Discover to
  /// get different slices of the same topic).
  Future<List<YtVideo>> search(
    String query, {
    int count = 20,
    int offset = 0,
    bool byDate = false,
  }) async {
    final prefix = byDate ? 'ytsearchdate' : 'ytsearch';
    final total = offset + count;
    final data = await _runJson([
      ..._flat,
      if (offset > 0) ...['--playlist-items', '${offset + 1}-$total'],
      '$prefix$total:$query',
    ]);
    return _parseEntries(data);
  }

  Future<ChannelPageData> channelVideos(String channelId, {int count = 30}) async {
    final data = await _runJson([
      ..._flat,
      '--playlist-end',
      '$count',
      'https://www.youtube.com/channel/$channelId/videos',
    ]);
    final name = _channelName(data) ?? channelId;
    return ChannelPageData(
      channelId: channelId,
      name: name,
      videos: _parseEntries(
        data,
        defaultChannelName: name,
        defaultChannelId: channelId,
      ),
    );
  }

  Future<PlaylistInfo> playlist(String url, {int max = 300}) async {
    final data = await _runJson([..._flat, '--playlist-end', '$max', url]);
    final title = (data['title'] as String?)?.trim();
    return PlaylistInfo(
      title: (title == null || title.isEmpty) ? 'Playlist' : title,
      videos: _parseEntries(data),
    );
  }

  /// Accepts a channel link, @handle, bare channel id or a video link.
  Future<YtChannel> resolveChannel(String input) async {
    final text = input.trim();
    final String url;
    if (RegExp(r'^UC[0-9A-Za-z_-]{22}$').hasMatch(text)) {
      url = 'https://www.youtube.com/channel/$text';
    } else if (text.startsWith('@')) {
      url = 'https://www.youtube.com/$text';
    } else if (text.startsWith('http://') || text.startsWith('https://')) {
      url = text;
    } else {
      throw const AppException(
        'Enter a channel link, an @handle or a channel id (UC...).',
      );
    }

    final data = await _runJson([..._flat, '--playlist-end', '1', url]);

    String? id;
    for (final key in ['channel_id', 'uploader_id', 'id']) {
      final value = data[key];
      if (value is String && RegExp(r'^UC[0-9A-Za-z_-]{22}$').hasMatch(value)) {
        id = value;
        break;
      }
    }
    if (id == null) {
      throw const AppException('Could not find a channel at this address.');
    }

    return YtChannel(
      channelId: id,
      name: _channelName(data) ?? id,
      subscribedAt: DateTime.now(),
    );
  }

  String? _channelName(Map<String, dynamic> data) {
    for (final key in ['channel', 'uploader']) {
      final value = data[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    final title = data['title'];
    if (title is String && title.trim().isNotEmpty) {
      return title.replaceFirst(RegExp(r'\s*-\s*Videos$'), '').trim();
    }
    return null;
  }

  List<YtVideo> _parseEntries(
    Map<String, dynamic> data, {
    String? defaultChannelName,
    String? defaultChannelId,
  }) {
    final entries = data['entries'];
    final out = <YtVideo>[];
    if (entries is List) {
      for (final e in entries) {
        if (e is! Map) continue;
        final video = _entryToVideo(
          Map<String, dynamic>.from(e),
          defaultChannelName,
          defaultChannelId,
        );
        if (video != null) out.add(video);
      }
    }
    return out;
  }

  YtVideo? _entryToVideo(
    Map<String, dynamic> e,
    String? defaultChannelName,
    String? defaultChannelId,
  ) {
    final id = e['id'];
    if (id is! String || id.length != 11) return null;

    final ieKey = (e['ie_key'] as String?)?.toLowerCase();
    if (ieKey != null && ieKey != 'youtube') return null;

    final title = (e['title'] as String?)?.trim();
    if (title == null || title.isEmpty) return null;

    DateTime? published;
    final timestamp = e['timestamp'];
    final uploadDate = e['upload_date'];
    if (timestamp is num) {
      published = DateTime.fromMillisecondsSinceEpoch(timestamp.toInt() * 1000);
    } else if (uploadDate is String && uploadDate.length == 8) {
      published = DateTime.tryParse(
        '${uploadDate.substring(0, 4)}-${uploadDate.substring(4, 6)}-${uploadDate.substring(6, 8)}',
      );
    }

    final url = (e['url'] as String?) ?? '';
    final channelName = (e['channel'] ?? e['uploader']) as String?;
    final channelId = e['channel_id'] as String?;

    return YtVideo(
      id: id,
      title: title,
      channelName: channelName ?? defaultChannelName,
      channelId: channelId ?? defaultChannelId,
      durationSec: (e['duration'] as num?)?.toInt(),
      views: (e['view_count'] as num?)?.toInt(),
      publishedAt: published,
      isShort: url.contains('/shorts/'),
    );
  }

  // ----------------------------------------------------------------- parsing

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

  List<Chapter> _chapters(Map<String, dynamic> data) {
    final raw = data['chapters'];
    final out = <Chapter>[];
    if (raw is List) {
      for (final c in raw) {
        if (c is! Map) continue;
        final start = (c['start_time'] as num?)?.toDouble();
        final end = (c['end_time'] as num?)?.toDouble();
        final title = c['title'];
        if (start == null || end == null || title is! String) continue;
        out.add(Chapter(start: start, end: end, title: title));
      }
    }
    return out;
  }

  List<SubtitleOption> _subtitles(Map<String, dynamic> data) {
    final out = <SubtitleOption>[];

    void collect(Object? map, bool auto) {
      if (map is! Map) return;
      map.forEach((lang, formats) {
        if (lang is! String || formats is! List) return;
        if (lang == 'live_chat') return;
        if (auto && !(lang == 'en' || lang == 'ru' || lang.endsWith('-orig'))) {
          return;
        }

        Map? pick;
        for (final wanted in const ['vtt', 'srt', 'ass']) {
          for (final f in formats) {
            if (f is Map && f['ext'] == wanted && f['url'] is String) {
              pick = f;
              break;
            }
          }
          if (pick != null) break;
        }
        if (pick == null) return;

        final name = (pick['name'] as String?) ?? lang;
        out.add(
          SubtitleOption(
            label: auto ? '$name (auto)' : name,
            lang: lang,
            url: pick['url'] as String,
            auto: auto,
          ),
        );
      });
    }

    collect(data['subtitles'], false);
    collect(data['automatic_captions'], true);
    return out;
  }

  VideoDetails _details(Map<String, dynamic> data) {
    return VideoDetails(
      title: (data['title'] as String?) ?? '',
      description: data['description'] as String?,
      channel: (data['channel'] ?? data['uploader']) as String?,
      channelId: data['channel_id'] as String?,
      viewCount: (data['view_count'] as num?)?.toInt(),
      likeCount: (data['like_count'] as num?)?.toInt(),
      uploadDate: data['upload_date'] as String?,
      durationSec: (data['duration'] as num?)?.toInt(),
      chapters: _chapters(data),
      subtitles: _subtitles(data),
    );
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
      details: _details(data),
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
