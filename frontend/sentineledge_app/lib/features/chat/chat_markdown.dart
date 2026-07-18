import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../design/app_spacing.dart';
import 'ai_agent_icon.dart';

/// Normalizes the delimiter variants commonly returned by model providers so
/// display math gets its own block and inline math stays inline.
String normalizeAssistantMarkdown(String content) {
  var value = content.trim();
  value = value.replaceAllMapped(
    RegExp(r'\\\[(.*?)\\\]', dotAll: true),
    (match) => '\n\n\$\$${match.group(1)!.trim()}\$\$\n\n',
  );
  value = value.replaceAllMapped(
    RegExp(r'\\\((.*?)\\\)', dotAll: true),
    (match) => '\$${match.group(1)!.trim()}\$',
  );
  return value.replaceAll(RegExp(r'\n{3,}'), '\n\n');
}

Color userMessageForeground(Color background) => Colors.white;

class AssistantMessageView extends StatelessWidget {
  const AssistantMessageView({required this.content, super.key});

  final String content;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AnimatedAiAgentIcon(size: 22),
            const SizedBox(width: AppSpacing.xs),
            Text(
              'Erlang AI Agent',
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        MarkdownBody(
          data: normalizeAssistantMarkdown(content),
          selectable: true,
          styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
            p: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurface,
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }
}
