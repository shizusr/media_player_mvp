class VideoItem {
  final String id;
  final String originalUrl;
  final String streamUrl;
  final String? audioUrl;
  final String title;
  final String? thumbnailUrl;
  final String? qualityLabel;
  final bool isLocal;

  const VideoItem({
    required this.id,
    required this.originalUrl,
    required this.streamUrl,
    required this.title,
    this.audioUrl,
    this.thumbnailUrl,
    this.qualityLabel,
    this.isLocal = false,
  });
}