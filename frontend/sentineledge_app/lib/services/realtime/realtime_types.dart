enum RealtimeStatus { connecting, live, reconnecting, offline }

class RealtimeMessage {
  const RealtimeMessage({required this.type, required this.data});

  final String type;
  final Map<String, dynamic> data;
}

abstract class RealtimeConnection {
  void dispose();
}

typedef RealtimeMessageHandler = void Function(RealtimeMessage message);
typedef RealtimeStatusHandler = void Function(RealtimeStatus status);
