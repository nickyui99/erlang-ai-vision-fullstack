import 'package:web/web.dart' as web;

Future<bool> openPlaybackUrl(String url, {bool download = false}) async {
  if (download) {
    final anchor = web.HTMLAnchorElement()
      ..href = url
      ..download = 'erlang-clip.mp4'
      ..target = '_blank'
      ..rel = 'noopener';
    web.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
    return true;
  }

  web.window.open(url, '_blank', 'noopener,noreferrer');
  return true;
}
