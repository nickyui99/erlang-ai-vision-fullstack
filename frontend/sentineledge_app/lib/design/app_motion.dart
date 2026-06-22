import 'package:flutter/widgets.dart';

/// Motion tokens. Durations are short and purposeful; curves favour a
/// natural decelerate so state changes feel responsive, not floaty.
class AppMotion {
  AppMotion._();

  static const Duration fast = Duration(milliseconds: 120);
  static const Duration base = Duration(milliseconds: 200);
  static const Duration slow = Duration(milliseconds: 320);

  static const Curve easeOut = Curves.easeOutCubic;
  static const Curve emphasized = Curves.easeOutQuint;
  static const Curve standard = Curves.easeInOutCubic;

  /// Whether animations should be suppressed (OS "reduce motion").
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  /// Returns [duration] unless reduced motion is requested, then [Duration.zero].
  static Duration duration(BuildContext context, Duration duration) =>
      reduced(context) ? Duration.zero : duration;
}
