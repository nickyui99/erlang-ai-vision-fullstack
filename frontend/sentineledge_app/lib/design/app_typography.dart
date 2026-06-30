import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Type scale for Erlang AI Vision, built on Inter.
///
/// Weights are deliberate (400/500/600/700) — no blanket w800. Line-heights
/// are tuned for dense data UIs. If the build environment is offline, Inter
/// falls back to the platform default automatically.
class AppTypography {
  AppTypography._();

  static TextTheme textTheme(Brightness brightness) {
    final ink = brightness == Brightness.dark
        ? AppColors.neutral50
        : AppColors.neutral900;
    final inkMuted = brightness == Brightness.dark
        ? AppColors.neutral400
        : AppColors.neutral600;

    TextStyle s(
      double size,
      FontWeight weight, {
      double height = 1.35,
      double spacing = 0,
      Color? color,
    }) => GoogleFonts.inter(
      fontSize: size,
      fontWeight: weight,
      height: height,
      letterSpacing: spacing,
      color: color ?? ink,
    );

    return TextTheme(
      // Display / headlines
      displaySmall: s(34, FontWeight.w700, height: 1.12, spacing: -0.5),
      headlineMedium: s(26, FontWeight.w700, height: 1.18, spacing: -0.3),
      headlineSmall: s(22, FontWeight.w700, height: 1.22, spacing: -0.2),
      // Titles
      titleLarge: s(18, FontWeight.w600, height: 1.3),
      titleMedium: s(16, FontWeight.w600, height: 1.35),
      titleSmall: s(14, FontWeight.w600, height: 1.4),
      // Body
      bodyLarge: s(16, FontWeight.w400, height: 1.5, color: inkMuted),
      bodyMedium: s(14, FontWeight.w400, height: 1.5, color: inkMuted),
      bodySmall: s(12.5, FontWeight.w400, height: 1.45, color: inkMuted),
      // Labels
      labelLarge: s(14, FontWeight.w600, height: 1.2, spacing: 0.1),
      labelMedium: s(12.5, FontWeight.w500, height: 1.2, spacing: 0.1),
      labelSmall: s(11.5, FontWeight.w500, height: 1.2, spacing: 0.4),
    );
  }

  /// Monospace style for tokens, code blocks, and tabular data.
  static TextStyle mono({double size = 12.5, Color? color}) =>
      GoogleFonts.jetBrainsMono(
        fontSize: size,
        height: 1.5,
        color: color,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  /// Tabular figures for metric numbers so digits align.
  static TextStyle tabular(TextStyle base) =>
      base.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
}
