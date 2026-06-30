import 'package:flutter/material.dart';

/// Raw palette + semantic roles for Erlang AI Vision.
///
/// This is the single source of truth for product color. Widgets should read
/// from here, via [ColorScheme], or via [AppStatusColors] instead of hardcoding
/// one-off colors.
class AppColors {
  AppColors._();

  // --- Neutral ramp ---------------------------------------------------------
  static const neutral0 = Color(0xFFFFFFFF);
  static const neutral50 = Color(0xFFF7F8FA);
  static const neutral100 = Color(0xFFF1F3F5);
  static const neutral150 = Color(0xFFECEFF3);
  static const neutral200 = Color(0xFFE4E7EC);
  static const neutral300 = Color(0xFFD0D5DD);
  static const neutral400 = Color(0xFF98A2B3);
  static const neutral500 = Color(0xFF667085);
  static const neutral600 = Color(0xFF475467);
  static const neutral700 = Color(0xFF344054);
  static const neutral800 = Color(0xFF1D2939);
  static const neutral900 = Color(0xFF111820);

  // --- Brand: Erlang AI Vision ---------------------------------------------
  static const primary = Color(0xFFF03A24);
  static const primaryHover = Color(0xFFE2321E);
  static const primaryPressed = Color(0xFFC91F14);
  static const primaryContainer = Color(0xFFFFE7E1);
  static const onPrimaryContainer = Color(0xFF7A170F);
  static const accentOrange = Color(0xFFFF6A2A);
  static const brandInk = Color(0xFF111820);
  static const brandDeep = primaryPressed;

  // --- Semantic state colors ------------------------------------------------
  static const success = Color(0xFF16A34A);
  static const warning = Color(0xFFD97706);
  static const danger = Color(0xFFDC2626);
  static const info = Color(0xFF2563EB);

  // --- Light surfaces -------------------------------------------------------
  static const lightBackground = neutral50;
  static const lightSurface = neutral0;
  static const lightSurfaceMuted = neutral100;
  static const lightBorder = neutral200;

  // --- Dark surfaces --------------------------------------------------------
  static const darkBackground = Color(0xFF090D12);
  static const darkSurface = Color(0xFF0D1117);
  static const darkSurfaceMuted = Color(0xFF151B23);
  static const darkBorder = Color(0xFF27313B);
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

  /// Foreground (text/icon) for a tone, slightly brighter in dark mode.
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
