import 'dart:async';

import 'package:flutter/widgets.dart';

/// Mobile/desktop live view.
///
/// Flutter's [Image] widget cannot decode a multipart `multipart/x-mixed-replace`
/// MJPEG stream, so — exactly like the web build — we poll the backend's
/// single-JPEG `/stream-frame` endpoint (which shares the MJPEG stream's signed
/// token) on a short interval and swap the frame. Polling also keeps a demo
/// camera's server-side simulation alive (each request touches the simulator).
class LiveStreamView extends StatefulWidget {
  const LiveStreamView({required this.url, super.key});

  /// The signed MJPEG stream URL (`.../stream?token=...`). We rewrite it to the
  /// `.../stream-frame` polling endpoint.
  final String url;

  @override
  State<LiveStreamView> createState() => _LiveStreamViewState();
}

class _LiveStreamViewState extends State<LiveStreamView> {
  static const _frameInterval = Duration(milliseconds: 150);

  Timer? _timer;
  int _tick = 0;
  NetworkImage? _previous;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(covariant LiveStreamView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _tick = 0;
      _start();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _previous?.evict();
    super.dispose();
  }

  void _start() {
    _timer?.cancel();
    _timer = Timer.periodic(_frameInterval, (_) {
      if (!mounted) return;
      setState(() => _tick++);
    });
  }

  /// Rewrites `.../stream` to `.../stream-frame` and adds a cache-busting frame
  /// counter so each poll fetches the newest frame.
  String _frameUrl(int tick) {
    final uri = Uri.parse(widget.url);
    final path = uri.path.endsWith('/stream')
        ? '${uri.path.substring(0, uri.path.length - '/stream'.length)}/stream-frame'
        : uri.path;
    final query = Map<String, String>.from(uri.queryParameters)
      ..['_frame'] = tick.toString();
    return uri.replace(path: path, queryParameters: query).toString();
  }

  @override
  Widget build(BuildContext context) {
    final image = NetworkImage(_frameUrl(_tick));
    // Bound the image cache: each frame has a unique (cache-busting) URL, so
    // evict the previous one now that the next is in flight. gaplessPlayback
    // keeps the last decoded frame on screen while the new one loads.
    final stale = _previous;
    if (stale != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => stale.evict());
    }
    _previous = image;
    return Image(
      image: image,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      // Before the first frame arrives (503 "no_stream_frame") show a calm
      // placeholder rather than a broken-image glyph.
      errorBuilder: (context, error, stackTrace) =>
          const ColoredBox(color: Color(0xFF0A1412)),
    );
  }
}
