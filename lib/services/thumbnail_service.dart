import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Stores cover images in the app data folder so cards look the same offline.
class ThumbnailService {
  Directory? _dir;
  int _counter = 0;

  Future<Directory> _thumbsDir() async {
    final existing = _dir;
    if (existing != null) return existing;

    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'thumbs'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _dir = dir;
    return dir;
  }

  Future<String> _newPath(String extension) async {
    final dir = await _thumbsDir();
    _counter++;
    final name = '${DateTime.now().microsecondsSinceEpoch}_$_counter$extension';
    return p.join(dir.path, name);
  }

  /// Downloads an image and returns the saved file path, or null on failure.
  Future<String?> download(String url) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response =
          await request.close().timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        await response.drain<void>();
        return null;
      }
      final bytes = await consolidateHttpClientResponseBytes(response);
      if (bytes.isEmpty) return null;

      final path = await _newPath('.jpg');
      await File(path).writeAsBytes(bytes);
      return path;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Copies a user-chosen image into the app data folder.
  Future<String> importFile(String sourcePath) async {
    var ext = p.extension(sourcePath);
    if (ext.isEmpty) ext = '.jpg';
    final target = await _newPath(ext);
    await File(sourcePath).copy(target);
    return target;
  }

  Future<void> deleteFile(String? path) async {
    if (path == null) return;
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Ignore: a leftover cover file is harmless.
    }
  }

  /// Deletes cover files that no card refers to. Returns how many were removed.
  Future<int> cleanUnused(Set<String> usedPaths) async {
    final dir = await _thumbsDir();
    var removed = 0;
    await for (final entity in dir.list()) {
      if (entity is File && !usedPaths.contains(entity.path)) {
        try {
          await entity.delete();
          removed++;
        } catch (_) {
          // Skip files that cannot be deleted.
        }
      }
    }
    return removed;
  }
}
