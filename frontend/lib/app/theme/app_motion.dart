import 'package:flutter/material.dart';

/// Motion - entrance cubic-bezier(0.32, 0.72, 0, 1);
/// exit cubic-bezier(0.4, 0, 0.2, 1). Bottom sheets use spring physics.
abstract final class AppMotion {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 250);
  static const Duration slow = Duration(milliseconds: 400);

  static const Curve entrance = Cubic(0.32, 0.72, 0, 1);
  static const Curve exit = Cubic(0.4, 0, 0.2, 1);
}
