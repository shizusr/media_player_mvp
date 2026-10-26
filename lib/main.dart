import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'app_shell.dart';
import 'services/app_services.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  try {
    final services = await AppServices.create();
    runApp(MediaCatalogApp(services: services));
    if (services.settings.autoRefreshFeed) {
      unawaited(services.subscriptions.refreshFeed());
    }
  } catch (e) {
    runApp(StartupErrorApp(error: e.toString()));
  }
}

class MediaCatalogApp extends StatelessWidget {
  const MediaCatalogApp({super.key, required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: services.settings,
      builder: (context, _) {
        return MaterialApp(
          title: 'Media Catalog',
          debugShowCheckedModeBanner: false,
          theme: buildLightTheme(),
          darkTheme: buildDarkTheme(),
          themeMode: services.settings.themeMode,
          home: AppShell(services: services),
        );
      },
    );
  }
}

class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({super.key, required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildDarkTheme(),
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: SelectableText(
              'The app could not start.\n\n$error',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
