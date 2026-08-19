import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Typography - Headings: Plus Jakarta Sans, Body/UI: Inter.
/// Baseline: 16px, line height 1.5.
abstract final class AppTextStyles {
  static const String _headingFamily = 'PlusJakartaSans';
  static const String _bodyFamily = 'Inter';

  static const TextStyle display = TextStyle(
    fontFamily: _headingFamily,
    fontSize: 34,
    height: 1.2,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );

  static const TextStyle headline1 = TextStyle(
    fontFamily: _headingFamily,
    fontSize: 28,
    height: 1.25,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );

  static const TextStyle headline2 = TextStyle(
    fontFamily: _headingFamily,
    fontSize: 22,
    height: 1.3,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static const TextStyle title = TextStyle(
    fontFamily: _headingFamily,
    fontSize: 18,
    height: 1.35,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static const TextStyle body = TextStyle(
    fontFamily: _bodyFamily,
    fontSize: 16,
    height: 1.5,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontFamily: _bodyFamily,
    fontSize: 14,
    height: 1.5,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
  );

  static const TextStyle caption = TextStyle(
    fontFamily: _bodyFamily,
    fontSize: 12,
    height: 1.4,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
  );

  static const TextStyle button = TextStyle(
    fontFamily: _bodyFamily,
    fontSize: 16,
    height: 1,
    fontWeight: FontWeight.w600,
    color: Colors.white,
    letterSpacing: 0.2,
  );

  static const TextStyle price = TextStyle(
    fontFamily: _headingFamily,
    fontSize: 16,
    height: 1.2,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );
}
