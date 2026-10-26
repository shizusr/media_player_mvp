import 'database_service.dart';
import 'discover_service.dart';
import 'feed_service.dart';
import 'library_controller.dart';
import 'ryd_service.dart';
import 'settings_service.dart';
import 'sponsorblock_service.dart';
import 'subscriptions_controller.dart';
import 'thumbnail_service.dart';
import 'yt_store.dart';
import 'ytdlp_service.dart';

/// All long-lived objects of the app, created once at startup.
class AppServices {
  AppServices._({
    required this.db,
    required this.settings,
    required this.thumbs,
    required this.ytdlp,
    required this.sponsorBlock,
    required this.library,
    required this.store,
    required this.subscriptions,
    required this.discover,
    required this.ryd,
  });

  final DatabaseService db;
  final SettingsService settings;
  final ThumbnailService thumbs;
  final YtDlpService ytdlp;
  final SponsorBlockService sponsorBlock;
  final LibraryController library;
  final YtStore store;
  final SubscriptionsController subscriptions;
  final DiscoverService discover;
  final RydService ryd;

  static Future<AppServices> create() async {
    final db = DatabaseService();
    await db.init();

    final settings = SettingsService(db);
    await settings.load();

    final thumbs = ThumbnailService();
    final ytdlp = YtDlpService(settings);
    final sponsorBlock = SponsorBlockService();
    final library = LibraryController(
      db: db,
      ytdlp: ytdlp,
      thumbs: thumbs,
      settings: settings,
    );
    await library.load();

    final store = YtStore(db);
    await store.load();
    final subscriptions = SubscriptionsController(
      db: db,
      store: store,
      feedService: FeedService(),
    );
    await subscriptions.load();

    return AppServices._(
      db: db,
      settings: settings,
      thumbs: thumbs,
      ytdlp: ytdlp,
      sponsorBlock: sponsorBlock,
      library: library,
      store: store,
      subscriptions: subscriptions,
      discover: DiscoverService(ytdlp: ytdlp, store: store),
      ryd: RydService(),
    );
  }
}
