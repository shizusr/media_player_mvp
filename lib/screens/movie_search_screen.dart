import 'package:flutter/material.dart';

import '../models/media_item.dart';
import '../services/embed_provider.dart';
import '../services/tmdb_service.dart';
import 'movie_player_screen.dart';

/// Cinema tab: trending catalog + TMDB search. Opens the player on tap.
class MovieSearchScreen extends StatefulWidget {
  const MovieSearchScreen({super.key, this.service});

  /// Optional, for tests. By default the key comes from `--dart-define`.
  final TmdbService? service;

  @override
  State<MovieSearchScreen> createState() => _MovieSearchScreenState();
}

class _MovieSearchScreenState extends State<MovieSearchScreen> {
  late final TmdbService _service =
      widget.service ?? TmdbService.fromEnvironment();
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scroll = ScrollController();

  List<MediaItem> _items = [];
  String _query = '';
  int _page = 0;
  int _totalPages = 1;
  bool _loading = false;
  bool _loadingMore = false;
  String? _error;

  /// Default subtitle language passed to providers that support it.
  String _subLang = 'ru';
  int _requestId = 0;

  bool get _hasMore => _page < _totalPages;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    if (_service.hasCredential) _load(reset: true);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _controller.dispose();
    if (widget.service == null) _service.close();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.hasClients && _scroll.position.extentAfter < 600) {
      _load();
    }
  }

  Future<void> _load({bool reset = false}) async {
    if (!reset && (_loading || _loadingMore || !_hasMore)) return;

    final id = ++_requestId;
    final nextPage = reset ? 1 : _page + 1;
    setState(() {
      if (reset) {
        _loading = true;
        _loadingMore = false;
        _error = null;
      } else {
        _loadingMore = true;
      }
    });

    try {
      final result = _query.isEmpty
          ? await _service.trending(page: nextPage)
          : await _service.search(_query, page: nextPage);
      if (!mounted || id != _requestId) return;
      setState(() {
        _items = reset ? result.items : [..._items, ...result.items];
        _page = result.page;
        _totalPages = result.totalPages;
      });
    } on TmdbException catch (e) {
      if (!mounted || id != _requestId) return;
      if (reset) {
        setState(() => _error = e.message);
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted && id == _requestId) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  void _submit(String text) {
    FocusScope.of(context).unfocus();
    _query = text.trim();
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _load(reset: true);
  }

  void _clear() {
    _controller.clear();
    _submit('');
  }

  Future<void> _open(MediaItem item) async {
    var title = item.title;
    int? season;
    int? episode;

    if (item.mediaType == MediaType.tv) {
      final pick = await showDialog<({int season, int episode})>(
        context: context,
        builder: (_) => _EpisodeDialog(title: item.title),
      );
      if (pick == null || !mounted) return;
      season = pick.season;
      episode = pick.episode;
      title = '${item.title} · S$season E$episode';
    }

    final sources = [
      for (final provider in EmbedProvider.all)
        provider.source(
          type: item.mediaType,
          tmdbId: item.id,
          season: season,
          episode: episode,
          subtitleLang: _subLang,
        ),
    ];
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MoviePlayerScreen(
          embedUrl: sources.first.url,
          title: title,
          sources: sources,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cinema')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: TextField(
              controller: _controller,
              textInputAction: TextInputAction.search,
              onSubmitted: _submit,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search movies and series',
                isDense: true,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _controller.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear',
                        icon: const Icon(Icons.close),
                        onPressed: _clear,
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              children: [
                const Text('Subtitles'),
                const SizedBox(width: 12),
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                  ),
                  segments: const [
                    ButtonSegment(value: 'ru', label: Text('RU')),
                    ButtonSegment(value: 'en', label: Text('EN')),
                    ButtonSegment(value: '', label: Text('Off')),
                  ],
                  selected: {_subLang},
                  onSelectionChanged: (v) => setState(() => _subLang = v.first),
                ),
              ],
            ),
          ),
          Expanded(child: _buildBody(context)),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (!_service.hasCredential) {
      return const _Message(
        icon: Icons.key_off_outlined,
        text: 'TMDB API key is not set.\n'
            'Run the app with --dart-define=TMDB_API_KEY=your_key',
      );
    }
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _items.isEmpty) {
      return _Message(
        icon: Icons.cloud_off_outlined,
        text: _error!,
        onRetry: () => _load(reset: true),
      );
    }
    if (_items.isEmpty) {
      return const _Message(
        icon: Icons.movie_outlined,
        text: 'Nothing found.',
      );
    }

    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _query.isEmpty ? 'Trending this week' : 'Results for "$_query"',
              style: theme.textTheme.titleMedium,
            ),
          ),
        ),
        Expanded(
          child: GridView.builder(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 180,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.52,
            ),
            itemCount: _items.length,
            itemBuilder: (context, index) {
              final item = _items[index];
              return _MediaCard(item: item, onTap: () => _open(item));
            },
          ),
        ),
        if (_loadingMore) const LinearProgressIndicator(),
      ],
    );
  }
}

class _MediaCard extends StatelessWidget {
  const _MediaCard({required this.item, required this.onTap});

  final MediaItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final posterUrl = item.posterUrl();

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (posterUrl == null)
                    const _PosterPlaceholder()
                  else
                    Image.network(
                      posterUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stack) =>
                          const _PosterPlaceholder(),
                      loadingBuilder: (context, child, progress) =>
                          progress == null ? child : const _PosterPlaceholder(),
                    ),
                  Positioned(
                    top: 6,
                    left: 6,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        child: Text(
                          item.mediaType.label,
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            item.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall,
          ),
          if (item.year != null)
            Text(
              '${item.year}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

class _PosterPlaceholder extends StatelessWidget {
  const _PosterPlaceholder();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Center(child: Icon(Icons.movie_outlined, size: 40)),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.onRetry});

  final IconData icon;
  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Asks which season/episode of a series to open.
class _EpisodeDialog extends StatefulWidget {
  const _EpisodeDialog({required this.title});

  final String title;

  @override
  State<_EpisodeDialog> createState() => _EpisodeDialogState();
}

class _EpisodeDialogState extends State<_EpisodeDialog> {
  int _season = 1;
  int _episode = 1;

  Widget _stepper(String label, int value, ValueChanged<int> onChanged) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        IconButton(
          icon: const Icon(Icons.remove),
          onPressed: value > 1 ? () => onChanged(value - 1) : null,
        ),
        SizedBox(
          width: 32,
          child: Text('$value', textAlign: TextAlign.center),
        ),
        IconButton(
          icon: const Icon(Icons.add),
          onPressed: value < 99 ? () => onChanged(value + 1) : null,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _stepper('Season', _season, (v) => setState(() => _season = v)),
          _stepper('Episode', _episode, (v) => setState(() => _episode = v)),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context)
              .pop((season: _season, episode: _episode)),
          child: const Text('Watch'),
        ),
      ],
    );
  }
}
