import 'package:xml/xml.dart';

import '../models/yt_models.dart';
import 'http_helper.dart';

/// Reads the public RSS feed of a YouTube channel (latest ~15 videos).
/// No account and no API key needed.
class FeedService {
  Future<List<YtVideo>> fetchChannel(YtChannel channel) async {
    final body = await httpGetString(
      Uri.https('www.youtube.com', '/feeds/videos.xml', {
        'channel_id': channel.channelId,
      }),
    );
    if (body == null) return const [];

    try {
      final doc = XmlDocument.parse(body);
      final out = <YtVideo>[];

      for (final entry in doc.rootElement.childElements) {
        if (entry.name.local != 'entry') continue;

        String? videoId;
        String? title;
        DateTime? published;
        int? views;

        for (final child in entry.childElements) {
          switch (child.name.local) {
            case 'videoId':
              videoId = child.innerText.trim();
            case 'title':
              title = child.innerText.trim();
            case 'published':
              published = DateTime.tryParse(child.innerText.trim());
            case 'group':
              for (final g in child.childElements) {
                if (g.name.local != 'community') continue;
                for (final c in g.childElements) {
                  if (c.name.local == 'statistics') {
                    views = int.tryParse(c.getAttribute('views') ?? '');
                  }
                }
              }
          }
        }

        if (videoId == null || videoId.isEmpty || title == null || title.isEmpty) {
          continue;
        }
        out.add(
          YtVideo(
            id: videoId,
            title: title,
            channelName: channel.name,
            channelId: channel.channelId,
            views: views,
            publishedAt: published?.toLocal(),
          ),
        );
      }
      return out;
    } catch (_) {
      return const [];
    }
  }
}
