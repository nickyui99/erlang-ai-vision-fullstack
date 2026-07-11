import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

class PlaybackVideoView extends StatefulWidget {
  const PlaybackVideoView({required this.url, super.key});

  final String url;

  @override
  State<PlaybackVideoView> createState() => _PlaybackVideoViewState();
}

class _PlaybackVideoViewState extends State<PlaybackVideoView> {
  late final String _viewType;
  late final web.HTMLVideoElement _video;

  @override
  void initState() {
    super.initState();
    _viewType =
        'erlang-playback-${widget.url.hashCode}-${DateTime.now().microsecondsSinceEpoch}';
    _video = web.HTMLVideoElement()
      ..src = widget.url
      ..controls = true
      ..preload = 'metadata';
    _video.style
      ..width = '100%'
      ..height = '100%'
      ..objectFit = 'contain'
      ..display = 'block'
      ..backgroundColor = '#0A1412';

    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int viewId) => _video,
    );
  }

  @override
  void didUpdateWidget(covariant PlaybackVideoView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _video.src = widget.url;
      _video.load();
    }
  }

  @override
  void dispose() {
    _video.pause();
    _video.src = '';
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType);
  }
}
