import 'dart:async';

import 'package:flutter/material.dart';

import '../../design/app_colors.dart';
import '../../design/app_spacing.dart';
import '../../services/backend_auth_client.dart';
import '../../shared/console_widgets.dart';
import 'ai_agent_icon.dart';
import 'chat_controller.dart';
import 'chat_markdown.dart';

/// The interactive Erlang AI Agent chat: a scrolling conversation wired to the
/// backend, with a drawer to switch between, start, and delete sessions.
class AiAgentChatScreen extends StatefulWidget {
  const AiAgentChatScreen({
    required this.apiClient,
    required this.user,
    super.key,
  });

  final ErlangVisionApiClient apiClient;
  final BackendUser user;

  @override
  State<AiAgentChatScreen> createState() => _AiAgentChatScreenState();
}

class _AiAgentChatScreenState extends State<AiAgentChatScreen> {
  static const _suggestions = [
    'Which cameras need attention right now?',
    "Summarize today's security events.",
    'Help me create a smarter agent rule.',
    'What should I review before leaving?',
  ];

  late final ChatController _controller = ChatController(
    apiClient: widget.apiClient,
  );
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerChange);
    _controller.loadSessions();
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChange);
    _controller.dispose();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onControllerChange() => _scrollToEnd();

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  String get _firstName {
    final name = widget.user.displayName?.trim();
    if (name != null && name.isNotEmpty) return name.split(' ').first;
    return widget.user.email.split('@').first;
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty || _controller.sending) return;
    _input.clear();
    await _controller.sendMessage(text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final compact = MediaQuery.sizeOf(context).width < AppBreakpoints.compact;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: theme.brightness == Brightness.dark
          ? AppColors.darkBackground
          : scheme.surface,
      appBar: AppBar(
        title: const Text('Erlang AI Agent'),
        actions: [
          if (compact)
            IconButton(
              tooltip: 'Conversations',
              onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
              icon: const Icon(Icons.menu_rounded),
            ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      endDrawer: _buildDrawer(context),
      body: compact
          ? _buildChatBody(theme, compact)
          : Row(
              children: [
                Expanded(child: _buildChatBody(theme, compact)),
                _buildDrawer(context, inline: true),
              ],
            ),
    );
  }

  Widget _buildChatBody(ThemeData theme, bool compact) {
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? AppSpacing.lg : AppSpacing.xxl,
              compact ? AppSpacing.md : AppSpacing.xl,
              compact ? AppSpacing.lg : AppSpacing.xxl,
              AppSpacing.lg,
            ),
            child: ListenableBuilder(
              listenable: _controller,
              builder: (context, _) {
                return Column(
                  children: [
                    Expanded(child: _buildConversation(theme)),
                    if (_controller.error != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      AppBanner(text: _controller.error!),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    _buildComposer(theme),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildConversation(ThemeData theme) {
    final scheme = theme.colorScheme;
    final messages = _controller.messages;

    if (_controller.loading && messages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    // Empty state: the animated orb, greeting, and tappable suggestions.
    if (messages.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: AppSpacing.lg),
          const Center(child: AnimatedAiAgentIcon(size: 86)),
          const SizedBox(height: AppSpacing.xl),
          Text(
            "Hi, I'm Erlang AI Agent.",
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Ask me about your cameras, events, and agent rules, $_firstName.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),
          for (final prompt in _suggestions)
            _SuggestionRow(
              label: prompt,
              onTap: _controller.sending ? null : () => _send(prompt),
            ),
        ],
      );
    }

    return ListView.builder(
      controller: _scroll,
      itemCount: messages.length + (_controller.sending ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= messages.length) {
          return const AiAgentWaitingIndicator();
        }
        final message = messages[index];
        return _ChatBubble(
          role: message.role,
          // Assistant replies arrive as LLM output: Markdown (headers, tables,
          // bold) and LaTeX math — render them. Qwen emits both \(...\)/\[...\]
          // and $...$/$$...$$ delimiters; useDollarSignsForLatex covers the
          // dollar forms too. User messages stay literal text.
          child: message.role == 'assistant'
              ? AssistantMessageView(content: message.content)
              : Text(
                  message.content,
                  style: const TextStyle(color: Colors.white),
                ),
        );
      },
    );
  }

  Widget _buildComposer(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _input,
              enabled: !_controller.sending,
              minLines: 1,
              maxLines: 5,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              decoration: const InputDecoration(
                hintText: 'Ask anything',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                prefixIcon: Icon(Icons.chat_bubble_outline),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          IconButton.filled(
            tooltip: 'Send',
            onPressed: _controller.sending ? null : () => _send(),
            icon: const Icon(Icons.arrow_upward_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawer(BuildContext context, {bool inline = false}) {
    final theme = Theme.of(context);
    return Drawer(
      width: 292,
      child: SafeArea(
        child: ListenableBuilder(
          listenable: _controller,
          builder: (context, _) {
            final sessions = _controller.sessions;
            // Block switching/creating/deleting while a turn is in flight so a
            // pending reply can't be attributed to the wrong conversation.
            final busy = _controller.sending;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Text(
                    'Conversations',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.add_rounded),
                  title: const Text('New chat'),
                  enabled: !busy,
                  onTap: () {
                    _controller.startNewSession();
                    // In the wide layout this is an inline sidebar, not a
                    // modal drawer. Popping there dismisses the entire AI
                    // Agent route and returns the user to the main page.
                    if (!inline) Navigator.of(context).pop();
                  },
                ),
                const Divider(height: 1),
                Expanded(
                  child: sessions.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpacing.lg),
                            child: Text(
                              'No conversations yet.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: sessions.length,
                          itemBuilder: (context, index) {
                            final session = sessions[index];
                            final selected =
                                session.sessionId ==
                                _controller.currentSessionId;
                            return ListTile(
                              selected: selected,
                              enabled: !busy,
                              title: Text(
                                session.title.isEmpty
                                    ? 'New chat'
                                    : session.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(_relativeTime(session.updatedAt)),
                              trailing: IconButton(
                                tooltip: 'Delete',
                                icon: const Icon(Icons.delete_outline_rounded),
                                onPressed: busy
                                    ? null
                                    : () => _confirmDelete(context, session),
                              ),
                              onTap: () {
                                _controller.selectSession(session.sessionId);
                                if (!inline) Navigator.of(context).pop();
                              },
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, ChatSession session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete conversation?'),
        content: Text(
          session.title.isEmpty
              ? 'This conversation will be permanently deleted.'
              : '"${session.title}" will be permanently deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _controller.deleteSession(session.sessionId);
    }
  }

  static String _relativeTime(DateTime? time) {
    if (time == null) return '';
    final delta = DateTime.now().difference(time.toLocal());
    if (delta.inMinutes < 1) return 'Just now';
    if (delta.inMinutes < 60) return '${delta.inMinutes}m ago';
    if (delta.inHours < 24) return '${delta.inHours}h ago';
    if (delta.inDays < 7) return '${delta.inDays}d ago';
    return '${time.toLocal().year}-'
        '${time.toLocal().month.toString().padLeft(2, '0')}-'
        '${time.toLocal().day.toString().padLeft(2, '0')}';
  }
}

/// A user/assistant message bubble, aligned and coloured by role.
class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.role, required this.child});

  final String role;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isUser = role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.72,
        ),
        decoration: BoxDecoration(
          color: isUser
              ? scheme.primary
              : (theme.brightness == Brightness.dark
                    ? scheme.surfaceContainerHighest
                    : scheme.surfaceContainerLow),
          // A width-0 BorderSide is a "hairline" border, which Flutter refuses
          // to paint with a borderRadius (assertion in debug; the exception
          // aborts paint before the bubble's text is drawn). User bubbles must
          // carry no border at all.
          border: isUser
              ? null
              : Border(
                  left: BorderSide(
                    color: scheme.primary.withValues(alpha: 0.55),
                    width: 3,
                  ),
                ),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(isUser ? 14 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 14),
          ),
        ),
        child: DefaultTextStyle.merge(
          style: theme.textTheme.bodyMedium?.copyWith(
            color: isUser
                ? userMessageForeground(scheme.primary)
                : scheme.onSurface,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// A tappable prompt suggestion shown in the empty state.
class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.subdirectory_arrow_right_rounded,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Communicates model work without exposing internal implementation details.
class AiAgentWaitingIndicator extends StatefulWidget {
  const AiAgentWaitingIndicator({super.key});

  @override
  State<AiAgentWaitingIndicator> createState() =>
      _AiAgentWaitingIndicatorState();
}

class _AiAgentWaitingIndicatorState extends State<AiAgentWaitingIndicator>
    with SingleTickerProviderStateMixin {
  static const _messages = [
    'Erlang is thinking...',
    'Reviewing your camera context...',
    'Shaping a useful answer...',
  ];
  Timer? _messageTimer;
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);
  var _messageIndex = 0;

  @override
  void initState() {
    super.initState();
    _messageTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _rotateMessage(),
    );
  }

  void _rotateMessage() {
    if (!mounted) return;
    setState(() => _messageIndex = (_messageIndex + 1) % _messages.length);
  }

  @override
  void dispose() {
    _messageTimer?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      label: 'Erlang is thinking',
      liveRegion: true,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) => Container(
          margin: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: scheme.primaryContainer.withValues(alpha: 0.45),
            borderRadius: AppRadius.mdAll,
            border: Border.all(color: scheme.primary.withValues(alpha: 0.18)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Opacity(
                opacity: 0.55 + (_pulse.value * 0.45),
                child: const AnimatedAiAgentIcon(size: 24),
              ),
              const SizedBox(width: AppSpacing.sm),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                child: Text(
                  _messages[_messageIndex],
                  key: ValueKey(_messageIndex),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
