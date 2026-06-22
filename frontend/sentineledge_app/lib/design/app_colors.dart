import 'package:flutter/material.dart';

/// Raw palette + semantic roles for SentinelEdge.
///
/// This is the single source of truth for color. Widgets never hardcode a
/// `Color(0x...)` — they read from here (directly, via the [ColorScheme] the
/// theme builds, or via the [AppStatusColors] theme extension).
class AppColors {
  AppColors._();

  // --- Neutral ramp (slate) -------------------------------------------------
  static const neutral0 = Color(0xFFFFFFFF);
  static const neutral50 = Color(0xFFF7F8FA); // app background
  static const neutral100 = Color(0xFFF1F3F5);
  static const neutral150 = Color(0xFFEAEDF0);
  static const neutral200 = Color(0xFFE3E6EA); // hairline borders
  static const neutral300 = Color(0xFFCBD2D9);
  static const neutral400 = Color(0xFF9AA5B1);
  static const neutral500 = Color(0xFF7B8794);
  static const neutral600 = Color(0xFF616E7C); // secondary text
  static const neutral700 = Color(0xFF3E4C59);
  static const neutral800 = Color(0xFF27313B);
  static const neutral900 = Color(0xFF16202B); // primary text

  // --- Brand (refined teal-green) ------------------------------------------
  static const primary = Color(0xFF0E9F6E);
  static const primaryHover = Color(0xFF0C8A5E);
  static const primaryPressed = Color(0xFF0A6F4C);
  static const primaryContainer = Color(0xFFE3F5EC);
  static const onPrimaryContainer = Color(0xFF065F46);
  static const brandDeep = Color(0xFF2F6B5F); // legacy brand, used sparingly

  // --- Semantic state (base hues; tints derived via alpha) ------------------
  static const success = Color(0xFF16A34A);
  static const warning = Color(0xFFD97706);
  static const danger = Color(0xFFDC2626);
  static const info = Color(0xFF2563EB);

  // --- Light surfaces -------------------------------------------------------
  static const lightBackground = neutral50;
  static const lightSurface = neutral0;
  static const lightSurfaceMuted = neutral100;
  static const lightBorder = neutral200;

  // --- Dark surfaces (future-proofed; shipping light-first) -----------------
  static const darkBackground = Color(0xFF0B1110);
  static const darkSurface = Color(0xFF121A19);
  static const darkSurfaceMuted = Color(0xFF18211F);
  static const darkBorder = Color(0xFF263230);
}

/// Tone categories used by status pills, badges, and banners.
enum StatusTone { success, warning, danger, info, neutral }

extension StatusToneColor on StatusTone {
  Color get base => switch (this) {
    StatusTone.success => AppColors.success,
    StatusTone.warning => AppColors.warning,
    StatusTone.danger => AppColors.danger,
    StatusTone.info => AppColors.info,
    StatusTone.neutral => AppColors.neutral500,
  };

  /// Maps a free-form status string (e.g. "online", "armed", "error") to a tone.
  static StatusTone fromStatus(String value) {
    switch (value.toLowerCase().trim()) {
      case 'online':
      case 'armed':
      case 'active':
      case 'available':
      case 'live':
      case 'completed':
      case 'enabled':
        return StatusTone.success;
      case 'offline':
      case 'error':
      case 'failed':
      case 'disabled':
      case 'critical':
        return StatusTone.danger;
      case 'connecting':
      case 'reconnecting':
      case 'degraded':
      case 'pending':
      case 'warning':
      case 'processing':
        return StatusTone.warning;
      case 'info':
      case 'idle':
      case 'disarmed':
        return StatusTone.info;
      default:
        return StatusTone.neutral;
    }
  }
}

/// Theme extension exposing semantic status colors that adapt to brightness.
@immutable
class AppStatusColors extends ThemeExtension<AppStatusColors> {
  const AppStatusColors({required this.brightness});

  final Brightness brightness;

  Color base(StatusTone tone) => tone.base;

  /// Soft tinted background for a tone (badges, banners).
  Color background(StatusTone tone) =>
      tone.base.withValues(alpha: brightness == Brightness.dark ? 0.20 : 0.12);

  /// Border tint for a tone.
  Color border(StatusTone tone) =>
      tone.base.withValues(alpha: brightness == Brightness.dark ? 0.40 : 0.28);

  /// Foreground (text/icon) for a tone — slightly brighter in dark mode.
  Color foreground(StatusTone tone) => brightness == Brightness.dark
      ? Color.lerp(tone.base, Colors.white, 0.25)!
      : tone.base;

  @override
  AppStatusColors copyWith({Brightness? brightness}) =>
      AppStatusColors(brightness: brightness ?? this.brightness);

  @override
  AppStatusColors lerp(ThemeExtension<AppStatusColors>? other, double t) {
    if (other is! AppStatusColors) return this;
    return t < 0.5 ? this : other;
  }
}
