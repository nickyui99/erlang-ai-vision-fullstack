import 'package:web/web.dart' as web;

void showBrowserNotification({
  required String title,
  required String body,
  String? eventId,
}) {
  if (web.Notification.permission != 'granted') return;

  try {
    web.Notification(
      title,
      web.NotificationOptions(
        body: body,
        tag: eventId ?? 'erlang-security-alert',
        icon: '/icons/Icon-192.png',
        badge: '/icons/Icon-maskable-192.png',
        requireInteraction: true,
      ),
    );
  } catch (_) {
    // Some browsers can expose FCM without supporting foreground notifications.
  }
}