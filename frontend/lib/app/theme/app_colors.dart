import 'package:flutter/material.dart';

/// Glamea design tokens - Luxury Minimalism.
/// Primary: Oxblood/Burgundy, Warm Cream, Soft Grey, Warm Rose Gold, Soft Coral.
class AppColors {
  AppColors._();

  /// Primary Oxblood/Burgundy
  static const Color primary = Color(0xFF6B1A2B);

  /// Deep Oxblood - gradient partner to [primary]
  static const Color primaryDeep = Color(0xFF8A2438);

  /// Warm Cream
  static const Color surface = Color(0xFFFAF9F7);

  /// Soft Grey
  static const Color softGrey = Color(0xFFF2F0ED);

  /// White
  static const Color white = Color(0xFFFFFFFF);

  /// Warm Rose Gold
  static const Color roseGold = Color(0xFFC98F86);

  /// Soft blush - gradient partner to [roseGold]
  static const Color roseGoldSoft = Color(0xFFEAD8D2);

  /// Soft Coral
  static const Color coral = Color(0xFFEF8F82);

  /// Rating gold
  static const Color rating = Color(0xFFF5B301);

  /// Muted "confirmed/info" blue that sits in the warm palette
  static const Color info = Color(0xFF6E8CA6);

  /// Success
  static const Color success = Color(0xFF10B981);

  /// Warning
  static const Color warning = Color(0xFFF59E0B);

  /// Error
  static const Color error = Color(0xFFEF4444);

  // Text
  static const Color textPrimary = Color(0xFF1C1917);
  static const Color textSecondary = Color(0xFF57534E);
  static const Color textMuted = Color(0xFF78716C);

  /// Subtle borders per spec: rgba(0,0,0,0.06)
  static const Color borderSubtle = Color(0x0F000000);

  /// Overlays
  static const Color scrim = Color(0x99000000);
  static const Color shimmerBase = Color(0xFFE7E5E4);
  static const Color shimmerHighlight = Color(0xFFF5F5F4);
}
