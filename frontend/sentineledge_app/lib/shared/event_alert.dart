import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/app_colors.dart';

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
}) {
  playAlertCue();
  if (messenger == null) return;
  final color = tone.base;
  messenger
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
        showCloseIcon: true,
        content: Row(
          children: [
            Icon(Icons.notifications_active, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(body, maxLines: 2, overflow: TextOverflow.ellipsis),
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
