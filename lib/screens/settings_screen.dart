import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/app_exception.dart';
import '../services/app_services.dart';
import '../services/settings_service.dart';
import '../widgets/dialogs.dart';
import '../widgets/subscription_tools.dart';
import '../widgets/topics_dialog.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.services});

  final AppServices services;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _pathController =
      TextEditingController(text: widget.services.settings.ytDlpPath);

  bool _testing = false;
  String? _ytStatus;
  bool _ytOk = false;

  SettingsService get _settings => widget.services.settings;

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
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

  Future<void> _savePath() async {
    await _settings.setYtDlpPath(_pathController.text);
    _pathController.text = _settings.ytDlpPath;
    _toast('yt-dlp path saved');
  }

  Future<void> _testYtDlp() async {
    await _settings.setYtDlpPath(_pathController.text);
    _pathController.text = _settings.ytDlpPath;
    setState(() {
      _testing = true;
      _ytStatus = null;
    });
    try {
      final version = await widget.services.ytdlp.version();
      if (!mounted) return;
      setState(() {
        _ytOk = true;
        _ytStatus = 'Found yt-dlp $version';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _ytOk = false;
        _ytStatus = _errorMessage(e);
      });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _export() async {
    try {
      final bytes = Uint8List.fromList(
        utf8.encode(widget.services.library.exportJson()),
      );
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Export catalog',
        fileName: 'media_catalog.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: bytes,
      );
      if (path == null) return;

      // Desktop pickers only return a path, so write the file ourselves.
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        final target = path.toLowerCase().endsWith('.json') ? path : '$path.json';
        await File(target).writeAsBytes(bytes);
      }
      _toast('Catalog exported');
    } catch (e) {
      _toast(_errorMessage(e));
    }
  }

  Future<void> _import() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.single;
      final String text;
      if (file.bytes != null) {
        text = utf8.decode(file.bytes!);
      } else if (file.path != null) {
        text = await File(file.path!).readAsString();
      } else {
        throw const AppException('Could not read the selected file.');
      }

      if (!mounted) return;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const PopScope(
          canPop: false,
          child: Center(child: CircularProgressIndicator()),
        ),
      );

      try {
        final imported = await widget.services.library
            .importJson(text.replaceFirst('\uFEFF', ''));
        _toast(
          'Imported ${imported.added} new, skipped ${imported.skipped} duplicates',
        );
      } finally {
        if (mounted) Navigator.of(context, rootNavigator: true).pop();
      }
    } catch (e) {
      _toast(_errorMessage(e));
    }
  }

  Future<void> _cleanCovers() async {
    try {
      final removed = await widget.services.library.cleanUnusedCovers();
      _toast('Removed $removed unused cover ${removed == 1 ? 'file' : 'files'}');
    } catch (e) {
      _toast(_errorMessage(e));
    }
  }

  Future<void> _resetHistory() async {
    final ok = await confirmDialog(
      context,
      title: 'Reset watch history',
      message:
          'Clear watched marks and saved positions for every video? Your library itself is not changed.',
      confirmLabel: 'Reset',
    );
    if (!ok) return;
    try {
      await widget.services.library.resetAllProgress();
      _toast('Watch history cleared');
    } catch (e) {
      _toast(_errorMessage(e));
    }
  }

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 24, 0, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ListenableBuilder(
      listenable: _settings,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: const Text('Settings')),
          body: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                children: [
                  _section('PLAYBACK'),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Maximum stream quality'),
                    subtitle: const Text(
                      'Applies to YouTube and other sites. Lower values use less bandwidth and CPU.',
                    ),
                    trailing: DropdownButton<int>(
                      value: _settings.maxQuality,
                      items: [
                        for (final q in SettingsService.qualities)
                          DropdownMenuItem<int>(value: q, child: Text('${q}p')),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          _settings.setMaxQuality(value);
                          widget.services.ytdlp.clearCache();
                        }
                      },
                    ),
                  ),
                  _section('YT-DLP'),
                  TextField(
                    controller: _pathController,
                    decoration: const InputDecoration(
                      labelText: 'yt-dlp path',
                      helperText:
                          'Leave as "yt-dlp" if it is installed in PATH. Install: winget install yt-dlp.yt-dlp',
                      helperMaxLines: 2,
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _savePath(),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      OutlinedButton(
                        onPressed: _savePath,
                        child: const Text('Save'),
                      ),
                      FilledButton.icon(
                        onPressed: _testing ? null : _testYtDlp,
                        icon: _testing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.check_circle_outline),
                        label: const Text('Test'),
                      ),
                    ],
                  ),
                  if (_ytStatus != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _ytStatus!,
                        style: TextStyle(
                          color: _ytOk ? Colors.green : scheme.error,
                        ),
                      ),
                    ),
                  _section('YOUTUBE'),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Autoplay next video'),
                    subtitle: const Text('Continues with the next video in the list you started from.'),
                    value: _settings.autoplayNext,
                    onChanged: _settings.setAutoplayNext,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Show likes and dislikes'),
                    subtitle: const Text('Uses the public Return YouTube Dislike service.'),
                    value: _settings.returnDislike,
                    onChanged: _settings.setReturnDislike,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Refresh subscriptions on startup'),
                    value: _settings.autoRefreshFeed,
                    onChanged: _settings.setAutoRefreshFeed,
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Preferred audio language'),
                    subtitle: const Text('For files with several audio tracks.'),
                    trailing: DropdownButton<String>(
                      value: _settings.audioLang,
                      items: const [
                        DropdownMenuItem(value: 'auto', child: Text('Auto')),
                        DropdownMenuItem(value: 'ru', child: Text('Russian')),
                        DropdownMenuItem(value: 'en', child: Text('English')),
                      ],
                      onChanged: (v) {
                        if (v != null) _settings.setAudioLang(v);
                      },
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Preferred subtitles'),
                    subtitle: const Text('Picked automatically when available.'),
                    trailing: DropdownButton<String>(
                      value: _settings.subLang,
                      items: const [
                        DropdownMenuItem(value: 'off', child: Text('Off')),
                        DropdownMenuItem(value: 'ru', child: Text('Russian')),
                        DropdownMenuItem(value: 'en', child: Text('English')),
                      ],
                      onChanged: (v) {
                        if (v != null) _settings.setSubLang(v);
                      },
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.tune),
                    title: const Text('Your interests'),
                    subtitle: const Text('Topics that build the Home feed.'),
                    onTap: () => showTopicsDialog(context, widget.services.store),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.upload_file_outlined),
                    title: const Text('Import subscriptions'),
                    subtitle: const Text('Google Takeout, NewPipe, FreeTube or OPML file.'),
                    onTap: () => importSubscriptionsFlow(context, widget.services),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.restart_alt),
                    title: const Text('Reset Home memory'),
                    subtitle: const Text('Lets Discover show videos it already showed.'),
                    onTap: () async {
                      await widget.services.store.clearSeen();
                      _toast('Home memory cleared');
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.visibility_outlined),
                    title: const Text('Show hidden videos and channels again'),
                    onTap: () async {
                      await widget.services.store.clearHidden();
                      widget.services.subscriptions.refreshFeed(force: true);
                      _toast('Hidden items restored');
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.history),
                    title: const Text('Clear search history'),
                    onTap: () async {
                      await widget.services.store.clearSearchHistory();
                      _toast('Search history cleared');
                    },
                  ),
                  _section('SPONSORBLOCK'),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Skip sponsor segments'),
                    subtitle: const Text(
                      'YouTube only. Uses the public SponsorBlock database; only a short hash of the video id is sent.',
                    ),
                    value: _settings.sponsorBlock,
                    onChanged: _settings.setSponsorBlock,
                  ),
                  if (_settings.sponsorBlock)
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final entry in sponsorCategoryLabels.entries)
                          FilterChip(
                            label: Text(entry.value),
                            selected:
                                _settings.sponsorCategories.contains(entry.key),
                            onSelected: (on) =>
                                _settings.toggleSponsorCategory(entry.key, on),
                          ),
                      ],
                    ),
                  _section('APPEARANCE'),
                  const Text('Theme'),
                  const SizedBox(height: 8),
                  SegmentedButton<ThemeMode>(
                    segments: const <ButtonSegment<ThemeMode>>[
                      ButtonSegment(
                        value: ThemeMode.dark,
                        label: Text('Dark'),
                        icon: Icon(Icons.dark_mode_outlined),
                      ),
                      ButtonSegment(
                        value: ThemeMode.light,
                        label: Text('Light'),
                        icon: Icon(Icons.light_mode_outlined),
                      ),
                      ButtonSegment(
                        value: ThemeMode.system,
                        label: Text('System'),
                        icon: Icon(Icons.settings_suggest_outlined),
                      ),
                    ],
                    selected: {_settings.themeMode},
                    onSelectionChanged: (s) => _settings.setThemeMode(s.first),
                  ),
                  const SizedBox(height: 16),
                  const Text('Card size'),
                  const SizedBox(height: 8),
                  SegmentedButton<CardSize>(
                    segments: <ButtonSegment<CardSize>>[
                      for (final size in CardSize.values)
                        ButtonSegment(value: size, label: Text(size.label)),
                    ],
                    selected: {_settings.cardSize},
                    onSelectionChanged: (s) => _settings.setCardSize(s.first),
                  ),
                  _section('LIBRARY DATA'),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Suggest links from clipboard'),
                    subtitle: const Text(
                      'When you return to the app and a video link is copied, offer to add it.',
                    ),
                    value: _settings.clipboardSuggest,
                    onChanged: _settings.setClipboardSuggest,
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.history_toggle_off),
                    title: const Text('Reset watch history'),
                    subtitle: const Text('Clears watched marks and saved positions.'),
                    onTap: _resetHistory,
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.upload_file_outlined),
                    title: const Text('Export catalog'),
                    subtitle: const Text('Save all videos and categories to a JSON backup file.'),
                    onTap: _export,
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.download_outlined),
                    title: const Text('Import catalog'),
                    subtitle: const Text('Add videos and categories from a backup file. Duplicates are skipped.'),
                    onTap: _import,
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.link_off_outlined),
                    title: const Text('Clear stream link cache'),
                    subtitle: const Text('Forces fresh links to be fetched on the next play.'),
                    onTap: () {
                      widget.services.ytdlp.clearCache();
                      _toast('Link cache cleared');
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.cleaning_services_outlined),
                    title: const Text('Remove unused cover files'),
                    subtitle: const Text('Deletes cover images that no video uses.'),
                    onTap: _cleanCovers,
                  ),
                  _section('ABOUT'),
                  ListenableBuilder(
                    listenable: widget.services.library,
                    builder: (context, _) {
                      final lib = widget.services.library;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${lib.videos.length} videos in '
                            '${lib.categories.length} categories',
                          ),
                          const SizedBox(height: 4),
                          SelectableText(
                            'Data folder: ${widget.services.db.dataDir}',
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
