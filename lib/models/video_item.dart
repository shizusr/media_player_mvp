enum VideoSource {
  /// Any page handled by yt-dlp (YouTube, Rutube, Vimeo, ...).
  web,

  /// A direct media link (.mp4, .m3u8, ...).
  direct,

  /// A file on this computer.
  local,
}

VideoSource videoSourceFromString(String? value) {
  return VideoSource.values.firstWhere(
    (e) => e.name == value,
    orElse: () => VideoSource.web,
  );
}

class VideoItem {
  const VideoItem({
    this.id,
    required this.source,
    required this.originalUrl,
    required this.title,
    this.thumbnailUrl,
    this.thumbnailPath,
    this.categoryId,
    required this.addedAt,
    this.positionMs = 0,
    this.durationMs = 0,
    this.watched = false,
    this.lastWatchedAt,
  });

  final int? id;
  final VideoSource source;

  /// Page URL, direct URL or local file path, depending on [source].
  final String originalUrl;
  final String title;
  final String? thumbnailUrl;
  final String? thumbnailPath;
  final int? categoryId;
  final DateTime addedAt;

  /// Where playback stopped (0 when finished or never started).
  final int positionMs;
  final int durationMs;
  final bool watched;
  final DateTime? lastWatchedAt;

  /// Started but not finished: shows a progress bar and "Continue watching".
  bool get inProgress => !watched && positionMs > 5000 && durationMs > 0;

  double get progress {
    if (durationMs <= 0) return 0;
    return (positionMs / durationMs).clamp(0.0, 1.0).toDouble();
  }

  /// When [replaceThumbnail] is true, [thumbnailUrl] and [thumbnailPath] are
  /// used as given (even if null). Same idea for [replaceCategory] and
  /// [replaceLastWatched].
  VideoItem copyWith({
    int? id,
    String? title,
    String? thumbnailUrl,
    String? thumbnailPath,
    int? categoryId,
    int? positionMs,
    int? durationMs,
    bool? watched,
    DateTime? lastWatchedAt,
    bool replaceThumbnail = false,
    bool replaceCategory = false,
    bool replaceLastWatched = false,
  }) {
    return VideoItem(
      id: id ?? this.id,
      source: source,
      originalUrl: originalUrl,
      title: title ?? this.title,
      thumbnailUrl:
          replaceThumbnail ? thumbnailUrl : (thumbnailUrl ?? this.thumbnailUrl),
      thumbnailPath: replaceThumbnail
          ? thumbnailPath
          : (thumbnailPath ?? this.thumbnailPath),
      categoryId: replaceCategory ? categoryId : (categoryId ?? this.categoryId),
      addedAt: addedAt,
      positionMs: positionMs ?? this.positionMs,
      durationMs: durationMs ?? this.durationMs,
      watched: watched ?? this.watched,
      lastWatchedAt: replaceLastWatched
          ? lastWatchedAt
          : (lastWatchedAt ?? this.lastWatchedAt),
    );
  }

  Map<String, Object?> toMap() {
    return {
      if (id != null) 'id': id,
      'source': source.name,
      'original_url': originalUrl,
      'title': title,
      'thumbnail_url': thumbnailUrl,
      'thumbnail_path': thumbnailPath,
      'category_id': categoryId,
      'added_at': addedAt.millisecondsSinceEpoch,
      'position_ms': positionMs,
      'duration_ms': durationMs,
      'watched': watched ? 1 : 0,
      'last_watched_at': lastWatchedAt?.millisecondsSinceEpoch,
    };
  }

  factory VideoItem.fromMap(Map<String, Object?> map) {
    final lastWatched = map['last_watched_at'] as int?;
    return VideoItem(
      id: map['id'] as int?,
      source: videoSourceFromString(map['source'] as String?),
      originalUrl: map['original_url'] as String,
      title: map['title'] as String,
      thumbnailUrl: map['thumbnail_url'] as String?,
      thumbnailPath: map['thumbnail_path'] as String?,
      categoryId: map['category_id'] as int?,
      addedAt: DateTime.fromMillisecondsSinceEpoch(map['added_at'] as int),
      positionMs: (map['position_ms'] as int?) ?? 0,
      durationMs: (map['duration_ms'] as int?) ?? 0,
      watched: ((map['watched'] as int?) ?? 0) != 0,
      lastWatchedAt: lastWatched == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(lastWatched),
    );
  }
}
