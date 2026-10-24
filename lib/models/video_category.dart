class VideoCategory {
  const VideoCategory({
    required this.id,
    required this.name,
    this.sortOrder = 0,
  });

  final int id;
  final String name;
  final int sortOrder;

  factory VideoCategory.fromMap(Map<String, Object?> map) {
    return VideoCategory(
      id: map['id'] as int,
      name: map['name'] as String,
      sortOrder: (map['sort_order'] as int?) ?? 0,
    );
  }
}
