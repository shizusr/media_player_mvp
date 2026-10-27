import 'package:flutter/material.dart';

import 'screens/discover_screen.dart';
import 'screens/library_screen.dart';
import 'screens/movie_search_screen.dart';
import 'screens/search_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/subscriptions_screen.dart';
import 'services/app_services.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.services});

  final AppServices services;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const int _subscriptionsIndex = 2;

  int _index = 0;

  Widget _subscriptionsIcon({required bool selected}) {
    final icon = Icon(
      selected ? Icons.subscriptions : Icons.subscriptions_outlined,
    );
    return ListenableBuilder(
      listenable: widget.services.subscriptions,
      builder: (context, _) {
        final count = widget.services.subscriptions.unseenCount;
        return Badge(
          isLabelVisible: count > 0,
          label: Text(count > 99 ? '99+' : '$count'),
          child: icon,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = IndexedStack(
      index: _index,
      children: [
        DiscoverScreen(
          services: widget.services,
          onOpenSubscriptions: () =>
              setState(() => _index = _subscriptionsIndex),
        ),
        SearchScreen(services: widget.services),
        SubscriptionsScreen(services: widget.services),
        LibraryScreen(services: widget.services),
        const MovieSearchScreen(),
        SettingsScreen(services: widget.services),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;

        if (wide) {
          return Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: _index,
                  labelType: NavigationRailLabelType.all,
                  onDestinationSelected: (i) => setState(() => _index = i),
                  destinations: [
                    const NavigationRailDestination(
                      icon: Icon(Icons.home_outlined),
                      selectedIcon: Icon(Icons.home),
                      label: Text('Home'),
                    ),
                    const NavigationRailDestination(
                      icon: Icon(Icons.search),
                      selectedIcon: Icon(Icons.search),
                      label: Text('Search'),
                    ),
                    NavigationRailDestination(
                      icon: _subscriptionsIcon(selected: false),
                      selectedIcon: _subscriptionsIcon(selected: true),
                      label: const Text('Subscriptions'),
                    ),
                    const NavigationRailDestination(
                      icon: Icon(Icons.video_library_outlined),
                      selectedIcon: Icon(Icons.video_library),
                      label: Text('Library'),
                    ),
                    const NavigationRailDestination(
                      icon: Icon(Icons.movie_outlined),
                      selectedIcon: Icon(Icons.movie),
                      label: Text('Cinema'),
                    ),
                    const NavigationRailDestination(
                      icon: Icon(Icons.settings_outlined),
                      selectedIcon: Icon(Icons.settings),
                      label: Text('Settings'),
                    ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: body),
              ],
            ),
          );
        }

        return Scaffold(
          body: body,
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: 'Home',
              ),
              const NavigationDestination(
                icon: Icon(Icons.search),
                label: 'Search',
              ),
              NavigationDestination(
                icon: _subscriptionsIcon(selected: false),
                selectedIcon: _subscriptionsIcon(selected: true),
                label: 'Subs',
              ),
              const NavigationDestination(
                icon: Icon(Icons.video_library_outlined),
                selectedIcon: Icon(Icons.video_library),
                label: 'Library',
              ),
              const NavigationDestination(
                icon: Icon(Icons.movie_outlined),
                selectedIcon: Icon(Icons.movie),
                label: 'Cinema',
              ),
              const NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: 'Settings',
              ),
            ],
          ),
        );
      },
    );
  }
}
