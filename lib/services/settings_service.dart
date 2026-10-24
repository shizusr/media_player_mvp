import 'package:flutter/material.dart';

import 'database_service.dart';

enum CardSize {
  small(220, 'Small'),
  medium(280, 'Medium'),
  large(360, 'Large');

  const CardSize(this.maxExtent, this.label);

  final double maxExtent;
  final String label;
}

enum SortMode {
  newest('Newest added'),
  oldest('Oldest added'),
  titleAsc('Title A-Z'),
  titleDesc('Title Z-A'),
  recentlyWatched('Recently watched');

  const SortMode(this.label);

  final String label;
}

enum ViewMode { grid, list }

/// SponsorBlock categories the user can choose to skip.
const Map<String, String> sponsorCategoryLabels = {
  'sponsor': 'Sponsor',
  'selfpromo': 'Self-promotion',
  'interaction': 'Like/subscribe reminder',
  'intro': 'Intro',
  'outro': 'Outro / credits',
  'preview': 'Preview / recap',
  'music_offtopic': 'Non-music part',
};

class SettingsService extends ChangeNotifier {
  SettingsService(this._db);

  static const List<int> qualities = [480, 720, 1080, 1440, 2160];

  final DatabaseService _db;

  int maxQuality = 1080;
  String ytDlpPath = 'yt-dlp';
  ThemeMode themeMode = ThemeMode.dark;
  CardSize cardSize = CardSize.medium;
  SortMode sortMode = SortMode.newest;
  ViewMode viewMode = ViewMode.grid;
  double volume = 100;
  bool clipboardSuggest = true;
  bool sponsorBlock = true;
  Set<String> sponsorCategories = {'sponsor', 'selfpromo', 'interaction'};

  Future<void> load() async {
    final quality = int.tryParse(await _db.getSetting('max_quality') ?? '');
    if (quality != null && qualities.contains(quality)) {
      maxQuality = quality;
    }

    final path = await _db.getSetting('ytdlp_path');
    if (path != null && path.trim().isNotEmpty) {
      ytDlpPath = path.trim();
    }

    final theme = await _db.getSetting('theme_mode');
    themeMode = ThemeMode.values.firstWhere(
      (m) => m.name == theme,
      orElse: () => ThemeMode.dark,
    );

    final size = await _db.getSetting('card_size');
    cardSize = CardSize.values.firstWhere(
      (s) => s.name == size,
      orElse: () => CardSize.medium,
    );

    final sort = await _db.getSetting('sort_mode');
    sortMode = SortMode.values.firstWhere(
      (s) => s.name == sort,
      orElse: () => SortMode.newest,
    );

    final view = await _db.getSetting('view_mode');
    viewMode = ViewMode.values.firstWhere(
      (v) => v.name == view,
      orElse: () => ViewMode.grid,
    );

    final vol = double.tryParse(await _db.getSetting('volume') ?? '');
    if (vol != null) volume = vol.clamp(0.0, 100.0).toDouble();

    clipboardSuggest = (await _db.getSetting('clipboard_suggest') ?? '1') == '1';
    sponsorBlock = (await _db.getSetting('sponsorblock') ?? '1') == '1';

    final cats = await _db.getSetting('sponsor_categories');
    if (cats != null) {
      sponsorCategories = cats
          .split(',')
          .where((c) => sponsorCategoryLabels.containsKey(c))
          .toSet();
    }
  }

  Future<void> setMaxQuality(int value) async {
    maxQuality = value;
    notifyListeners();
    await _db.setSetting('max_quality', value.toString());
  }

  Future<void> setYtDlpPath(String value) async {
    final clean = value.trim().isEmpty ? 'yt-dlp' : value.trim();
    ytDlpPath = clean;
    notifyListeners();
    await _db.setSetting('ytdlp_path', clean);
  }

  Future<void> setThemeMode(ThemeMode value) async {
    themeMode = value;
    notifyListeners();
    await _db.setSetting('theme_mode', value.name);
  }

  Future<void> setCardSize(CardSize value) async {
    cardSize = value;
    notifyListeners();
    await _db.setSetting('card_size', value.name);
  }

  Future<void> setSortMode(SortMode value) async {
    sortMode = value;
    notifyListeners();
    await _db.setSetting('sort_mode', value.name);
  }

  Future<void> setViewMode(ViewMode value) async {
    viewMode = value;
    notifyListeners();
    await _db.setSetting('view_mode', value.name);
  }

  Future<void> setClipboardSuggest(bool value) async {
    clipboardSuggest = value;
    notifyListeners();
    await _db.setSetting('clipboard_suggest', value ? '1' : '0');
  }

  Future<void> setSponsorBlock(bool value) async {
    sponsorBlock = value;
    notifyListeners();
    await _db.setSetting('sponsorblock', value ? '1' : '0');
  }

  Future<void> toggleSponsorCategory(String key, bool enabled) async {
    final next = {...sponsorCategories};
    if (enabled) {
      next.add(key);
    } else {
      next.remove(key);
    }
    sponsorCategories = next;
    notifyListeners();
    await _db.setSetting('sponsor_categories', next.join(','));
  }

  /// Saved quietly (no rebuild of the whole app) because the volume slider
  /// changes it many times per second.
  Future<void> rememberVolume(double value) async {
    volume = value.clamp(0.0, 100.0).toDouble();
    await _db.setSetting('volume', volume.toStringAsFixed(0));
  }
}
