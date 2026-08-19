import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:glamea/app/theme/app_colors.dart';
import 'package:glamea/app/theme/app_dimens.dart';

void main() {
  group('Design tokens', () {
    test('brand colors match the spec', () {
      expect(AppColors.primary, const Color(0xFF6B1A2B));
      expect(AppColors.surface, const Color(0xFFFAF9F7));
      expect(AppColors.softGrey, const Color(0xFFF2F0ED));
      expect(AppColors.roseGold, const Color(0xFFC98F86));
      expect(AppColors.coral, const Color(0xFFEF8F82));
    });

    test('mobile card radius is 16px', () {
      expect(AppDimens.cardRadiusMobile, 16);
    });

    test('min touch target is 44px', () {
      expect(AppDimens.minTouchTarget, 44);
    });

    test('portfolio ratio is 4:5', () {
      expect(AppDimens.portfolioAspectRatio, 4 / 5);
    });
  });
}
