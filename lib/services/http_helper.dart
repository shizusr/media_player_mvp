import 'dart:convert';
import 'dart:io';

/// Small GET helper. Returns null on any failure or non-200 answer.
Future<String?> httpGetString(
  Uri uri, {
  Duration timeout = const Duration(seconds: 12),
}) async {
  final client = HttpClient()..connectionTimeout = timeout;
  try {
    final request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.userAgentHeader, 'MediaCatalog/4.0');
    final response = await request.close().timeout(timeout);
    if (response.statusCode != 200) {
      await response.drain<void>();
      return null;
    }
    return await response.transform(utf8.decoder).join();
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}
