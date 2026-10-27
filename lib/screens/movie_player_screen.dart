import 'dart:collection';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/embed_provider.dart';

/// Plays a third-party embed player inside a WebView.
///
/// The player page is wrapped in an <iframe>: such players are built to live
/// inside another page and misbehave (hang, "error 153") when opened bare.
/// With several [sources] an app-bar menu switches between them.
class MoviePlayerScreen extends StatefulWidget {
  const MoviePlayerScreen({
    super.key,
    required this.embedUrl,
    required this.title,
    this.sources = const [],
  });

  /// Used when [sources] is empty.
  final String embedUrl;
  final String title;
  final List<EmbedSource> sources;

  @override
  State<MoviePlayerScreen> createState() => _MoviePlayerScreenState();
}

class _MoviePlayerScreenState extends State<MoviePlayerScreen> {
  /// Cancels top-level navigations after load (ad redirects). If a player
  /// ever breaks, set this to false first.
  static const bool _blockTopNavigation = true;

  /// Prints the page console as [web] lines. Keep OFF: sites with
  /// anti-devtools scripts detect the listener and break themselves.
  static const bool _debugConsole = false;

  static final WebUri _baseUrl = WebUri('https://localhost/');

  static bool get _isMobile =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  late final List<EmbedSource> _sources = widget.sources.isEmpty
      ? [EmbedSource(name: 'Default', url: widget.embedUrl)]
      : widget.sources;

  late final InAppWebViewSettings _settings = InAppWebViewSettings(
    javaScriptEnabled: true,
    mediaPlaybackRequiresUserGesture: false,
    allowsInlineMediaPlayback: true,
    iframeAllow: 'autoplay; fullscreen; encrypted-media; picture-in-picture',
    iframeAllowFullscreen: true,
    javaScriptCanOpenWindowsAutomatically: false,
    supportMultipleWindows: false,
    supportZoom: false,
    builtInZoomControls: false,
    displayZoomControls: false,
    disableContextMenu: true,
    allowsBackForwardNavigationGestures: false,
    disallowOverScroll: true,
    overScrollMode: OverScrollMode.NEVER,
    useShouldOverrideUrlLoading: _blockTopNavigation,
    isInspectable: false,
  );

  InAppWebViewController? _controller;
  int _index = 0;
  double _progress = 0;
  bool _firstLoadDone = false;
  String? _error;

  EmbedSource get _source => _sources[_index];

  bool get _direct => _source.mode == EmbedMode.direct;

  /// Origin the wrapper page claims to have.
  WebUri _parentFor(EmbedSource source) {
    if (source.mode == EmbedMode.sameOrigin) {
      return WebUri('${Uri.parse(source.url).origin}/');
    }
    return _baseUrl;
  }

  @override
  void dispose() {
    _restoreSystemUi();
    super.dispose();
  }

  String _html(String url) {
    final safe = const HtmlEscape(HtmlEscapeMode.attribute).convert(url);
    return '''<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>html,body{margin:0;height:100%;overflow:hidden;background:#000}
iframe{display:block;border:0;width:100%;height:100%}</style></head>
<body><iframe src="$safe"
 allow="autoplay; fullscreen; encrypted-media; picture-in-picture"
 allowfullscreen referrerpolicy="origin"></iframe></body></html>''';
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _progress = 0;
      _firstLoadDone = false;
    });
    if (_direct) {
      await _controller?.loadUrl(
        urlRequest: URLRequest(url: WebUri(_source.url)),
      );
    } else {
      await _controller?.loadData(
        data: _html(_source.url),
        baseUrl: _parentFor(_source),
      );
    }
  }

  void _select(int index) {
    if (index == _index) return;
    _index = index;
    _load();
  }

  void _enterFullscreenUi() {
    if (!_isMobile) return;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  void _restoreSystemUi() {
    if (!_isMobile) return;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(const []);
  }

  Future<NavigationActionPolicy> _onNavigation(
    InAppWebViewController controller,
    NavigationAction action,
  ) async {
    if (!_firstLoadDone || !action.isForMainFrame) {
      return NavigationActionPolicy.ALLOW;
    }
    // Direct mode: the site itself may navigate between its own pages.
    if (_direct &&
        action.request.url?.host == Uri.parse(_source.url).host) {
      return NavigationActionPolicy.ALLOW;
    }
    return NavigationActionPolicy.CANCEL;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (_sources.length > 1)
            PopupMenuButton<int>(
              tooltip: 'Switch source (audio / subtitles differ)',
              icon: const Icon(Icons.dns_outlined),
              initialValue: _index,
              onSelected: _select,
              itemBuilder: (context) => [
                for (var i = 0; i < _sources.length; i++)
                  CheckedPopupMenuItem<int>(
                    value: i,
                    checked: i == _index,
                    child: Text(_sources[i].name),
                  ),
              ],
            ),
          IconButton(
            tooltip: 'Open in browser',
            icon: const Icon(Icons.open_in_browser),
            onPressed: () => launchUrl(
              Uri.parse(_source.url),
              mode: LaunchMode.externalApplication,
            ),
          ),
          IconButton(
            tooltip: 'Reload',
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: Stack(
        children: [
          InAppWebView(
            initialData: _direct
                ? null
                : InAppWebViewInitialData(
                    data: _html(_source.url),
                    baseUrl: _parentFor(_source),
                  ),
            initialUrlRequest:
                _direct ? URLRequest(url: WebUri(_source.url)) : null,
            initialSettings: _settings,
            // Forward page errors to the `flutter run` console as [web] lines.
            initialUserScripts: !_debugConsole
                ? null
                : UnmodifiableListView<UserScript>([
              UserScript(
                source: """
window.addEventListener('error', function (e) {
  console.log('JSERR: ' + e.message + ' @' + e.filename + ':' + e.lineno);
});
window.addEventListener('unhandledrejection', function (e) {
  console.log('REJECTION: ' + (e.reason && (e.reason.stack || e.reason)));
});""",
                injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
              ),
            ]),
            onConsoleMessage: !_debugConsole
                ? null
                : (controller, message) =>
                    debugPrint('[web] ${message.message}'),
            onWebViewCreated: (controller) => _controller = controller,
            shouldOverrideUrlLoading: _blockTopNavigation ? _onNavigation : null,
            onCreateWindow: (controller, action) async => false,
            onPermissionRequest: (controller, request) async =>
                PermissionResponse(
              resources: request.resources,
              action: PermissionResponseAction.DENY,
            ),
            onProgressChanged: (controller, progress) {
              if (mounted) setState(() => _progress = progress / 100);
            },
            onLoadStop: (controller, url) => _firstLoadDone = true,
            onReceivedError: (controller, request, error) {
              if (!_firstLoadDone && request.isForMainFrame == true && mounted) {
                setState(() => _error = error.description);
              }
            },
            onEnterFullscreen: (controller) => _enterFullscreenUi(),
            onExitFullscreen: (controller) => _restoreSystemUi(),
          ),
          if (_progress < 1 && _error == null)
            LinearProgressIndicator(value: _progress),
          if (_error != null) _PlayerError(message: _error!, onRetry: _load),
        ],
      ),
    );
  }
}

class _PlayerError extends StatelessWidget {
  const _PlayerError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 40),
              const SizedBox(height: 12),
              Text(
                'The player could not be loaded.\n$message',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
