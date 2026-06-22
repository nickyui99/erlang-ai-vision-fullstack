import 'package:flutter/material.dart';

/// Soft, layered elevation tokens. We lead with shadows (not hard borders)
/// to create the calm depth hierarchy of a modern SaaS surface.
class AppShadows {
  AppShadows._();

  /// Resting card: barely-there lift that reads as "on the surface".
  static List<BoxShadow> card(Brightness brightness) {
    if (brightness == Brightness.dark) {
      return const [
        BoxShadow(
          color: Color(0x33000000),
          blurRadius: 2,
          offset: Offset(0, 1),
        ),
      ];
    }
    return const [
      BoxShadow(color: Color(0x0A101828), blurRadius: 1, offset: Offset(0, 1)),
      BoxShadow(color: Color(0x14101828), blurRadius: 3, offset: Offset(0, 1)),
    ];
  }

  /// Hover/selected card: a touch more presence.
  static List<BoxShadow> raised(Brightness brightness) {
    if (brightness == Brightness.dark) {
      return const [
        BoxShadow(
          color: Color(0x4D000000),
          blurRadius: 8,
          offset: Offset(0, 3),
        ),
      ];
    }
    return const [
      BoxShadow(color: Color(0x0F101828), blurRadius: 4, offset: Offset(0, 2)),
      BoxShadow(color: Color(0x1A101828), blurRadius: 12, offset: Offset(0, 6)),
    ];
  }

  /// Floating surfaces: menus, dialogs, toasts.
  static List<BoxShadow> overlay(Brightness brightness) {
    if (brightness == Brightness.dark) {
      return const [
        BoxShadow(
          color: Color(0x66000000),
          blurRadius: 24,
          offset: Offset(0, 12),
        ),
      ];
    }
    return const [
      BoxShadow(
        color: Color(0x1F101828),
        blurRadius: 24,
        offset: Offset(0, 12),
      ),
    ];
  }
}
