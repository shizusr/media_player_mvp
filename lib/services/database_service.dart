import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as mobile;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

import '../models/video_category.dart';
import '../models/video_item.dart';

class DatabaseService {
  late ffi.Database _db;

  /// Folder where the database and cover images live.
  late String dataDir;

  Future<void> init() async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    dataDir = dir.path;

    final ffi.DatabaseFactory factory;
    if (Platform.isWindows || Platform.isLinux) {
      ffi.sqfliteFfiInit();
      factory = ffi.databaseFactoryFfi;
    } else {
      factory = mobile.databaseFactory;
    }

    _db = await factory.openDatabase(
      p.join(dir.path, 'catalog.db'),
      options: ffi.OpenDatabaseOptions(
        version: 2,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      ),
    );
  }

  Future<void> _onCreate(ffi.Database db, int version) async {
    await db.execute('''
      CREATE TABLE categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        sort_order INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE videos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        source TEXT NOT NULL,
        original_url TEXT NOT NULL,
        title TEXT NOT NULL,
        thumbnail_url TEXT,
        thumbnail_path TEXT,
        category_id INTEGER,
        added_at INTEGER NOT NULL,
        position_ms INTEGER NOT NULL DEFAULT 0,
        duration_ms INTEGER NOT NULL DEFAULT 0,
        watched INTEGER NOT NULL DEFAULT 0,
        last_watched_at INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE settings (
        setting_key TEXT PRIMARY KEY,
        setting_value TEXT NOT NULL
      )
    ''');
  }

  Future<void> _onUpgrade(ffi.Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
        'ALTER TABLE videos ADD COLUMN position_ms INTEGER NOT NULL DEFAULT 0',
      );
      await db.execute(
        'ALTER TABLE videos ADD COLUMN duration_ms INTEGER NOT NULL DEFAULT 0',
      );
      await db.execute(
        'ALTER TABLE videos ADD COLUMN watched INTEGER NOT NULL DEFAULT 0',
      );
      await db.execute('ALTER TABLE videos ADD COLUMN last_watched_at INTEGER');
    }
  }

  // ---------------------------------------------------------------- categories

  Future<List<VideoCategory>> getCategories() async {
    final rows = await _db.query('categories', orderBy: 'sort_order ASC, id ASC');
    return rows.map(VideoCategory.fromMap).toList();
  }

  Future<int> insertCategory(String name) async {
    final rows = await _db.rawQuery(
      'SELECT COALESCE(MAX(sort_order), 0) + 1 AS next_order FROM categories',
    );
    final order = (rows.first['next_order'] as int?) ?? 1;
    return _db.insert('categories', {'name': name, 'sort_order': order});
  }

  Future<void> renameCategory(int id, String name) async {
    await _db.update(
      'categories',
      {'name': name},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteCategory(int id) async {
    await _db.transaction((txn) async {
      await txn.update(
        'videos',
        {'category_id': null},
        where: 'category_id = ?',
        whereArgs: [id],
      );
      await txn.delete('categories', where: 'id = ?', whereArgs: [id]);
    });
  }

  // -------------------------------------------------------------------- videos

  Future<List<VideoItem>> getVideos() async {
    final rows = await _db.query('videos', orderBy: 'added_at DESC, id DESC');
    return rows.map(VideoItem.fromMap).toList();
  }

  Future<int> insertVideo(VideoItem video) {
    return _db.insert('videos', video.toMap());
  }

  Future<void> updateVideo(VideoItem video) async {
    await _db.update(
      'videos',
      video.toMap(),
      where: 'id = ?',
      whereArgs: [video.id],
    );
  }

  /// Cheap partial update used while a video is playing.
  Future<void> updateProgress(
    int id, {
    required int positionMs,
    required int durationMs,
    required bool watched,
    DateTime? lastWatchedAt,
  }) async {
    await _db.update(
      'videos',
      {
        'position_ms': positionMs,
        'duration_ms': durationMs,
        'watched': watched ? 1 : 0,
        'last_watched_at': lastWatchedAt?.millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> resetAllProgress() async {
    await _db.update('videos', {
      'position_ms': 0,
      'watched': 0,
      'last_watched_at': null,
    });
  }

  Future<void> deleteVideo(int id) async {
    await _db.delete('videos', where: 'id = ?', whereArgs: [id]);
  }

  // ------------------------------------------------------------------ settings

  Future<String?> getSetting(String key) async {
    final rows = await _db.query(
      'settings',
      where: 'setting_key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['setting_value'] as String?;
  }

  Future<void> setSetting(String key, String value) async {
    await _db.insert(
      'settings',
      {'setting_key': key, 'setting_value': value},
      conflictAlgorithm: ffi.ConflictAlgorithm.replace,
    );
  }
}
