/// A YouTube video as shown in search results, feeds and channel pages.
class YtVideo {
  const YtVideo({
    required this.id,
    required this.title,
    this.channelName,
    this.channelId,
    this.durationSec,
    this.views,
    this.publishedAt,
    this.isShort = false,
  });

  final String id;
  final String title;
  final String? channelName;
  final String? channelId;
  final int? durationSec;
  final int? views;
  final DateTime? publishedAt;
  final bool isShort;

  String get url => 'https://www.youtube.com/watch?v=$id';
  String get thumbnailUrl => 'https://i.ytimg.com/vi/$id/mqdefault.jpg';
  String get coverUrl => 'https://i.ytimg.com/vi/$id/hqdefault.jpg';
}

class YtChannel {
  const YtChannel({
    required this.channelId,
    required this.name,
    required this.subscribedAt,
  });

  final String channelId;
  final String name;
  final DateTime subscribedAt;
}

class YtTopic {
  const YtTopic({required this.id, required this.query});

  final int id;
  final String query;
}

class Chapter {
  const Chapter({required this.start, required this.end, required this.title});

  final double start;
  final double end;
  final String title;
}

class SubtitleOption {
  const SubtitleOption({
    required this.label,
    required this.lang,
    required this.url,
    required this.auto,
  });

  final String label;
  final String lang;
  final String url;
  final bool auto;
}

class VideoDetails {
  const VideoDetails({
    required this.title,
    this.description,
    this.channel,
    this.channelId,
    this.viewCount,
    this.likeCount,
    this.uploadDate,
    this.durationSec,
    this.chapters = const [],
    this.subtitles = const [],
  });

  final String title;
  final String? description;
  final String? channel;
  final String? channelId;
  final int? viewCount;
  final int? likeCount;

  /// yt-dlp format: YYYYMMDD.
  final String? uploadDate;
  final int? durationSec;
  final List<Chapter> chapters;
  final List<SubtitleOption> subtitles;

  DateTime? get uploadedAt {
    final d = uploadDate;
    if (d == null || d.length != 8) return null;
    return DateTime.tryParse('${d.substring(0, 4)}-${d.substring(4, 6)}-${d.substring(6, 8)}');
  }
}

class PlaylistInfo {
  const PlaylistInfo({required this.title, required this.videos});

  final String title;
  final List<YtVideo> videos;
}

class ChannelPageData {
  const ChannelPageData({
    required this.channelId,
    required this.name,
    required this.videos,
  });

  final String channelId;
  final String name;
  final List<YtVideo> videos;
}
