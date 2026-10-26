import 'package:flutter/material.dart';

import '../models/yt_models.dart';
import '../services/app_exception.dart';
import '../services/app_services.dart';
import '../widgets/yt_video_card.dart';

enum _SortBy { relevance, newest, views }

enum _MinLength { any, over4, over20 }

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.services});

  final AppServices services;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  late final YtActions _actions = YtActions(widget.services);
  final TextEditingController _controller = TextEditingController();

  List<YtVideo> _results = [];
  List<String> _history = [];
  bool _loading = false;
  bool _searched = false;
  String? _error;
  int _count = 20;
  int _searchId = 0;
  String _lastQuery = '';

  _SortBy _sort = _SortBy.relevance;
  _MinLength _minLength = _MinLength.any;
  bool _exact = false;
  bool _hideShorts = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final history = await widget.services.store.searchHistory();
    if (mounted) setState(() => _history = history);
  }

  Future<void> _search({bool more = false, String? text}) async {
    final query = (text ?? (more ? _lastQuery : _controller.text)).trim();
    if (query.isEmpty) return;
    FocusScope.of(context).unfocus();

    if (text != null) _controller.text = text;
    if (!more) {
      _count = 20;
      _lastQuery = query;
    } else {
      _count += 20;
    }

    final id = ++_searchId;
    setState(() {
      _loading = true;
      _error = null;
      _searched = true;
    });

    try {
      final phrase = _exact ? '"$query"' : query;
      final list = await widget.services.ytdlp.search(
        phrase,
        count: _count,
        byDate: _sort == _SortBy.newest,
      );
      if (!mounted || id != _searchId) return;
      setState(() => _results = list);
      await widget.services.store.addSearch(query);
      await _loadHistory();
    } catch (e) {
      if (!mounted || id != _searchId) return;
      setState(() {
        _error = e is AppException ? e.message : 'Search failed: $e';
      });
    } finally {
      if (mounted && id == _searchId) setState(() => _loading = false);
    }
  }

  List<YtVideo> get _shown {
    final minSeconds = switch (_minLength) {
      _MinLength.any => 0,
      _MinLength.over4 => 240,
      _MinLength.over20 => 1200,
    };

    final list = _results.where((v) {
      if (widget.services.store.isHidden(v)) return false;
      if (_hideShorts && v.isShort) return false;
      if (minSeconds > 0 && (v.durationSec ?? 0) < minSeconds) return false;
      return true;
    }).toList();

    if (_sort == _SortBy.views) {
      list.sort((a, b) => (b.views ?? 0).compareTo(a.views ?? 0));
    }
    return list;
  }

  Widget _filters() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ChoiceChip(
            label: const Text('Relevance'),
            selected: _sort == _SortBy.relevance,
            onSelected: (_) {
              setState(() => _sort = _SortBy.relevance);
              if (_searched) _search(text: _lastQuery);
            },
          ),
          ChoiceChip(
            label: const Text('Newest'),
            selected: _sort == _SortBy.newest,
            onSelected: (_) {
              setState(() => _sort = _SortBy.newest);
              if (_searched) _search(text: _lastQuery);
            },
          ),
          ChoiceChip(
            label: const Text('Most viewed'),
            selected: _sort == _SortBy.views,
            onSelected: (_) => setState(() => _sort = _SortBy.views),
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: const Text('Any length'),
            selected: _minLength == _MinLength.any,
            onSelected: (_) => setState(() => _minLength = _MinLength.any),
          ),
          ChoiceChip(
            label: const Text('4+ min'),
            selected: _minLength == _MinLength.over4,
            onSelected: (_) => setState(() => _minLength = _MinLength.over4),
          ),
          ChoiceChip(
            label: const Text('20+ min'),
            selected: _minLength == _MinLength.over20,
            onSelected: (_) => setState(() => _minLength = _MinLength.over20),
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: const Text('Exact phrase'),
            selected: _exact,
            onSelected: (v) => setState(() => _exact = v),
          ),
          FilterChip(
            label: const Text('Hide Shorts'),
            selected: _hideShorts,
            onSelected: (v) => setState(() => _hideShorts = v),
          ),
        ],
      ),
    );
  }

  Widget _historyView() {
    if (_history.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Search YouTube without ads or tracking.\n'
            'Use the filters to sort by date or views, skip Shorts and find exact phrases.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('Recent searches', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            TextButton(
              onPressed: () async {
                await widget.services.store.clearSearchHistory();
                _loadHistory();
              },
              child: const Text('Clear'),
            ),
          ],
        ),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final q in _history)
              ActionChip(label: Text(q), onPressed: () => _search(text: q)),
          ],
        ),
      ],
    );
  }

  Widget _resultsView(List<YtVideo> shown) {
    if (_error != null && _results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }
    if (_loading && _results.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (shown.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Nothing found with these filters.\nTry removing Exact phrase or the length filter.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: shown.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        if (index == shown.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Center(
              child: _loading
                  ? const CircularProgressIndicator()
                  : OutlinedButton(
                      onPressed: () => _search(more: true),
                      child: const Text('Load more results'),
                    ),
            ),
          );
        }
        final video = shown[index];
        return YtVideoTile(
          key: ValueKey(video.id),
          services: widget.services,
          video: video,
          onTap: () => _actions.play(context, shown, index),
          onAction: (action) => _actions.handle(
            context,
            action,
            video,
            list: shown,
            index: index,
            onHidden: () => setState(() {}),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown;

    return Scaffold(
      appBar: AppBar(title: const Text('Search')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _controller,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                hintText: 'Search YouTube',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  tooltip: 'Search',
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: _search,
                ),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
          ),
          _filters(),
          Expanded(child: _searched ? _resultsView(shown) : _historyView()),
        ],
      ),
    );
  }
}
