import 'package:flutter/material.dart';

/// Design tokens mirrored from the UI reference (`instaham_ui`).
abstract final class AppColors {
  // Primary palette
  static const signalPink = Color(0xFFC2185B);
  static const brightPink = Color(0xFFFF5C97);
  static const pinkTint = Color(0xFFFDE1EB);

  // Neutral
  static const background = Color(0xFFFAFAFA);
  static const foreground = Color(0xFF121212);
  static const card = Color(0xFFFFFFFF);
  static const muted = Color(0xFFE0E0E0);
  static const mutedForeground = Color(0xFF616161);
  static const border = Color(0xFFE0E0E0);

  // Status
  static const success = Color(0xFF22C55E);
  static const uncertain = Color(0xFFFBBF24);
  static const blocked = Color(0xFFB45309);
  static const destructive = Color(0xFFD32F2F);
}
