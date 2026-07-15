import 'package:flutter_test/flutter_test.dart';
import 'package:erlang_ai_vision_app/features/chat/chat_controller.dart';
import 'package:erlang_ai_vision_app/services/backend_auth_client.dart';

/// In-memory stand-in for the backend chat API. Overrides only the chat methods
/// the controller uses; the inherited (unused) http client is harmless in tests.
class _FakeApi extends ErlangVisionApiClient {
  final List<ChatSession> _sessions = [];
  final Map<String, List<ChatMessage>> _messages = {};
  int _seq = 0;

  @override
  Future<List<ChatSession>> listChatSessions() async =>
      List<ChatSession>.from(_sessions);

  @override
  Future<ChatSession> createChatSession({String? firstMessage}) async {
    final id = 'chat_${_seq++}';
    final session = ChatSession(sessionId: id, title: '');
    _sessions.insert(0, session);
    _messages[id] = [];
    return session;
  }

  @override
  Future<List<ChatMessage>> getChatMessages(String sessionId) async =>
      List<ChatMessage>.from(_messages[sessionId] ?? const []);

  @override
  Future<ChatMessage> sendChatMessage(String sessionId, String content) async {
    final list = _messages.putIfAbsent(sessionId, () => []);
    list.add(ChatMessage(
      messageId: 'u${list.length}',
      role: 'user',
      content: content,
    ));
    final reply = ChatMessage(
      messageId: 'a${list.length}',
      role: 'assistant',
      content: 'reply to $content',
    );
    list.add(reply);
    final idx = _sessions.indexWhere((s) => s.sessionId == sessionId);
    if (idx >= 0) {
      _sessions[idx] = ChatSession(sessionId: sessionId, title: content);
    }
    return reply;
  }

  @override
  Future<void> deleteChatSession(String sessionId) async {
    _sessions.removeWhere((s) => s.sessionId == sessionId);
    _messages.remove(sessionId);
  }
}

/// Creates sessions fine but always fails the message send.
class _FailingSendApi extends _FakeApi {
  @override
  Future<ChatMessage> sendChatMessage(String sessionId, String content) async {
    throw Exception('network down');
  }
}

void main() {
  test('loadSessions on an empty account yields the empty state', () async {
    final controller = ChatController(apiClient: _FakeApi());

    await controller.loadSessions();

    expect(controller.sessions, isEmpty);
    expect(controller.currentSessionId, isNull);
    expect(controller.messages, isEmpty);
    expect(controller.loading, isFalse);
  });

  test('sendMessage creates a session and appends both turns', () async {
    final controller = ChatController(apiClient: _FakeApi());
    await controller.loadSessions();

    await controller.sendMessage('Hello');

    expect(controller.currentSessionId, isNotNull);
    expect(controller.sessions, hasLength(1));
    expect(controller.messages.map((m) => m.role).toList(),
        ['user', 'assistant']);
    expect(controller.messages.first.content, 'Hello');
    expect(controller.messages.last.content, 'reply to Hello');
    // The drawer title reflects the first message after the refresh.
    expect(controller.sessions.first.title, 'Hello');
    expect(controller.sending, isFalse);
  });

  test('loadSessions opens a fresh chat but keeps prior sessions in the drawer',
      () async {
    final api = _FakeApi();
    final seed = ChatController(apiClient: api);
    await seed.loadSessions();
    await seed.sendMessage('Persisted question');

    final reopened = ChatController(apiClient: api);
    await reopened.loadSessions();

    // The drawer still lists the prior conversation...
    expect(reopened.sessions, hasLength(1));
    expect(reopened.sessions.first.title, 'Persisted question');
    // ...but the screen opens on an empty new chat, not the old history.
    expect(reopened.currentSessionId, isNull);
    expect(reopened.messages, isEmpty);
  });

  test('selectSession still restores a prior conversation from the drawer',
      () async {
    final api = _FakeApi();
    final seed = ChatController(apiClient: api);
    await seed.loadSessions();
    await seed.sendMessage('Persisted question');
    final priorId = seed.currentSessionId!;

    final reopened = ChatController(apiClient: api);
    await reopened.loadSessions();
    await reopened.selectSession(priorId);

    expect(reopened.currentSessionId, priorId);
    expect(reopened.messages.map((m) => m.content).toList(),
        ['Persisted question', 'reply to Persisted question']);
  });

  test('deleteSession on the active session falls back to empty state',
      () async {
    final controller = ChatController(apiClient: _FakeApi());
    await controller.loadSessions();
    await controller.sendMessage('Doomed');
    final sessionId = controller.currentSessionId!;

    await controller.deleteSession(sessionId);

    expect(controller.sessions, isEmpty);
    expect(controller.currentSessionId, isNull);
    expect(controller.messages, isEmpty);
  });

  test('a failed first send rolls back the orphan session', () async {
    final controller = ChatController(apiClient: _FailingSendApi());
    await controller.loadSessions();

    await controller.sendMessage('Hello');

    expect(controller.error, isNotNull);
    expect(controller.sessions, isEmpty);
    expect(controller.currentSessionId, isNull);
    expect(controller.messages, isEmpty);
    expect(controller.sending, isFalse);
  });

  test('blank input is ignored', () async {
    final controller = ChatController(apiClient: _FakeApi());
    await controller.loadSessions();

    await controller.sendMessage('   ');

    expect(controller.currentSessionId, isNull);
    expect(controller.messages, isEmpty);
    expect(controller.sessions, isEmpty);
  });
}
