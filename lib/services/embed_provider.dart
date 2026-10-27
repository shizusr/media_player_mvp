import '../models/media_item.dart';

/// How the player page is hosted in the WebView.
/// - iframe: inside a wrapper page on a dummy origin (works for most embeds)
/// - sameOrigin: wrapper page that pretends to be the provider's own site
///   (for players that break when embedded from a foreign origin)
/// - direct: the provider page is opened as the top-level page
enum EmbedMode { iframe, sameOrigin, direct }

/// One concrete URL the player can load.
class EmbedSource {
  const EmbedSource({
    required this.name,
    required this.url,
    this.mode = EmbedMode.iframe,
  });

  final String name;
  final String url;
  final EmbedMode mode;
}

/// A third-party embed player addressed by TMDB id.
///
/// Templates use {id}, {s} (season) and {e} (episode). The only place that
/// knows balancer URL schemes: edit [all] to add, remove or reorder sources.
class EmbedProvider {
  const EmbedProvider({
    required this.name,
    required this.movie,
    required this.tv,
    this.subtitleParam,
    this.mode = EmbedMode.iframe,
  });

  final String name;
  final String movie;
  final String tv;
  final EmbedMode mode;

  /// Query parameter that selects the default subtitle language, if the
  /// provider supports one.
  final String? subtitleParam;

  EmbedSource source({
    required MediaType type,
    required int tmdbId,
    int? season,
    int? episode,
    String? subtitleLang,
  }) {
    var url = (type == MediaType.movie ? movie : tv)
        .replaceAll('{id}', '$tmdbId')
        .replaceAll('{s}', '${season ?? 1}')
        .replaceAll('{e}', '${episode ?? 1}');
    final param = subtitleParam;
    if (param != null && subtitleLang != null && subtitleLang.isNotEmpty) {
      final sep = url.contains('?') ? '&' : '?';
      url = '$url$sep$param=$subtitleLang';
    }
    return EmbedSource(name: name, url: url, mode: mode);
  }

  /// Your own provider without editing code:
  /// --dart-define=EMBED_MOVIE_URL=https://host/movie/{id}
  /// --dart-define=EMBED_TV_URL=https://host/tv/{id}/{s}/{e}
  static const String _customMovie = String.fromEnvironment('EMBED_MOVIE_URL');
  static const String _customTv = String.fromEnvironment('EMBED_TV_URL');

  static final List<EmbedProvider> all = [
    if (_customMovie.isNotEmpty && _customTv.isNotEmpty)
      const EmbedProvider(name: 'Custom', movie: _customMovie, tv: _customTv),
    const EmbedProvider(
      name: 'RiveStream',
      movie: 'https://rivestream.ru/embed?type=movie&id={id}',
      tv: 'https://rivestream.ru/embed?type=tv&id={id}&season={s}&episode={e}',
      mode: EmbedMode.sameOrigin,
    ),
    const EmbedProvider(
      name: 'RiveStream (direct)',
      movie: 'https://rivestream.ru/embed?type=movie&id={id}',
      tv: 'https://rivestream.ru/embed?type=tv&id={id}&season={s}&episode={e}',
      mode: EmbedMode.direct,
    ),
    const EmbedProvider(
      name: 'VidSrc',
      movie: 'https://vidsrc.me/embed/movie?tmdb={id}',
      tv: 'https://vidsrc.me/embed/tv?tmdb={id}&season={s}&episode={e}',
      subtitleParam: 'ds_lang',
    ),
    const EmbedProvider(
      name: 'VidSrc.to',
      movie: 'https://vidsrc.to/embed/movie/{id}',
      tv: 'https://vidsrc.to/embed/tv/{id}/{s}/{e}',
    ),
    const EmbedProvider(
      name: 'VidLink',
      movie: 'https://vidlink.pro/movie/{id}',
      tv: 'https://vidlink.pro/tv/{id}/{s}/{e}',
    ),
    const EmbedProvider(
      name: 'AutoEmbed',
      movie: 'https://player.autoembed.cc/embed/movie/{id}',
      tv: 'https://player.autoembed.cc/embed/tv/{id}/{s}/{e}',
    ),
    const EmbedProvider(
      name: '2Embed',
      movie: 'https://www.2embed.cc/embed/{id}',
      tv: 'https://www.2embed.cc/embedtv/{id}&s={s}&e={e}',
    ),
  ];
}
