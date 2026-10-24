import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/video_category.dart';
import '../models/video_item.dart';
import 'app_exception.dart';
import 'database_service.dart';
import 'settings_service.dart';
import 'thumbnail_service.dart';
import 'ytdlp_service.dart';

class ImportResult {
  const ImportResult({required this.added, required this.skipped});

  final int added;
  final int skipped;
}

/// Holds the catalog (videos + categories), the active filter and search text,
/// and every operation that changes them.
class LibraryController extends ChangeNotifier {
  LibraryController({
    required this.db,
    required this.ytdlp,
    required this.thumbs,
    required this.settings,
  });

  static const int filterAll = -1;
  static const int filterUncategorized = 0;
  static const int filterContinue = -2;
  static const int filterUnwatched = -3;

  static const List<String> _directExtensions = [
    '.mp4',
    '.m3u8',
    '.webm',
    '.mkv',
    '.mov',
    '.avi',
    '.m4v',
    '.flv',
  ];

  final DatabaseService db;
  final YtDlpService ytdlp;
  final ThumbnailService thumbs;
  final SettingsService settings;

  List<VideoItem> _videos = [];
  List<VideoCategory> _categories = [];
  int _filter = filterAll;
  String _query = '';

  List<VideoItem> get videos => _videos;
  List<VideoCategory> get categories => _categories;
  int get filter => _filter;
  String get query => _query;

  bool _matchesFilter(VideoItem v) {
    switch (_filter) {
      case filterAll:
        return true;
      case filterUncategorized:
        return v.categoryId == null;
      case filterContinue:
        return v.inProgress;
      case filterUnwatched:
        return !v.watched;
      default:
        return v.categoryId == _filter;
    }
  }

  int _byRecentlyWatched(VideoItem a, VideoItem b) {
    final aw = a.lastWatchedAt;
    final bw = b.lastWatchedAt;
    if (aw != null && bw != null) return bw.compareTo(aw);
    if (aw != null) return -1;
    if (bw != null) return 1;
    return b.addedAt.compareTo(a.addedAt);
  }

  List<VideoItem> get visibleVideos {
    final q = _query.trim().toLowerCase();
    final list = _videos.where((v) {
      final matchesQuery = q.isEmpty || v.title.toLowerCase().contains(q);
      return _matchesFilter(v) && matchesQuery;
    }).toList();

    if (_filter == filterContinue) {
      list.sort(_byRecentlyWatched);
      return list;
    }

    switch (settings.sortMode) {
      case SortMode.newest:
        list.sort((a, b) => b.addedAt.compareTo(a.addedAt));
      case SortMode.oldest:
        list.sort((a, b) => a.addedAt.compareTo(b.addedAt));
      case SortMode.titleAsc:
        list.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
      case SortMode.titleDesc:
        list.sort(
          (a, b) => b.title.toLowerCase().compareTo(a.title.toLowerCase()),
        );
      case SortMode.recentlyWatched:
        list.sort(_byRecentlyWatched);
    }
    return list;
  }

  VideoItem? byId(int? id) {
    if (id == null) return null;
    for (final v in _videos) {
      if (v.id == id) return v;
    }
    return null;
  }

  /// Lets other parts of the app request a rebuild (e.g. after playback).
  void refresh() => notifyListeners();

  String? categoryName(int? id) {
    if (id == null) return null;
    for (final c in _categories) {
      if (c.id == id) return c.name;
    }
    return null;
  }

  Future<void> load() async {
    _categories = await db.getCategories();
    _videos = await db.getVideos();
    if (_filter > 0 && !_categories.any((c) => c.id == _filter)) {
      _filter = filterAll;
    }
    notifyListeners();
  }

  void setFilter(int value) {
    _filter = value;
    notifyListeners();
  }

  void setQuery(String value) {
    _query = value;
    notifyListeners();
  }

  // ------------------------------------------------------------------- adding

  bool _isDirectFile(Uri uri) {
    final path = uri.path.toLowerCase();
    return _directExtensions.any(path.endsWith);
  }

  String _titleFromUri(Uri uri) {
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return uri.host;
    var name = segments.last;
    final dot = name.lastIndexOf('.');
    if (dot > 0) name = name.substring(0, dot);
    return name.isEmpty ? uri.host : name;
  }

