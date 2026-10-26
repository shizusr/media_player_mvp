import 'package:flutter/material.dart';

import '../models/yt_models.dart';
import '../services/yt_store.dart';

/// Lets the user manage the interests that drive the Home feed.
/// Returns true when something changed.
Future<bool> showTopicsDialog(BuildContext context, YtStore store) async {
  final changed = await showDialog<bool>(
    context: context,
    builder: (_) => _TopicsDialog(store: store),
  );
  return changed ?? false;
}

class _TopicsDialog extends StatefulWidget {
  const _TopicsDialog({required this.store});

  final YtStore store;

  @override
  State<_TopicsDialog> createState() => _TopicsDialogState();
}

class _TopicsDialogState extends State<_TopicsDialog> {
  static const List<String> _suggestions = [
    'science documentaries',
    'programming tutorials',
    'live music',
    'history',
    'cooking',
    'travel vlog',
    'retro games',
    'space',
  ];

  final TextEditingController _controller = TextEditingController();
  List<YtTopic> _topics = [];
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final topics = await widget.store.topics();
    if (mounted) setState(() => _topics = topics);
  }

  Future<void> _add(String raw) async {
    final query = raw.trim();
    if (query.isEmpty) return;
    if (_topics.any((t) => t.query.toLowerCase() == query.toLowerCase())) return;
    await widget.store.addTopic(query);
    _changed = true;
    _controller.clear();
    await _reload();
  }

  Future<void> _remove(YtTopic topic) async {
    await widget.store.deleteTopic(topic.id);
    _changed = true;
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final unused = _suggestions
        .where((s) => !_topics.any((t) => t.query.toLowerCase() == s))
        .toList();

    return AlertDialog(
      title: const Text('Your interests'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'The Home feed is built from these searches. Every refresh '
                'shows different videos and never repeats what you have seen.',
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: const InputDecoration(
                        labelText: 'Add an interest',
                        isDense: true,
                      ),
                      onSubmitted: _add,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Add',
                    icon: const Icon(Icons.add),
                    onPressed: () => _add(_controller.text),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_topics.isNotEmpty)
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final t in _topics)
                      InputChip(
                        label: Text(t.query),
                        onDeleted: () => _remove(t),
                      ),
                  ],
                ),
              if (unused.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('Suggestions'),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final s in unused)
                      ActionChip(label: Text(s), onPressed: () => _add(s)),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context, _changed),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
