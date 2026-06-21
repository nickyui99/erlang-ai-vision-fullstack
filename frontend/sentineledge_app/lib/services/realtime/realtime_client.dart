import 'realtime_client_stub.dart'
    if (dart.library.html) 'realtime_client_web.dart';
import 'realtime_types.dart';

export 'realtime_types.dart';

RealtimeConnection connectRealtime({
  required RealtimeMessageHandler onMessage,
  required RealtimeStatusHandler onStatus,
}) {
  return createRealtimeConnection(onMessage: onMessage, onStatus: onStatus);
}
