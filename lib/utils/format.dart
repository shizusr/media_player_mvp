String formatDuration(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

String formatMs(int ms) => formatDuration(Duration(milliseconds: ms));

String formatViews(int n) {
  if (n >= 1000000000) return '${(n / 1e9).toStringAsFixed(1)}B';
  if (n >= 1000000) return '${(n / 1e6).toStringAsFixed(n >= 10000000 ? 0 : 1)}M';
  if (n >= 1000) return '${(n / 1e3).toStringAsFixed(n >= 10000 ? 0 : 1)}K';
  return '$n';
}

String timeAgo(DateTime time) {
  final diff = DateTime.now().difference(time);
  String unit(int n, String word) => '$n ${n == 1 ? word : '${word}s'} ago';
  if (diff.inDays >= 365) return unit(diff.inDays ~/ 365, 'year');
  if (diff.inDays >= 30) return unit(diff.inDays ~/ 30, 'month');
  if (diff.inDays >= 1) return unit(diff.inDays, 'day');
  if (diff.inHours >= 1) return unit(diff.inHours, 'hour');
  if (diff.inMinutes >= 1) return unit(diff.inMinutes, 'minute');
  return 'just now';
}
