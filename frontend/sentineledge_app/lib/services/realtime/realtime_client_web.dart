import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../backend_auth_client.dart';
import 'realtime_types.dart';

RealtimeConnection createRealtimeConnection({
  required RealtimeMessageHandler onMessage,
  required RealtimeStatusHandler onStatus,
}) {
  return _WebRealtimeConnection(onMessage: onMessage, onStatus: onStatus);
}

class _WebRealtimeConnection implements RealtimeConnection {
  _WebRealtimeConnection({required this.onMessage, required this.onStatus}) {
    _connect();
  }

  final RealtimeMessageHandler onMessage;
  final RealtimeStatusHandler onStatus;
  web.EventSource? _source;
  bool _disposed = false;
  int _reconnectAttempt = 0;

  void _connect() {
    if (_disposed) {
      return;
    }
    onStatus(
      _reconnectAttempt == 0
          ? RealtimeStatus.connecting
          : RealtimeStatus.reconnecting,
    );
    final url = '${BackendAuthClient.baseUrl}/api/v1/stream/events';
    final source = web.EventSource(
      url,
      web.EventSourceInit(withCredentials: true),
    );
    _source = source;

    source.onOpen.listen((_) {
      _reconnectAttempt = 0;
      onStatus(RealtimeStatus.live);
    });
    source.onError.listen((_) {
      if (_disposed) {
        return;
      }
      onStatus(RealtimeStatus.reconnecting);
      source.close();
      _scheduleReconnect();
    });

    for (final type in const [
      'realtime.connected',
      'event.created',
      'clip.available',
      'device.health_changed',
      'agent.state_changed',
    ]) {
      final listener = ((web.Event event) {
        _handleRealtimeEvent(type, event);
      }).toJS;
      source.addEventListener(type, listener);
    }
  }

  void _handleRealtimeEvent(String type, web.Event event) {
    // EventSource dispatches MessageEvent for named SSE events.
    // ignore: invalid_runtime_check_with_js_interop_types
    final message = event as web.MessageEvent;
    onMessage(RealtimeMessage(type: type, data: _decodeData(message.data)));
  }

  void _scheduleReconnect() {
    _reconnectAttempt += 1;
    final delayMs = (_reconnectAttempt.clamp(1, 5)) * 1000;
    Future<void>.delayed(Duration(milliseconds: delayMs), _connect);
  }

  Map<String, dynamic> _decodeData(Object? data) {
    if (data is String && data.isNotEmpty) {
      final decoded = jsonDecode(data);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    }
    return const {};
  }

  @override
  void dispose() {
    _disposed = true;
    _source?.close();
    _source = null;
    onStatus(RealtimeStatus.offline);
  }
}
