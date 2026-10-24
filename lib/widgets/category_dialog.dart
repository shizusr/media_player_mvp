import 'package:flutter/material.dart';

import '../models/video_category.dart';
import '../services/app_exception.dart';
import '../services/library_controller.dart';
import 'dialogs.dart';

class CategoryManagerDialog extends StatefulWidget {
  const CategoryManagerDialog({super.key, required this.library});

  final LibraryController library;

  @override
  State<CategoryManagerDialog> createState() => _CategoryManagerDialogState();
}

class _CategoryManagerDialogState extends State<CategoryManagerDialog> {
  final TextEditingController _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    try {
      await widget.library.addCategory(_controller.text);
      _controller.clear();
      if (mounted) setState(() => _error = null);
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _rename(VideoCategory category) async {
    final name = await promptText(
      context,
      title: 'Rename category',
      initial: category.name,
      label: 'Name',
    );
    if (name == null) return;
    try {
      await widget.library.renameCategory(category.id, name);
      if (mounted) setState(() => _error = null);
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _delete(VideoCategory category) async {
    final ok = await confirmDialog(
      context,
      title: 'Delete category',
      message:
          'Delete "${category.name}"? Its videos will move to Uncategorized.',
    );
    if (!ok) return;
    await widget.library.deleteCategory(category.id);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Categories'),
      content: SizedBox(
        width: 400,
        child: ListenableBuilder(
          listenable: widget.library,
          builder: (context, _) {
            final categories = widget.library.categories;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        decoration: InputDecoration(
                          labelText: 'New category',
                          errorText: _error,
                          isDense: true,
                        ),
                        onSubmitted: (_) => _add(),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Add',
                      onPressed: _add,
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (categories.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('No categories yet.'),
                  )
                else
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final c in categories)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(c.name),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Rename',
                                  icon: const Icon(Icons.edit_outlined),
                                  onPressed: () => _rename(c),
                                ),
                                IconButton(
                                  tooltip: 'Delete',
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () => _delete(c),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
