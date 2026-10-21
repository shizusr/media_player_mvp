import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/video_item.dart';

class UrlParseException implements Exception {
  final String message;

  const UrlParseException(this.message);

  @override
  String toString() => message;
}

class UrlParserService {
  /// Максимальная высота картинки. Для 4K поставьте 2160.
  static const int maxHeight = 1080;

  Future<VideoItem> parse(String input) async {
    final url = input.trim();
    final uri = Uri.tryParse(url);

    if (url.isEmpty ||
        uri == null ||
        uri.host.isEmpty ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw const UrlParseException(
        'Enter the correct link (http:// или https://)',
      );
    }

    try {
      if (_isDirect(uri)) {
        return _parseDirect(url, uri);
      }
      return await _parseWithYtDlp(url, uri);
    } on UrlParseException {
      rethrow;
    } catch (e) {
      throw UrlParseException('Failed to process link: $e');
    }
  }

  bool _isDirect(Uri uri) {
    final path = uri.path.toLowerCase();
    return path.endsWith('.mp4') ||
        path.endsWith('.m3u8') ||
        path.endsWith('.webm') ||
        path.endsWith('.mkv');
  }

  Future<VideoItem> _parseWithYtDlp(String url, Uri uri) async {
    // Сначала H.264 (легче для процессора), затем любой кодек, затем готовый файл.
    const h = maxHeight;
    final format = 'bv*[height<=$h][vcodec^=avc1]+ba/bv*[height<=$h]+ba/b';

    final ProcessResult result;
    try {
      result = await Process.run(
        'yt-dlp',
        ['-J', '--no-playlist', '--no-warnings', '-f', format, url],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      ).timeout(const Duration(seconds: 90));
    } on ProcessException {
      throw const UrlParseException(
        'yt-dlp not found. Please install yt-dlp: winget install yt-dlp.yt-dlp '
        'and reload terminal.',
      );
    } on TimeoutException {
      throw const UrlParseException('yt-dlp not response.');
    }

    if (result.exitCode != 0) {
      final err = (result.stderr as String).trim();
      final lastLine = err.isEmpty ? 'unknown error' : err.split('\n').last;
      throw UrlParseException('yt-dlp: $lastLine');
    }

    var data = jsonDecode(result.stdout as String) as Map<String, dynamic>;
    final entries = data['entries'];
    if (entries is List && entries.isNotEmpty && entries.first is Map) {
      data = (entries.first as Map).cast<String, dynamic>();
    }

    String? streamUrl;
    String? audioUrl;
    int? height;

    final requested = data['requested_formats'];
    if (requested is List && requested.length >= 2) {
      final fmts = requested
          .whereType<Map>()
          .map((m) => m.cast<String, dynamic>())
          .toList();

      bool hasVideo(Map<String, dynamic> f) =>
          f['vcodec'] != null && f['vcodec'] != 'none';
      bool hasAudio(Map<String, dynamic> f) =>
          f['acodec'] != null && f['acodec'] != 'none';

      final video = fmts.firstWhere(hasVideo, orElse: () => fmts.first);
      final audio = fmts.firstWhere(
        (f) => hasAudio(f) && !hasVideo(f),
        orElse: () => fmts.last,
      );

      streamUrl = video['url'] as String?;
      audioUrl = audio['url'] as String?;
      height = video['height'] as int?;
    } else {
      streamUrl = data['url'] as String?;
      height = data['height'] as int?;
    }

    if (streamUrl == null || streamUrl.isEmpty) {
      throw const UrlParseException('Failed to get video link.');
    }

    return VideoItem(
      id: (data['id'] ?? DateTime.now().microsecondsSinceEpoch).toString(),
      originalUrl: url,
      streamUrl: streamUrl,
      audioUrl: audioUrl,
      title: (data['title'] as String?) ?? uri.host,
      thumbnailUrl: data['thumbnail'] as String?,
      qualityLabel: height != null ? '${height}p' : null,
    );
  }

  VideoItem _parseDirect(String url, Uri uri) {
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    final title =
        segments.isNotEmpty ? Uri.decodeComponent(segments.last) : uri.host;

    return VideoItem(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      originalUrl: url,
      streamUrl: url,
      title: title,
      thumbnailUrl: null,
    );
  }

  VideoItem fromLocalFile(String path) {
    final name = path.split(Platform.pathSeparator).last;
    final dot = name.lastIndexOf('.');
    final title = dot > 0 ? name.substring(0, dot) : name;

    return VideoItem(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      originalUrl: path,
      streamUrl: path,
      title: title,
      thumbnailUrl: null,
      isLocal: true,
    );
  }
  
  void dispose() {}
}