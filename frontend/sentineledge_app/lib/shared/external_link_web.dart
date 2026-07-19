import 'package:web/web.dart' as web;

void openExternalUrl(String url) {
  web.window.open(url, '_blank', 'noopener,noreferrer');
}

/// Leaves the Flutter shell and restores the public static document at `/`.
void returnToPublicLanding() {
  web.window.location.replace('/?landing=1');
}
