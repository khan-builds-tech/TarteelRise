import 'package:flutter/material.dart';

/// The app's fixed dark-mode palette. Values are pinned to exact hex codes
/// (not derived from a seed color) so the "Deep Slate + Emerald" identity
/// stays consistent regardless of Material 3 dynamic color behavior.
class AppColors {
  const AppColors._();

  static const Color primaryBackground = Color(0xFF121212);
  static const Color accentEmerald = Color(0xFF0F9D58);
  static const Color surfaceElevated = Color(0xFF1E1E1E);
  static const Color textPrimary = Color(0xFFF5F5F5);
}

/// Text styles with fixed sizing that Material's default [TextTheme] scale
/// doesn't cover, most importantly the Arabic Ayah display style mandated
/// by the product spec (28pt+, 1.8 line height, for legibility to
/// half-asleep eyes).
class AppTextStyles {
  const AppTextStyles._();

  static const TextStyle arabicAyah = TextStyle(
    color: AppColors.textPrimary,
    fontSize: 30,
    height: 1.8,
    fontWeight: FontWeight.w500,
  );
}

/// The single source of the app's Material 3 dark theme.
class AppTheme {
  const AppTheme._();

  static ThemeData get darkTheme {
    final ColorScheme colorScheme = const ColorScheme.dark().copyWith(
      primary: AppColors.accentEmerald,
      onPrimary: AppColors.textPrimary,
      secondary: AppColors.accentEmerald,
      onSecondary: AppColors.textPrimary,
      surface: AppColors.surfaceElevated,
      onSurface: AppColors.textPrimary,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.primaryBackground,
      textTheme: _textTheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.primaryBackground,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: AppColors.surfaceElevated,
        elevation: 4,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.accentEmerald,
        foregroundColor: AppColors.textPrimary,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accentEmerald,
          foregroundColor: AppColors.textPrimary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
      ),
    );
  }

  static const TextTheme _textTheme = TextTheme(
    displayLarge: TextStyle(
      color: AppColors.textPrimary,
      fontSize: 57,
      fontWeight: FontWeight.w700,
    ),
    displayMedium: TextStyle(
      color: AppColors.textPrimary,
      fontSize: 45,
      fontWeight: FontWeight.w700,
    ),
    headlineLarge: TextStyle(
      color: AppColors.textPrimary,
      fontSize: 32,
      fontWeight: FontWeight.w600,
    ),
    headlineMedium: TextStyle(
      color: AppColors.textPrimary,
      fontSize: 28,
      fontWeight: FontWeight.w600,
    ),
    titleLarge: TextStyle(
      color: AppColors.textPrimary,
      fontSize: 22,
      fontWeight: FontWeight.w600,
    ),
    bodyLarge: TextStyle(
      color: AppColors.textPrimary,
      fontSize: 16,
      height: 1.5,
    ),
    bodyMedium: TextStyle(
      color: Color(0xFFB3B3B3),
      fontSize: 14,
      height: 1.5,
    ),
    labelLarge: TextStyle(
      color: AppColors.textPrimary,
      fontSize: 16,
      fontWeight: FontWeight.w600,
    ),
  );
}
