import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/video_category.dart';
import '../models/video_item.dart';

class EditResult {
  const EditResult({
    required this.title,
    required this.categoryId,
    this.newCoverPath,
    this.removeCover = false,
  });

  final String title;
  final int? categoryId;
  final String? newCoverPath;
  final bool removeCover;
}

class EditVideoDialog extends StatefulWidget {
  const EditVideoDialog({
    super.key,
    required this.video,
    required this.categories,
  });

  final VideoItem video;
  final List<VideoCategory> categories;

  @override
  State<EditVideoDialog> createState() => _EditVideoDialogState();
}

class _EditVideoDialogState extends State<EditVideoDialog> {
  late final TextEditingController _title =
      TextEditingController(text: widget.video.title);
  late int? _categoryId = widget.video.categoryId;
  String? _newCover;
  bool _removeCover = false;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _pickCover() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    final path = result?.files.single.path;
    if (path == null) return;
    setState(() {
      _newCover = path;
      _removeCover = false;
    });
  }

  Widget _preview(ColorScheme scheme) {
    final String? path;
    if (_removeCover) {
      path = null;
    } else {
      path = _newCover ?? widget.video.thumbnailPath;
    }

    final placeholder = Container(
      color: scheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(Icons.image_outlined, size: 40, color: scheme.onSurfaceVariant),
    );

    if (path == null) return placeholder;
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => placeholder,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Text('Edit video'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: _preview(scheme),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: _pickCover,
                    icon: const Icon(Icons.image_outlined),
                    label: const Text('Choose cover'),
                  ),
                  TextButton.icon(
                    onPressed: () => setState(() {
                      _removeCover = true;
                      _newCover = null;
                    }),
                    icon: const Icon(Icons.hide_image_outlined),
                    label: const Text('Remove cover'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _title,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Category',
                  border: OutlineInputBorder(),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int?>(
                    isExpanded: true,
                    value: _categoryId,
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('Uncategorized'),
                      ),
                      for (final c in widget.categories)
                        DropdownMenuItem<int?>(
                          value: c.id,
                          child: Text(c.name),
                        ),
                    ],
                    onChanged: (value) => setState(() => _categoryId = value),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            EditResult(
              title: _title.text,
              categoryId: _categoryId,
              newCoverPath: _newCover,
              removeCover: _removeCover,
            ),
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
