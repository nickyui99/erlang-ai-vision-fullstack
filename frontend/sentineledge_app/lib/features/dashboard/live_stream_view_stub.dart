import 'package:flutter/widgets.dart';

class LiveStreamView extends StatelessWidget {
  const LiveStreamView({required this.url, super.key});

  final String url;

  @override
  Widget build(BuildContext context) {
    return Image.network(url, fit: BoxFit.cover, gaplessPlayback: true);
  }
}
