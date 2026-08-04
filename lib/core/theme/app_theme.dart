import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_text_styles.dart';

enum ResultStatus { success, uncertain, blocked }

enum StatCardStatus { success, warning, error }

abstract final class AppRadius {
  static const double sm = 9.6;
  static const double md = 12.8;
  static const double lg = 16.0;
  static const double xl = 22.4;
  static const double x2l = 28.8;
  static const double x3l = 35.2;
  static const double x4l = 41.6;
}

abstract final class AppTheme {
  static ThemeData get light => ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: const ColorScheme.light(
          primary: AppColors.signalPink,
          onPrimary: Colors.white,
          surface: AppColors.background,
          onSurface: AppColors.foreground,
          error: AppColors.destructive,
          onError: Colors.white,
        ),
        cardTheme: CardThemeData(
          color: AppColors.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            side: const BorderSide(color: AppColors.border),
          ),
          elevation: 0,
        ),
        textTheme: TextTheme(
          headlineMedium: AppTextStyles.headline,
          bodyMedium: AppTextStyles.body,
          labelMedium: AppTextStyles.label,
          bodySmall: AppTextStyles.subtext,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.signalPink,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
            elevation: 0,
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.foreground,
            minimumSize: const Size.fromHeight(48),
            side: const BorderSide(color: AppColors.border),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
          ),
        ),
      );
}
