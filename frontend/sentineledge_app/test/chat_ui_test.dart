import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:erlang_ai_vision_app/design/app_colors.dart';
import 'package:erlang_ai_vision_app/design/app_theme.dart';
import 'package:erlang_ai_vision_app/features/chat/ai_agent_chat_screen.dart';
import 'package:erlang_ai_vision_app/features/chat/chat_controller.dart';
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

  _thinkingPanelTests();
}

/// The thinking panel: collapsed by default, showing the headline figures, and
/// revealing the model's reasoning and each MCP tool call when opened.
Future<void> _pumpPanel(WidgetTester tester, ChatTrace trace) {
  return tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: ThinkingPanel(trace: trace)),
    ),
  );
}

ChatTrace _sampleTrace() => const ChatTrace(
  steps: [
    ChatTraceStep(
      kind: 'reasoning',
      text: 'I should list the cameras before answering.',
    ),
    ChatTraceStep(
      kind: 'tool',
      name: 'list_devices',
      ok: true,
      result: '6 cameras',
    ),
    ChatTraceStep(
      kind: 'tool',
      name: 'get_device_status',
      ok: false,
      result: 'device_not_found',
    ),
  ],
  toolCount: 2,
  durationMs: 8200,
);

void _thinkingPanelTests() {
  testWidgets('thinking panel starts collapsed and summarises the turn', (
    tester,
  ) async {
    await _pumpPanel(tester, _sampleTrace());
    await tester.pump();

    expect(find.text('Thinking'), findsOneWidget);
    expect(find.text('(2 tools, 8.2s)'), findsOneWidget);
    // Collapsed: neither the reasoning nor the tool rows are mounted yet.
    expect(find.text('list_devices'), findsNothing);
    expect(
      find.text('I should list the cameras before answering.'),
      findsNothing,
    );
  });

  testWidgets('expanding reveals reasoning and every tool call', (
    tester,
  ) async {
    await _pumpPanel(tester, _sampleTrace());
    await tester.pump();

    await tester.tap(find.text('Thinking'));
    await tester.pump();

    expect(
      find.text('I should list the cameras before answering.'),
      findsOneWidget,
    );
    expect(find.text('list_devices'), findsOneWidget);
    expect(find.text('get_device_status'), findsOneWidget);
    // A failed tool is visibly distinct from a successful one.
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a single tool reads "1 tool", not "1 tools"', (tester) async {
    await _pumpPanel(
      tester,
      const ChatTrace(
        steps: [ChatTraceStep(kind: 'tool', name: 'list_agents')],
        toolCount: 1,
        durationMs: 1500,
      ),
    );
    await tester.pump();

    expect(find.text('(1 tool, 1.5s)'), findsOneWidget);
  });

  testWidgets('live panel shows a spinner and the steps so far', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: LiveThinkingPanel(
            steps: const [
              ChatTraceStep(kind: 'reasoning', text: 'Checking the cameras.'),
              ChatTraceStep(kind: 'tool', name: 'list_devices', ok: true),
            ],
            startedAt: DateTime.now(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Thinking'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Checking the cameras.'), findsOneWidget);
    expect(find.text('list_devices'), findsOneWidget);

    // The running clock must not leak a pending timer into the next test.
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('live steps only apply to the in-flight session', () async {
    final api = _SlowChatApi();
    final controller = ChatController(apiClient: api);

    // Nothing is in flight yet, so a step is ignored outright.
    controller.ingestLiveStep('chat_0', {'kind': 'tool', 'name': 'early'});
    expect(controller.liveSteps, isEmpty);

    final sending = controller.sendMessage('hello');
    await Future<void>.delayed(Duration.zero);

    // A step for a different conversation must not bleed in.
    controller.ingestLiveStep('chat_other', {'kind': 'tool', 'name': 'nope'});
    expect(controller.liveSteps, isEmpty);

    controller.ingestLiveStep(controller.currentSessionId!, {
      'kind': 'tool',
      'name': 'list_devices',
      'ok': true,
    });
    expect(controller.liveSteps, hasLength(1));
    expect(controller.liveSteps.single.name, 'list_devices');

    api.complete();
    await sending;

    // The persisted trace on the reply takes over once the turn lands.
    expect(controller.liveSteps, isEmpty);
    controller.dispose();
  });
}

/// A chat API whose send hangs until [complete], so a turn can be inspected
/// while it is still in flight.
class _SlowChatApi extends _FakeChatApi {
  final Completer<void> _gate = Completer<void>();

  void complete() => _gate.complete();

  @override
  Future<ChatMessage> sendChatMessage(String sessionId, String content) async {
    await _gate.future;
    return super.sendChatMessage(sessionId, content);
  }

}
