import 'dart:async';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

class LiveStreamView extends StatefulWidget {
  const LiveStreamView({required this.url, super.key});

  final String url;

  @override
  State<LiveStreamView> createState() => _LiveStreamViewState();
}

class _LiveStreamViewState extends State<LiveStreamView> {
  late final String _viewType;
  late final web.HTMLImageElement _image;
  Timer? _refreshTimer;
  int _frameTick = 0;

  @override
  void initState() {
    super.initState();
    _viewType = 'sentineledge-live-${widget.url.hashCode}-${DateTime.now().microsecondsSinceEpoch}';
    _image = web.HTMLImageElement()..alt = 'Erlang AI Vision live stream';
    _image.style
      ..width = '100%'
      ..height = '100%'
      ..objectFit = 'cover'
      ..display = 'block'
      ..backgroundColor = '#0A1412';

    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) => _image);
    _startFramePolling();
  }

  @override
  void didUpdateWidget(covariant LiveStreamView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _frameTick = 0;
      _startFramePolling();
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _image.src = '';
    super.dispose();
  }

  void _startFramePolling() {
    _refreshTimer?.cancel();
    _setNextFrameUrl();
    _refreshTimer = Timer.periodic(
      const Duration(milliseconds: 150),
      (_) => _setNextFrameUrl(),
    );
  }

  void _setNextFrameUrl() {
    _image.src = _latestFrameUrl(widget.url, _frameTick++);
  }

  String _latestFrameUrl(String streamUrl, int tick) {
    final uri = Uri.parse(streamUrl);
    final path = uri.path.endsWith('/stream')
        ? '${uri.path.substring(0, uri.path.length - '/stream'.length)}/stream-frame'
        : uri.path;
    final query = Map<String, String>.from(uri.queryParameters)
      ..['_frame'] = tick.toString();
    return uri.replace(path: path, queryParameters: query).toString();
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType);
  }
}