  /// Adds a video from a pasted link. Throws [AppException] with a readable
  /// message when something is wrong.
  Future<VideoItem> addFromInput(String input) async {
    final url = input.trim();
    final uri = Uri.tryParse(url);

    if (url.isEmpty ||
        uri == null ||
        uri.host.isEmpty ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw const AppException(
        'Enter a valid link starting with http:// or https://',
      );
    }
    if (_videos.any((v) => v.originalUrl == url)) {
      throw const AppException('This link is already in your library.');
    }

    final int? categoryId = _filter > 0 ? _filter : null;
    final VideoItem draft;

    if (_isDirectFile(uri)) {
      draft = VideoItem(
        source: VideoSource.direct,
        originalUrl: url,
        title: _titleFromUri(uri),
        categoryId: categoryId,
        addedAt: DateTime.now(),
      );
    } else {
      final meta = await ytdlp.fetchMeta(url);
      String? thumbPath;
      if (meta.thumbnailUrl != null) {
        thumbPath = await thumbs.download(meta.thumbnailUrl!);
      }
      draft = VideoItem(
        source: VideoSource.web,
        originalUrl: url,
        title: meta.title,
        thumbnailUrl: meta.thumbnailUrl,
        thumbnailPath: thumbPath,
        categoryId: categoryId,
        addedAt: DateTime.now(),
      );
    }

    final id = await db.insertVideo(draft);
    final saved = draft.copyWith(id: id);
    _videos = [saved, ..._videos];
    notifyListeners();
    return saved;
  }

  /// Adds files from this computer. Returns how many were new.
  Future<int> addLocalFiles(List<String> paths) async {
    final int? categoryId = _filter > 0 ? _filter : null;
    var added = 0;

    for (final path in paths) {
      final exists = _videos.any(
        (v) => v.source == VideoSource.local && v.originalUrl == path,
      );
      if (exists) continue;

      final draft = VideoItem(
        source: VideoSource.local,
        originalUrl: path,
        title: p.basenameWithoutExtension(path),
        categoryId: categoryId,
        addedAt: DateTime.now(),
      );
      final id = await db.insertVideo(draft);
      _videos = [draft.copyWith(id: id), ..._videos];
      added++;
    }

    if (added > 0) notifyListeners();
    return added;
  }

  // ------------------------------------------------------------------ editing

  Future<void> _save(VideoItem video) async {
    await db.updateVideo(video);
    _videos = [
      for (final v in _videos) v.id == video.id ? video : v,
    ];
    notifyListeners();
  }

  Future<void> applyEdit({
    required VideoItem original,
    required String title,
    required int? categoryId,
    String? newCoverPath,
    bool removeCover = false,
  }) async {
    final cleanTitle = title.trim().isEmpty ? original.title : title.trim();
    var updated = original.copyWith(
      title: cleanTitle,
      replaceCategory: true,
      categoryId: categoryId,
    );

    if (removeCover) {
      await thumbs.deleteFile(original.thumbnailPath);
      updated = updated.copyWith(replaceThumbnail: true);
    } else if (newCoverPath != null) {
      final stored = await thumbs.importFile(newCoverPath);
      await thumbs.deleteFile(original.thumbnailPath);
      updated = updated.copyWith(
        replaceThumbnail: true,
        thumbnailPath: stored,
      );
    }

    await _save(updated);
  }

  /// Re-reads title and cover from the source site (web videos only).
  Future<void> refreshVideo(VideoItem video) async {
    if (video.source != VideoSource.web) return;

    final meta = await ytdlp.fetchMeta(video.originalUrl);
    String? newPath;
    if (meta.thumbnailUrl != null) {
      newPath = await thumbs.download(meta.thumbnailUrl!);
    }
    if (newPath != null) {
      await thumbs.deleteFile(video.thumbnailPath);
    }

    await _save(
      video.copyWith(
        title: meta.title,
        replaceThumbnail: true,
        thumbnailUrl: meta.thumbnailUrl ?? video.thumbnailUrl,
        thumbnailPath: newPath ?? video.thumbnailPath,
      ),
    );
  }

  Future<void> removeVideo(VideoItem video) async {
    final id = video.id;
    if (id == null) return;
    await db.deleteVideo(id);
    await thumbs.deleteFile(video.thumbnailPath);
    _videos = _videos.where((v) => v.id != id).toList();
    notifyListeners();
  }


  // ----------------------------------------------------------------- progress

  /// Called while a video plays. Updates memory and the database quietly;
  /// call [refresh] afterwards when the UI should redraw.
  Future<void> saveProgress(
    int id, {
    required int positionMs,
    required int durationMs,
    bool finished = false,
  }) async {
    final index = _videos.indexWhere((v) => v.id == id);
    if (index < 0 || durationMs <= 0) return;

    final current = _videos[index];
    final reachedEnd = finished ||
        positionMs >= durationMs * 0.92 ||
        (durationMs > 60000 && durationMs - positionMs < 15000);

    final updated = current.copyWith(
      positionMs: reachedEnd ? 0 : positionMs,
      durationMs: durationMs,
      watched: current.watched || reachedEnd,
      lastWatchedAt: DateTime.now(),
    );

    _videos = [
      for (final v in _videos) v.id == id ? updated : v,
    ];

    await db.updateProgress(
      id,
      positionMs: updated.positionMs,
      durationMs: updated.durationMs,
      watched: updated.watched,
      lastWatchedAt: updated.lastWatchedAt,
    );
  }

