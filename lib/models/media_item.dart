/// Kind of cinema entry. [apiValue] matches both TMDB and the embed URL path.
enum MediaType {
  movie,
  tv;

  String get apiValue => name;

  String get label => this == movie ? 'Movie' : 'Series';

  static MediaType? tryParse(String? value) {
    for (final type in MediaType.values) {
      if (type.name == value) return type;
    }
    return null;
  }
}

/// A movie or a series from TMDB. Independent from the YouTube models.
class MediaItem {
  const MediaItem({
    required this.id,
    required this.title,
    required this.overview,
    required this.mediaType,
    this.posterPath,
    this.year,
  });

  /// TMDB id.
  final int id;
  final String title;
  final String overview;
  final String? posterPath;
  final MediaType mediaType;
  final int? year;

  static const String _imageBase = 'https://image.tmdb.org/t/p';

  /// Full poster URL, or null when TMDB has no poster for the title.
  /// Typical sizes: w185, w342, w500, original.
  String? posterUrl({String size = 'w342'}) =>
      posterPath == null ? null : '$_imageBase/$size$posterPath';

  /// Builds an item from a TMDB JSON object.
  ///
  /// Returns null for entries that are not a movie or a series (for example
  /// `person` results of `search/multi`). Detail endpoints do not contain
  /// `media_type`, so pass [fallbackType] for them.
  static MediaItem? fromTmdbJson(
    Map<String, dynamic> json, {
    MediaType? fallbackType,
  }) {
    final type =
        MediaType.tryParse(json['media_type'] as String?) ?? fallbackType;
    final id = json['id'];
    if (type == null || id is! int) return null;

    final isMovie = type == MediaType.movie;
    final title = (isMovie ? json['title'] : json['name']) as String?;
    final date =
        (isMovie ? json['release_date'] : json['first_air_date']) as String?;
    final poster = json['poster_path'] as String?;

    return MediaItem(
      id: id,
      title: (title == null || title.isEmpty) ? 'Untitled' : title,
      overview: (json['overview'] as String?) ?? '',
      posterPath: (poster == null || poster.isEmpty) ? null : poster,
      mediaType: type,
      year: _yearOf(date),
    );
  }

  static int? _yearOf(String? date) {
    if (date == null || date.length < 4) return null;
    return int.tryParse(date.substring(0, 4));
  }

  @override
  bool operator ==(Object other) =>
      other is MediaItem && other.id == id && other.mediaType == mediaType;

  @override
  int get hashCode => Object.hash(id, mediaType);
}
