import 'package:flutter/material.dart';

ThemeData buildDarkTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: Colors.red,
    brightness: Brightness.dark,
  ).copyWith(surface: const Color(0xFF0F0F0F));

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xFF0F0F0F),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF0F0F0F),
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
  );
}

ThemeData buildLightTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: Colors.red,
    brightness: Brightness.light,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
  );
}
