import 'package:flutter/foundation.dart';

import '../../services/backend_auth_client.dart';

/// Owns the Erlang AI Agent chat state: the session list, the active session,
/// its messages, and the in-flight send. Mirrors the app's ChangeNotifier
/// pattern ([SessionController]/[ThemeModeController]).
class ChatController extends ChangeNotifier {
  ChatController({required ErlangVisionApiClient apiClient}) : _api = apiClient;

  final ErlangVisionApiClient _api;

  List<ChatSession> _sessions = const [];
  List<ChatSession> get sessions => _sessions;

  String? _currentSessionId;
  String? get currentSessionId => _currentSessionId;

  List<ChatMessage> _messages = const [];
  List<ChatMessage> get messages => _messages;

  /// True while loading the session list or switching sessions.
  bool _loading = false;
  bool get loading => _loading;

  /// True while a user turn is awaiting the assistant reply.
  bool _sending = false;
  bool get sending => _sending;

  String? _error;
  String? get error => _error;

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Load the user's session list for the drawer, but always open a fresh chat.
  /// Called once when the screen mounts: prior conversations stay reachable via
  /// the end drawer, yet opening the assistant lands on an empty new chat rather
  /// than resurrecting the most recent conversation.
  Future<void> loadSessions() async {
    _loading = true;
    _error = null;
    _notify();
    try {
      _sessions = await _api.listChatSessions();
      _currentSessionId = null;
      _messages = const [];
    } catch (error) {
      _error = error.toString();
    } finally {
      _loading = false;
      _notify();
    }
  }

  /// Switch to an existing session and load its history.
  Future<void> selectSession(String sessionId) async {
    if (sessionId == _currentSessionId && _messages.isNotEmpty) return;
    _currentSessionId = sessionId;
    _messages = const [];
    _loading = true;
    _error = null;
    _notify();
    try {
      _messages = await _api.getChatMessages(sessionId);
    } catch (error) {
      _error = error.toString();
    } finally {
      _loading = false;
      _notify();
    }
  }

  /// Reset to the empty state. The backend session row is created lazily on the
  /// first [sendMessage].
  void startNewSession() {
    _currentSessionId = null;
    _messages = const [];
    _error = null;
    _notify();
  }

  /// Append the user's message, create the session if needed, and append the
  /// assistant's reply. The user bubble shows immediately (optimistic).
  ///
  /// State mutations after an `await` are guarded against the user having
  /// switched sessions mid-send: replies are only appended when the target
  /// session is still the active one, so a reply for conversation A can never
  /// leak into conversation B.
  Future<void> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _sending) return;

    final optimistic = ChatMessage(
      messageId: 'local_user_${_messages.length}',
      role: 'user',
      content: trimmed,
      createdAt: DateTime.now(),
    );
    _messages = [..._messages, optimistic];
    _sending = true;
    _error = null;
    _notify();

    // Non-null once we create a session in this call (for rollback on failure).
    String? createdSessionId;
    try {
      var targetId = _currentSessionId;
      if (targetId == null) {
        final session = await _api.createChatSession();
        targetId = session.sessionId;
        createdSessionId = targetId;
        _currentSessionId = targetId;
        _sessions = [session, ..._sessions];
        _notify();
      }
      final reply = await _api.sendChatMessage(targetId, trimmed);
      // Only touch the visible transcript if we're still on that session.
      if (_currentSessionId == targetId) {
        _messages = [..._messages, reply];
      }
      // Refresh so the drawer reflects the new title and updated ordering.
      _sessions = await _api.listChatSessions();
    } catch (error) {
      _error = error.toString();
      // Roll back an empty session we created in this call that never got a
      // completed turn, so blank "New chat" rows don't accumulate.
      final orphan = createdSessionId;
      if (orphan != null) {
        _sessions = _sessions.where((s) => s.sessionId != orphan).toList();
        if (_currentSessionId == orphan) {
          _currentSessionId = null;
          _messages = const [];
        }
        try {
          await _api.deleteChatSession(orphan);
        } catch (_) {
          // Best-effort cleanup; ignore secondary failure.
        }
      }
    } finally {
      _sending = false;
      _notify();
    }
  }

  /// Delete a session; if it was active, fall back to the newest remaining one
  /// or the empty state.
  Future<void> deleteSession(String sessionId) async {
    try {
      await _api.deleteChatSession(sessionId);
      _sessions = _sessions.where((s) => s.sessionId != sessionId).toList();
      if (_currentSessionId == sessionId) {
        if (_sessions.isNotEmpty) {
          await selectSession(_sessions.first.sessionId);
        } else {
          startNewSession();
        }
      } else {
        _notify();
      }
    } catch (error) {
      _error = error.toString();
      _notify();
    }
  }
}
