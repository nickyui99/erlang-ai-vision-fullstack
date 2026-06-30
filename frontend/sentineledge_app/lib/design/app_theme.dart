import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

/// Assembles [ThemeData] from the design tokens. Replaces the old
/// `LegacySentinelEdgeTheme`. Light is the primary target; dark is provided so
/// `ThemeMode.system` keeps working.
class AppTheme {
  AppTheme._();

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final scheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: brightness,
        ).copyWith(
          primary: AppColors.primary,
          onPrimary: Colors.white,
          primaryContainer: isDark
              ? AppColors.onPrimaryContainer
              : AppColors.primaryContainer,
          onPrimaryContainer: isDark
              ? AppColors.primaryContainer
              : AppColors.onPrimaryContainer,
          surface: isDark ? AppColors.darkSurface : AppColors.lightSurface,
          onSurface: isDark ? AppColors.neutral50 : AppColors.neutral900,
          onSurfaceVariant: isDark
              ? AppColors.neutral400
              : AppColors.neutral600,
          outline: isDark ? AppColors.darkBorder : AppColors.neutral300,
          outlineVariant: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          error: AppColors.danger,
          surfaceContainerLowest: isDark
              ? AppColors.darkBackground
              : AppColors.neutral0,
          surfaceContainerLow: isDark
              ? AppColors.darkSurfaceMuted
              : AppColors.neutral50,
          surfaceContainer: isDark
              ? AppColors.darkSurfaceMuted
              : AppColors.neutral100,
          surfaceContainerHigh: isDark
              ? AppColors.darkSurface
              : AppColors.neutral100,
          surfaceContainerHighest: isDark
              ? AppColors.darkSurface
              : AppColors.neutral150,
        );

    final background = isDark
        ? AppColors.darkBackground
        : AppColors.lightBackground;
    final border = scheme.outlineVariant;
    final textTheme = AppTypography.textTheme(brightness);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      scaffoldBackgroundColor: background,
      textTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      extensions: [AppStatusColors(brightness: brightness)],
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        titleTextStyle: textTheme.titleLarge,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.lgAll,
          side: BorderSide(color: border),
        ),
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 46),
          textStyle: textTheme.labelLarge,
          elevation: 0,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 46),
          textStyle: textTheme.labelLarge,
          foregroundColor: scheme.onSurface,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
          side: BorderSide(color: scheme.outline),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle: textTheme.labelLarge,
          foregroundColor: scheme.primary,
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.smAll),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.smAll),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: isDark ? AppColors.darkSurfaceMuted : AppColors.neutral50,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        hintStyle: textTheme.bodyMedium,
        labelStyle: textTheme.bodyMedium,
        floatingLabelStyle: textTheme.labelMedium?.copyWith(
          color: scheme.primary,
        ),
        prefixIconColor: scheme.onSurfaceVariant,
        border: OutlineInputBorder(
          borderRadius: AppRadius.mdAll,
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdAll,
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdAll,
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
        indicatorShape: const RoundedRectangleBorder(
          borderRadius: AppRadius.mdAll,
        ),
        selectedIconTheme: IconThemeData(color: scheme.onPrimaryContainer),
        unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
        selectedLabelTextStyle: textTheme.labelLarge?.copyWith(
          color: scheme.onSurface,
        ),
        unselectedLabelTextStyle: textTheme.labelLarge?.copyWith(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w500,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: scheme.primaryContainer,
        labelTextStyle: WidgetStatePropertyAll(textTheme.labelMedium),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? scheme.onPrimaryContainer
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? AppColors.neutral800 : AppColors.neutral900,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: Colors.white),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
        insetPadding: const EdgeInsets.all(AppSpacing.lg),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        side: BorderSide(color: border),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.pillAll),
        labelStyle: textTheme.labelMedium,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.neutral900.withValues(alpha: 0.92),
          borderRadius: AppRadius.smAll,
        ),
        textStyle: textTheme.labelMedium?.copyWith(color: Colors.white),
      ),
    );
  }
}
