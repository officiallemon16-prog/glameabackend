/// Dimensions - radii, touch targets, heights.
abstract final class AppDimens {
  /// Mobile cards: 16px radius. Desktop/admin: 12px.
  static const double cardRadiusMobile = 16;
  static const double cardRadiusDesktop = 12;

  static const double buttonHeight = 52;
  static const double inputHeight = 52;
  static const double chipHeight = 32;

  /// Minimum interactive target: 44-48px.
  static const double minTouchTarget = 44;

  /// Portfolio presentation ratio: 4:5.
  static const double portfolioAspectRatio = 4 / 5;

  static const double maxContentWidth = 600;
}