  Future<void> setWatched(VideoItem video, bool watched) async {
    final id = video.id;
    if (id == null) return;

    final updated = video.copyWith(
      watched: watched,
      positionMs: 0,
      replaceLastWatched: true,
      lastWatchedAt: watched ? DateTime.now() : null,
    );
    await db.updateProgress(
      id,
      positionMs: 0,
      durationMs: updated.durationMs,
      watched: watched,
      lastWatchedAt: updated.lastWatchedAt,
    );
    _videos = [
      for (final v in _videos) v.id == id ? updated : v,
    ];
    notifyListeners();
  }

  Future<void> resetAllProgress() async {
    await db.resetAllProgress();
    _videos = await db.getVideos();
    notifyListeners();
  }

  // --------------------------------------------------------------- categories

  void _checkCategoryName(String name, {int? exceptId}) {
    if (name.isEmpty) {
      throw const AppException('Category name cannot be empty.');
    }
    final lower = name.toLowerCase();
    final duplicate = _categories.any(
      (c) => c.name.toLowerCase() == lower && c.id != exceptId,
    );
    if (duplicate) {
      throw const AppException('A category with this name already exists.');
    }
  }

  Future<void> addCategory(String rawName) async {
    final name = rawName.trim();
    _checkCategoryName(name);
    await db.insertCategory(name);
    _categories = await db.getCategories();
    notifyListeners();
  }

  Future<void> renameCategory(int id, String rawName) async {
    final name = rawName.trim();
    _checkCategoryName(name, exceptId: id);
    await db.renameCategory(id, name);
    _categories = await db.getCategories();
    notifyListeners();
  }

  Future<void> deleteCategory(int id) async {
    await db.deleteCategory(id);
    _categories = await db.getCategories();
    _videos = await db.getVideos();
    if (_filter == id) _filter = filterAll;
    notifyListeners();
  }

  // ------------------------------------------------------------ backup / misc

  String exportJson() {
    final names = {for (final c in _categories) c.id: c.name};
    final data = {
      'app': 'media_catalog',
      'version': 1,
      'exported_at': DateTime.now().toIso8601String(),
      'categories': [for (final c in _categories) c.name],
      'videos': [
        for (final v in _videos)
          {
            'source': v.source.name,
            'url': v.originalUrl,
            'title': v.title,
            'thumbnail_url': v.thumbnailUrl,
            'category': names[v.categoryId],
            'added_at': v.addedAt.millisecondsSinceEpoch,
          },
      ],
    };
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  Future<int> _ensureCategory(String name) async {
    final lower = name.toLowerCase();
    for (final c in _categories) {
      if (c.name.toLowerCase() == lower) return c.id;
    }
    final id = await db.insertCategory(name);
    _categories = await db.getCategories();
    return id;
  }

  Future<ImportResult> importJson(String text) async {
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      throw const AppException('This file is not valid JSON.');
    }
    if (decoded is! Map || decoded['videos'] is! List) {
      throw const AppException('This file is not a Media Catalog backup.');
    }

    final rawCategories = decoded['categories'];
    if (rawCategories is List) {
      for (final name in rawCategories) {
        if (name is String && name.trim().isNotEmpty) {
          await _ensureCategory(name.trim());
        }
      }
    }

    final existing = {
      for (final v in _videos) '${v.source.name}|${v.originalUrl}',
    };

    var added = 0;
    var skipped = 0;
    final newItems = <VideoItem>[];

    for (final raw in decoded['videos'] as List) {
      if (raw is! Map) continue;
      final url = raw['url'];
      if (url is! String || url.trim().isEmpty) continue;

      final source = videoSourceFromString(raw['source'] as String?);
      final key = '${source.name}|$url';
      if (existing.contains(key)) {
        skipped++;
        continue;
      }

      int? categoryId;
      final categoryName = raw['category'];
      if (categoryName is String && categoryName.trim().isNotEmpty) {
        categoryId = await _ensureCategory(categoryName.trim());
      }

      final addedAtRaw = raw['added_at'];
      final addedAt = addedAtRaw is int
          ? DateTime.fromMillisecondsSinceEpoch(addedAtRaw)
          : DateTime.now();
      final title = raw['title'];
      final thumbUrl = raw['thumbnail_url'];

      final draft = VideoItem(
        source: source,
        originalUrl: url,
        title: (title is String && title.trim().isNotEmpty) ? title : url,
        thumbnailUrl: thumbUrl is String ? thumbUrl : null,
        categoryId: categoryId,
        addedAt: addedAt,
      );
      final id = await db.insertVideo(draft);
      newItems.add(draft.copyWith(id: id));
      existing.add(key);
      added++;
    }

    _categories = await db.getCategories();
    _videos = await db.getVideos();
    notifyListeners();

    // Covers are not part of the backup file, so download them again.
    for (final item in newItems) {
      final url = item.thumbnailUrl;
      if (url == null) continue;
      final path = await thumbs.download(url);
      if (path != null) {
        await _save(item.copyWith(thumbnailPath: path));
      }
    }

    return ImportResult(added: added, skipped: skipped);
  }

  Future<int> cleanUnusedCovers() {
    final used = _videos.map((v) => v.thumbnailPath).whereType<String>().toSet();
    return thumbs.cleanUnused(used);
  }
}
