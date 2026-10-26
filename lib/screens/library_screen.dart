import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../models/video_item.dart';
import '../services/app_exception.dart';
import '../services/app_services.dart';
import '../services/library_controller.dart';
import '../services/settings_service.dart';
import '../widgets/category_dialog.dart';
import '../widgets/dialogs.dart';
import '../widgets/edit_video_dialog.dart';
import '../widgets/video_card.dart';
import 'player_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, required this.services});

  final AppServices services;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> with WidgetsBindingObserver {
  static const List<String> _videoExtensions = [
    'mp4',
    'mkv',
    'avi',
    'mov',
    'webm',
    'flv',
    'wmv',
    'm4v',
    'ts',
    'mpg',
    'mpeg',
    '3gp',
  ];

  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  bool _adding = false;
  bool _dragging = false;
  String? _lastClipboard;

  LibraryController get _library => widget.services.library;
  SettingsService get _settings => widget.services.settings;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkClipboard());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _urlController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkClipboard();
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _errorMessage(Object error) {
    return error is AppException ? error.message : 'Something went wrong: $error';
  }

  // ---------------------------------------------------------------- clipboard

  Future<void> _checkClipboard() async {
    if (!mounted || !_settings.clipboardSuggest) return;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;

    String? text;
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      text = data?.text?.trim();
    } catch (_) {
      return;
    }
    if (!mounted || text == null || text.isEmpty || text == _lastClipboard) {
      return;
    }
    if (RegExp(r'\s').hasMatch(text)) return;

    final uri = Uri.tryParse(text);
    if (uri == null ||
        uri.host.isEmpty ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      return;
    }

    _lastClipboard = text;
    if (_library.videos.any((v) => v.originalUrl == text)) return;

    final link = text;
    final shown = link.length > 70 ? '${link.substring(0, 67)}...' : link;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentMaterialBanner();
    messenger.showMaterialBanner(
      MaterialBanner(
        leading: const Icon(Icons.content_paste),
        content: Text('Link in clipboard: $shown'),
        actions: [
          TextButton(
            onPressed: messenger.hideCurrentMaterialBanner,
            child: const Text('Dismiss'),
          ),
          FilledButton(
            onPressed: () {
              messenger.hideCurrentMaterialBanner();
              _addLink(link);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );

    Future<void>.delayed(const Duration(seconds: 15), () {
      messenger.hideCurrentMaterialBanner();
    });
  }

  // ------------------------------------------------------------------ adding

  bool _isPlaylistUrl(String text) {
    final uri = Uri.tryParse(text.trim());
    if (uri == null || !uri.host.contains('youtube.com')) return false;
    return uri.path == '/playlist' && uri.queryParameters['list'] != null;
  }

  Future<bool> _importPlaylist(String text) async {
    try {
      _toast('Reading the playlist...');
      final info = await widget.services.ytdlp.playlist(text.trim());
      if (!mounted) return false;
      if (info.videos.isEmpty) {
        _toast('This playlist has no videos.');
        return false;
      }
      final ok = await confirmDialog(
        context,
        title: 'Import playlist',
        message:
            'Add ${info.videos.length} videos from "${info.title}" to a category with the same name?',
        confirmLabel: 'Import',
      );
      if (!ok) return false;
      final added = await _library.importPlaylist(info);
      _toast('Imported $added ${added == 1 ? 'video' : 'videos'}');
      return true;
    } catch (e) {
      _toast(_errorMessage(e));
      return false;
    }
  }

  Future<bool> _addLink(String text) async {
    if (_adding) return false;
    setState(() => _adding = true);
    try {
      if (_isPlaylistUrl(text)) return await _importPlaylist(text);
      final item = await _library.addFromInput(text);
      _toast('Added "${item.title}"');
      return true;
    } catch (e) {
      _toast(_errorMessage(e));
      return false;
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _addUrl() async {
    if (_adding) return;
    final text = _urlController.text;
    FocusScope.of(context).unfocus();
    final ok = await _addLink(text);
    if (ok) _urlController.clear();
  }

  Future<void> _pickFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: _videoExtensions,
        allowMultiple: true,
      );
      if (result == null) return;
      await _addPaths(result.paths.whereType<String>().toList());
    } catch (e) {
      _toast(_errorMessage(e));
    }
  }

  /// Handles files chosen in the picker or dropped on the window.
  Future<void> _addPaths(List<String> paths) async {
    final videoPaths = <String>[];
    final links = <String>[];

    for (final path in paths) {
      final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
      if (_videoExtensions.contains(ext)) {
        videoPaths.add(path);
      } else if (ext == 'url') {
        final link = await _readUrlShortcut(path);
        if (link != null) links.add(link);
      }
    }

    if (videoPaths.isEmpty && links.isEmpty) {
      _toast('Nothing to add. Use video files or .url shortcuts.');
      return;
    }

    if (videoPaths.isNotEmpty) {
      final added = await _library.addLocalFiles(videoPaths);
      if (added == 0) {
        _toast('Those files are already in your library.');
      } else {
        _toast('Added $added ${added == 1 ? 'file' : 'files'}');
      }
    }
    for (final link in links) {
      await _addLink(link);
    }
  }

  Future<String?> _readUrlShortcut(String path) async {
    try {
      final lines = await File(path).readAsLines();
      for (final line in lines) {
        if (line.toUpperCase().startsWith('URL=')) {
          return line.substring(4).trim();
        }
      }
    } catch (_) {
      // Unreadable shortcut: ignore.
    }
    return null;
  }

  // ------------------------------------------------------------------ actions

  void _openPlayer(VideoItem video) {
    final queue = _library.visibleVideos;
    final index = queue.indexWhere((v) => v.id == video.id);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          video: video,
          services: widget.services,
          queue: index >= 0 ? queue : [video],
          queueIndex: index >= 0 ? index : 0,
        ),
      ),
    );
  }

  Future<void> _editVideo(VideoItem video) async {
    final result = await showDialog<EditResult>(
      context: context,
      builder: (_) => EditVideoDialog(
        video: video,
        categories: _library.categories,
      ),
    );
    if (result == null) return;

    try {
      await _library.applyEdit(
        original: video,
        title: result.title,
        categoryId: result.categoryId,
        newCoverPath: result.newCoverPath,
        removeCover: result.removeCover,
      );
    } catch (e) {
      _toast(_errorMessage(e));
    }
  }

  Future<void> _refreshVideo(VideoItem video) async {
    _toast('Refreshing...');
    try {
      await _library.refreshVideo(video);
      _toast('Updated');
    } catch (e) {
      _toast(_errorMessage(e));
    }
  }

  Future<void> _deleteVideo(VideoItem video) async {
    final ok = await confirmDialog(
      context,
      title: 'Delete video',
      message: video.source == VideoSource.local
          ? 'Remove "${video.title}" from the library? The file on your '
              'computer is not deleted.'
          : 'Remove "${video.title}" from the library?',
    );
    if (!ok) return;
    try {
      await _library.removeVideo(video);
    } catch (e) {
      _toast(_errorMessage(e));
    }
  }

  void _onCardAction(VideoItem video, VideoMenuAction action) {
    switch (action) {
      case VideoMenuAction.edit:
        _editVideo(video);
      case VideoMenuAction.refresh:
        _refreshVideo(video);
      case VideoMenuAction.toggleWatched:
        _library.setWatched(video, !video.watched);
      case VideoMenuAction.delete:
        _deleteVideo(video);
    }
  }

  void _manageCategories() {
    showDialog<void>(
      context: context,
      builder: (_) => CategoryManagerDialog(library: _library),
    );
  }

  // ------------------------------------------------------------------- build

  Widget _filterChip(String label, int value) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: _library.filter == value,
        onSelected: (_) => _library.setFilter(value),
      ),
    );
  }

  Widget _emptyState(String text) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(color: color),
        ),
      ),
    );
  }

  Widget _grid(List<VideoItem> videos) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const padding = 12.0;
        const gap = 12.0;
        final maxExtent = _settings.cardSize.maxExtent;
        final available = constraints.maxWidth - padding * 2;
        final columns =
            math.max(1, ((available + gap) / (maxExtent + gap)).ceil());
        final itemWidth = (available - gap * (columns - 1)) / columns;

        return GridView.builder(
          padding: const EdgeInsets.all(padding),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: gap,
            mainAxisSpacing: gap,
            mainAxisExtent: itemWidth * 9 / 16 + 76,
          ),
          itemCount: videos.length,
          itemBuilder: (context, index) {
            final video = videos[index];
            return VideoCard(
              key: ValueKey(video.id),
              video: video,
              categoryName: _library.categoryName(video.categoryId),
              onTap: () => _openPlayer(video),
              onAction: (action) => _onCardAction(video, action),
            );
          },
        );
      },
    );
  }

  Widget _list(List<VideoItem> videos) {
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: videos.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final video = videos[index];
        return VideoListTile(
          key: ValueKey(video.id),
          video: video,
          categoryName: _library.categoryName(video.categoryId),
          onTap: () => _openPlayer(video),
          onAction: (action) => _onCardAction(video, action),
        );
      },
    );
  }

  Widget _content(List<VideoItem> visible) {
    if (_library.videos.isEmpty) {
      return _emptyState(
        'Your library is empty.\nPaste a link above, drop video files here, or press File.',
      );
    }
    if (visible.isEmpty) {
      return _emptyState(
        _library.filter == LibraryController.filterContinue
            ? 'Nothing to continue yet.\nVideos you stop halfway appear here.'
            : 'No videos match your search or filter.',
      );
    }
    return _settings.viewMode == ViewMode.grid ? _grid(visible) : _list(visible);
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return ListenableBuilder(
      listenable: Listenable.merge([_library, _settings]),
      builder: (context, _) {
        final visible = _library.visibleVideos;
        final count = _library.videos.length;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Library'),
            actions: [
              PopupMenuButton<SortMode>(
                tooltip: 'Sort',
                icon: const Icon(Icons.sort),
                onSelected: _settings.setSortMode,
                itemBuilder: (context) => [
                  for (final mode in SortMode.values)
                    CheckedPopupMenuItem<SortMode>(
                      value: mode,
                      checked: _settings.sortMode == mode,
                      child: Text(mode.label),
                    ),
                ],
              ),
              IconButton(
                tooltip: _settings.viewMode == ViewMode.grid
                    ? 'Switch to list'
                    : 'Switch to grid',
                icon: Icon(
                  _settings.viewMode == ViewMode.grid
                      ? Icons.view_list
                      : Icons.grid_view,
                ),
                onPressed: () => _settings.setViewMode(
                  _settings.viewMode == ViewMode.grid
                      ? ViewMode.list
                      : ViewMode.grid,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 4, right: 16),
                child: Center(
                  child: Text(
                    '$count ${count == 1 ? 'video' : 'videos'}',
                    style: TextStyle(color: muted),
                  ),
                ),
              ),
            ],
          ),
          body: DropTarget(
            onDragEntered: (_) => setState(() => _dragging = true),
            onDragExited: (_) => setState(() => _dragging = false),
            onDragDone: (details) {
              setState(() => _dragging = false);
              _addPaths(details.files.map((f) => f.path).toList());
            },
            child: Stack(
              children: [
                Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _urlController,
                              enabled: !_adding,
                              keyboardType: TextInputType.url,
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => _addUrl(),
                              decoration: InputDecoration(
                                hintText:
                                    'Paste a video link (YouTube, Rutube, .mp4, .m3u8...)',
                                prefixIcon: const Icon(Icons.link),
                                isDense: true,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(24),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            height: 48,
                            child: _adding
                                ? const Padding(
                                    padding:
                                        EdgeInsets.symmetric(horizontal: 16),
                                    child: SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 3,
                                      ),
                                    ),
                                  )
                                : FilledButton.icon(
                                    onPressed: _addUrl,
                                    icon: const Icon(Icons.add),
                                    label: const Text('Add'),
                                  ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            height: 48,
                            child: OutlinedButton.icon(
                              onPressed: _adding ? null : _pickFiles,
                              icon: const Icon(Icons.folder_open),
                              label: const Text('File'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                      child: TextField(
                        controller: _searchController,
                        onChanged: _library.setQuery,
                        decoration: InputDecoration(
                          hintText: 'Search by title',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _library.query.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Clear',
                                  icon: const Icon(Icons.close),
                                  onPressed: () {
                                    _searchController.clear();
                                    _library.setQuery('');
                                  },
                                ),
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      height: 48,
                      child: Row(
                        children: [
                          Expanded(
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              children: [
                                _filterChip('All', LibraryController.filterAll),
                                _filterChip(
                                  'Continue',
                                  LibraryController.filterContinue,
                                ),
                                _filterChip(
                                  'Unwatched',
                                  LibraryController.filterUnwatched,
                                ),
                                _filterChip(
                                  'Uncategorized',
                                  LibraryController.filterUncategorized,
                                ),
                                for (final c in _library.categories)
                                  _filterChip(c.name, c.id),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Manage categories',
                            icon: const Icon(Icons.category_outlined),
                            onPressed: _manageCategories,
                          ),
                          const SizedBox(width: 4),
                        ],
                      ),
                    ),
                    Expanded(child: _content(visible)),
                  ],
                ),
                if (_dragging)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.18),
                        alignment: Alignment.center,
                        child: const Text(
                          'Drop video files or .url shortcuts to add them',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
