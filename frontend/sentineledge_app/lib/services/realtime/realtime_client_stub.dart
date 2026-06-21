import 'realtime_types.dart';

RealtimeConnection createRealtimeConnection({
  required RealtimeMessageHandler onMessage,
  required RealtimeStatusHandler onStatus,
}) {
  onStatus(RealtimeStatus.offline);
  return _NoopRealtimeConnection();
}

class _NoopRealtimeConnection implements RealtimeConnection {
  @override
  void dispose() {}
}
