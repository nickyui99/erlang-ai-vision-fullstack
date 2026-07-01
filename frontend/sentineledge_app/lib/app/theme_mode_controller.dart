import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeModeController extends ValueNotifier<ThemeMode> {
  ThemeModeController({ThemeMode initialMode = ThemeMode.light})
    : super(initialMode) {
    _loadSavedMode();
  }

  static const _preferenceKey = 'theme_mode';

  ThemeMode get mode => value;
  bool get isDark => value == ThemeMode.dark;

  Future<void> _loadSavedMode() async {
    final preferences = await SharedPreferences.getInstance();
    final savedMode = preferences.getString(_preferenceKey);
    if (savedMode == null) return;
    final mode = _themeModeFromName(savedMode);
    if (mode != null && mode != value) {
      value = mode;
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    if (mode == ThemeMode.system) {
      mode = ThemeMode.light;
    }
    if (value != mode) {
      value = mode;
    }
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_preferenceKey, mode.name);
  }

  Future<void> setDarkMode(bool enabled) {
    return setMode(enabled ? ThemeMode.dark : ThemeMode.light);
  }
}

ThemeMode? _themeModeFromName(String value) {
  return switch (value) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => null,
  };
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
