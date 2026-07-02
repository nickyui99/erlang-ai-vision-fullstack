import 'package:flutter/material.dart';

import '../../../design/app_spacing.dart';

class PlaybackVideoView extends StatelessWidget {
  const PlaybackVideoView({required this.url, super.key});

  final String url;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: AppRadius.mdAll,
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Text(
          'In-app playback is available on web. Use Open to play this clip on this platform.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall,
        ),
      ),
    );
  }
}
