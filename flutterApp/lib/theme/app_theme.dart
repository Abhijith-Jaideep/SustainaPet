import 'package:flutter/material.dart';

class AppColors {
  static const blue = Color(0xFF1967FF);
  static const purple = Color(0xFF8A2BE2);
  static const orange = Color(0xFFF4511E);
  static const card = Color(0xFFF7FAFC);
}

class AppTheme {
  static ThemeData get light {
    final base = ThemeData(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: const Color(0xFFF2F6F8),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          foregroundColor: Colors.white,
        ),
      ),
    );
  }
}
