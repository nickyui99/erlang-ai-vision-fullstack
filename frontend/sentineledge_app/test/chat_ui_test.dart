import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:erlang_ai_vision_app/design/app_colors.dart';
import 'package:erlang_ai_vision_app/design/app_theme.dart';
import 'package:erlang_ai_vision_app/features/chat/ai_agent_chat_screen.dart';
import 'package:erlang_ai_vision_app/features/chat/chat_markdown.dart';
import 'package:erlang_ai_vision_app/services/backend_auth_client.dart';

/// In-memory chat API so the screen can run a full send turn in tests.
class _FakeChatApi extends ErlangVisionApiClient {
  final Map<String, List<ChatMessage>> _messages = {};
  final List<ChatSession> _sessions = [];
  int _seq = 0;

  @override
  Future<List<ChatSession>> listChatSessions() async =>
      List<ChatSession>.from(_sessions);

  @override
  Future<ChatSession> createChatSession({String? firstMessage}) async {
    final session = ChatSession(sessionId: 'chat_${_seq++}', title: '');
    _sessions.insert(0, session);
    _messages[session.sessionId] = [];
    return session;
  }

  @override
  Future<List<ChatMessage>> getChatMessages(String sessionId) async =>
      List<ChatMessage>.from(_messages[sessionId] ?? const []);

  @override
  Future<ChatMessage> sendChatMessage(String sessionId, String content) async {
    final list = _messages.putIfAbsent(sessionId, () => []);
    list.add(ChatMessage(messageId: 'u', role: 'user', content: content));
    final reply = ChatMessage(
      messageId: 'a',
      role: 'assistant',
      content: 'reply to $content',
    );
    list.add(reply);
    return reply;
  }

  @override
  Future<void> deleteChatSession(String sessionId) async {
    _sessions.removeWhere((s) => s.sessionId == sessionId);
    _messages.remove(sessionId);
  }
}

const _testUser = BackendUser(
  userId: 'u1',
  email: 'tester@example.com',
  emailVerified: true,
  role: 'user',
);

void main() {
  testWidgets('waiting indicator explains that Erlang is working', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AiAgentWaitingIndicator())),
    );

    expect(find.text('Erlang is thinking...'), findsOneWidget);
  });

  test('normalizes display math delimiters for the renderer', () {
    expect(
      normalizeAssistantMarkdown(r'Area \[x^2 + y^2\]'),
      contains(r'$$x^2 + y^2$$'),
    );
  });

  test('uses white text for user message bubbles', () {
    expect(userMessageForeground(AppColors.primary), Colors.white);
    expect(userMessageForeground(Colors.white), Colors.white);
    expect(userMessageForeground(Colors.black), Colors.white);
  });

  // Regression: the user bubble's decoration once used a width-0 BorderSide as
  // its "no border" state; Flutter treats that as a hairline border, which
  // asserts when combined with a borderRadius and aborts paint before the
  // message text is drawn (an apparently empty red bubble).
  testWidgets('user message bubble paints its text', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: AiAgentChatScreen(apiClient: _FakeChatApi(), user: _testUser),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'hello erlang');
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    await tester.pump();
    // Let the post-send scroll-to-end animation finish.
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('hello erlang'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
