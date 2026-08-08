import 'package:flutter/material.dart';

class FnMusicTheme {
  static final lightTheme = ThemeData(
    useMaterial3: true,
    colorSchemeSeed: const Color(0xFF6750A4),
    brightness: Brightness.light,
  );

  static final darkTheme = ThemeData(
    useMaterial3: true,
    colorSchemeSeed: const Color(0xFFD0BCFF),
    brightness: Brightness.dark,
  );
}