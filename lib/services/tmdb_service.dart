import 'package:dio/dio.dart';

import '../models/media_item.dart';

class TmdbException implements Exception {
  const TmdbException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// One page of TMDB results.
class TmdbPage {
  const TmdbPage({
    required this.items,
    required this.page,
    required this.totalPages,
  });

  final List<MediaItem> items;
  final int page;
  final int totalPages;

  bool get hasMore => page < totalPages;
}

/// Thin TMDB client (catalog, search, details). Used only by the cinema tab.
///
/// Accepts either a v3 API key (32 hex chars, sent as `api_key`) or a v4
/// "API Read Access Token" (a JWT starting with `eyJ`, sent as Bearer).
class TmdbService {
  TmdbService({
    required String credential,
    this.language = 'ru-RU',
    Dio? dio,
  })  : _credential = credential.trim(),
        _ownsDio = dio == null,
        _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: 'https://api.themoviedb.org/3',
                connectTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 15),
                headers: const {'accept': 'application/json'},
              ),
            );

  /// Reads the key from `--dart-define=TMDB_API_KEY=...`.
  factory TmdbService.fromEnvironment() =>
      TmdbService(credential: const String.fromEnvironment('TMDB_API_KEY'));

  final String language;
  final String _credential;
  final Dio _dio;
  final bool _ownsDio;

  bool get hasCredential => _credential.isNotEmpty;

  bool get _isBearer => _credential.startsWith('eyJ');

  /// `search/multi`: movies and series matching [query] (people are dropped).
  Future<TmdbPage> search(String query, {int page = 1}) async {
    final json = await _get('/search/multi', {
      'query': query,
      'page': page,
      'include_adult': false,
    });
    return _parsePage(json);
  }

  /// `trending/all/week`: default catalog shown before the user searches.
  Future<TmdbPage> trending({int page = 1}) async {
    final json = await _get('/trending/all/week', {'page': page});
    return _parsePage(json);
  }

  /// `movie/{id}` or `tv/{id}`.
  Future<MediaItem> details(MediaType type, int id) async {
    final json = await _get('/${type.apiValue}/$id', const {});
    final item = MediaItem.fromTmdbJson(json, fallbackType: type);
    if (item == null) throw const TmdbException('Unexpected TMDB response.');
    return item;
  }

  void close() {
    if (_ownsDio) _dio.close();
  }

  TmdbPage _parsePage(Map<String, dynamic> json) {
    final results = (json['results'] as List<dynamic>? ?? const []);
    final items = <MediaItem>[];
    for (final entry in results) {
      if (entry is! Map<String, dynamic>) continue;
      final item = MediaItem.fromTmdbJson(entry);
      if (item != null) items.add(item);
    }
    return TmdbPage(
      items: items,
      page: (json['page'] as int?) ?? 1,
      totalPages: (json['total_pages'] as int?) ?? 1,
    );
  }

  Future<Map<String, dynamic>> _get(
    String path,
    Map<String, dynamic> params,
  ) async {
    if (!hasCredential) {
      throw const TmdbException(
        'TMDB API key is not set. Run the app with '
        '--dart-define=TMDB_API_KEY=your_key',
      );
    }
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        path,
        queryParameters: {
          ...params,
          'language': language,
          if (!_isBearer) 'api_key': _credential,
        },
        options: _isBearer
            ? Options(headers: {'Authorization': 'Bearer $_credential'})
            : null,
      );
      final data = response.data;
      if (data == null) throw const TmdbException('Empty response from TMDB.');
      return data;
    } on DioException catch (e) {
      throw TmdbException(_describe(e));
    }
  }

  String _describe(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'TMDB is not responding. Try again in a moment.';
      case DioExceptionType.connectionError:
        return 'Cannot reach TMDB. Check your internet connection.';
      case DioExceptionType.badResponse:
        final status = e.response?.statusCode;
        if (status == 401) return 'TMDB rejected the API key.';
        if (status == 404) return 'Nothing found on TMDB.';
        if (status == 429) return 'Too many requests to TMDB. Slow down.';
        return 'TMDB error ($status).';
      default:
        return 'Request to TMDB failed.';
    }
  }
}
