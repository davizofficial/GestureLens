import 'package:flutter/material.dart';

class AppTheme {
  const AppTheme._();

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF0B0F19),
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF00F0FF),
        brightness: Brightness.dark,
      ),
    );
  }
}
