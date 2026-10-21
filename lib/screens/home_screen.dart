import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/video_item.dart';
import '../services/url_parser_service.dart';
import 'player_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
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

  final TextEditingController _controller = TextEditingController();
  final UrlParserService _parser = UrlParserService();
  final List<VideoItem> _videos = [];

  bool _isLoading = false;

  @override
  void dispose() {
    _controller.dispose();
    _parser.dispose();
    super.dispose();
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  Future<void> _addVideo() async {
    if (_isLoading) return;
    FocusScope.of(context).unfocus();

    setState(() => _isLoading = true);

    try {
      final item = await _parser.parse(_controller.text);
      if (!mounted) return;
      setState(() {
        _videos.insert(0, item);
        _controller.clear();
      });
    } catch (e) {
      if (!mounted) return;
      _showMessage(e.toString());
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _pickFiles() async {
    if (_isLoading) return;

    try {
      // 1. Remove '.platform' and call 'FilePicker.pickFiles()' directly.
      // 2. This method now returns a List<PlatformFile> directly rather than a FilePickerResult wrapper.
      final List<PlatformFile> result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: _videoExtensions,
        // Note: allowMultiple was deprecated/removed from this generic helper method in v13,
        // because pickFiles intrinsically returns a List. If you need singular choices, you'd use pickFile().
      );
      
      // Check if the user canceled the picker (the returned list will be empty)
      if (result.isEmpty) return;

      // 3. Map the elements directly from the modern PlatformFile objects.
      // Use 'file.path' instead of accessing 'result.paths'.
      final items = result
          .map((file) => file.path)
          .whereType<String>()
          .map(_parser.fromLocalFile)
          .toList();
          
      if (items.isEmpty) return;
      if (!mounted) return;

      setState(() => _videos.insertAll(0, items));
    } catch (e) {
      if (!mounted) return;
      _showMessage('Failed to open file: $e');
    }
  }

  void _openPlayer(VideoItem item) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PlayerScreen(video: item)),
    );
  }

  int _columnsForWidth(double width) {
    if (width < 600) return 2;
    if (width < 900) return 3;
    if (width < 1300) return 4;
    return 5;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Player'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    enabled: !_isLoading,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _addVideo(),
                    decoration: InputDecoration(
                      hintText: 'Video link (YouTube, .mp4, .m3u8...)',
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
                  child: Center(
                    child: _isLoading
                        ? const SizedBox.square(
                            dimension: 24, // Гарантирует равную ширину и высоту (24x24)
                            child: CircularProgressIndicator(strokeWidth: 3),
                          )
                        : FilledButton(
                            onPressed: _addVideo,
                            child: const Text('Upload'),
                          ),
                  ),
                ),                
                const SizedBox(width: 8),
                SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: _isLoading ? null : _pickFiles,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('File'),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _videos.isEmpty
                ? const Center(
                    child: Text(
                      'Paste a link or select a file from your computer',
                      style: TextStyle(color: Colors.white54),
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = _columnsForWidth(constraints.maxWidth);
                      return GridView.builder(
                        padding: const EdgeInsets.all(12),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 0.95,
                        ),
                        itemCount: _videos.length,
                        itemBuilder: (context, index) {
                          final item = _videos[index];
                          return _VideoCard(
                            item: item,
                            onTap: () => _openPlayer(item),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _VideoCard extends StatelessWidget {
  final VideoItem item;
  final VoidCallback onTap;

  const _VideoCard({required this.item, required this.onTap});

  Widget _placeholder() {
    return Container(
      color: const Color(0xFF272727),
      alignment: Alignment.center,
      child: Icon(
        item.isLocal ? Icons.video_file_outlined : Icons.play_circle_outline,
        size: 48,
        color: Colors.white54,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final thumb = item.thumbnailUrl;

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: thumb == null
                  ? _placeholder()
                  : Image.network(
                      thumb,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _placeholder(),
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return _placeholder();
                      },
                    ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}