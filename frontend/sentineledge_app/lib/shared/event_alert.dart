import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_messenger.dart';
import '../design/app_colors.dart';

final _recentAlertKeys = <String, DateTime>{};

/// Severity -> tone (high/critical=red, medium=amber, low=blue).
StatusTone toneForSeverity(String? severity) {
  switch ((severity ?? '').toLowerCase().trim()) {
    case 'critical':
    case 'high':
      return StatusTone.danger;
    case 'medium':
      return StatusTone.warning;
    case 'low':
      return StatusTone.info;
    default:
      return StatusTone.neutral;
  }
}

/// Whether a realtime verification event represents a positive Qwen result.
///
/// The backend publishes both `verified` and `status`; use both so an older
/// worker or a serialized boolean cannot silently suppress the user alert.
bool isPositiveVerification(Map<String, dynamic> data) {
  final verified = data['verified'];
  if (verified == true || verified?.toString().toLowerCase() == 'true') {
    return true;
  }
  return data['status']?.toString().toLowerCase() == 'verified';
}

/// Play the alert cue: a short system sound plus a haptic buzz. On web the
/// system sound may be silent (browser autoplay policy) but the haptic/no-op is
/// harmless; on mobile both fire.
void playAlertCue() {
  SystemSound.play(SystemSoundType.alert);
  HapticFeedback.mediumImpact();
}

/// Show a floating in-app alert for a new event and play the alert cue. Pass the
/// nearest ScaffoldMessenger; a null messenger just plays the cue.
void showEventAlert(
  ScaffoldMessengerState? messenger, {
  required String title,
  required String body,
  StatusTone tone = StatusTone.danger,
  VoidCallback? onView,
  String? dedupeKey,
}) {
  if (dedupeKey != null && dedupeKey.isNotEmpty) {
    final now = DateTime.now();
    _recentAlertKeys.removeWhere(
      (_, shownAt) => now.difference(shownAt) > const Duration(seconds: 10),
    );
    if (_recentAlertKeys.containsKey(dedupeKey)) return;
    _recentAlertKeys[dedupeKey] = now;
  }
  playAlertCue();
  // Always prefer the root messenger. Realtime callbacks commonly originate
  // below a deferred route, where a context-local messenger can be detached
  // from the visible scaffold.
  final activeMessenger = appScaffoldMessengerKey.currentState ?? messenger;
  if (activeMessenger == null) return;

  // A floating SnackBar normally spans almost the entire browser window. That
  // makes an event alert feel detached from the console on desktop, while a
  // fixed width would overflow narrow browser windows. Derive the insets from
  // the current viewport instead so the alert is compact on desktop and still
  // has a comfortable gutter on small screens.
  final mediaQuery = MediaQuery.maybeOf(activeMessenger.context);
  final viewportWidth = mediaQuery?.size.width ?? 0;
  const minHorizontalInset = 16.0;
  const maxAlertWidth = 520.0;
  final alertWidth = math.max(
    0.0,
    math.min(maxAlertWidth, viewportWidth - (minHorizontalInset * 2)),
  );
  final horizontalInset = viewportWidth > 0
      ? math.max(minHorizontalInset, (viewportWidth - alertWidth) / 2)
      : minHorizontalInset;
  final bottomInset = math.max(
    minHorizontalInset,
    (mediaQuery?.padding.bottom ?? 0) + minHorizontalInset,
  );
  final color = tone.base;
  activeMessenger
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
        // Flutter does not allow a close icon and an action on the same
        // SnackBar. Preserve the explicit View action when supplied; otherwise
        // surface the close affordance for longer event descriptions.
        showCloseIcon: onView == null,
        margin: EdgeInsets.fromLTRB(
          horizontalInset,
          0,
          horizontalInset,
          bottomInset,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        content: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(Icons.notifications_active, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
          ],
        ),
        action: onView != null
            ? SnackBarAction(label: 'View', onPressed: onView)
            : null,
      ),
    );
}
