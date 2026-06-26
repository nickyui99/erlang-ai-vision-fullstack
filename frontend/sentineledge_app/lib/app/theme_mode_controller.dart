import 'package:flutter/material.dart';

class ThemeModeController extends ValueNotifier<ThemeMode> {
  ThemeModeController({ThemeMode initialMode = ThemeMode.system})
    : super(initialMode);

  ThemeMode get mode => value;

  void setMode(ThemeMode mode) {
    value = mode;
  }
}

class AppThemeModeScope extends InheritedNotifier<ThemeModeController> {
  const AppThemeModeScope({
    required ThemeModeController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static ThemeModeController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<AppThemeModeScope>()
        ?.notifier;
  }

  static ThemeModeController of(BuildContext context) {
    final controller = maybeOf(context);
    assert(controller != null, 'No AppThemeModeScope found in context.');
    return controller!;
  }
}
