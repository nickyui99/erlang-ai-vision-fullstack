import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'backend_http_client.dart';

class BackendAuthClient {
  BackendAuthClient({http.Client? httpClient})
    : _httpClient = httpClient ?? createBackendHttpClient();

  final http.Client _httpClient;

  Uri get _firebaseLoginUri => Uri.parse('$baseUrl/api/v1/auth/firebase/login');

  static String get baseUrl {
    const configured = String.fromEnvironment('SENTINELEDGE_API_BASE_URL');
    if (configured.isNotEmpty) {
      return configured;
    }
    if (kIsWeb) {
      return 'http://localhost:8000';
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8000';
    }
    return 'http://localhost:8000';
  }

  Future<BackendUser> loginWithFirebaseIdToken(String idToken) async {
    final response = await _httpClient.post(
      _firebaseLoginUri,
      headers: {'Authorization': 'Bearer $idToken'},
    );
    final body = _decodeObject(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw BackendAuthException.fromBody(
        body,
        fallback: 'Backend login failed',
      );
    }
    return BackendUser.fromJson(body['data'] as Map<String, dynamic>);
  }

  Future<void> logout() async {
    await _httpClient.post(Uri.parse('$baseUrl/api/v1/auth/logout'));
  }
}

class SentinelEdgeApiClient {
  SentinelEdgeApiClient({http.Client? httpClient})
    : _httpClient = httpClient ?? createBackendHttpClient();

  final http.Client _httpClient;

  Future<BackendUser> currentUser() async {
    final body = await _getObject('/api/v1/users/me');
    return BackendUser.fromJson(body['data'] as Map<String, dynamic>);
  }

  Future<DeviceRegistration> registerDevice({
    required String name,
    String? location,
  }) async {
    final body = await _postObject('/api/v1/devices', {
      'name': name,
      'location': _emptyToNull(location),
    });
    return DeviceRegistration.fromJson(body['data'] as Map<String, dynamic>);
  }

  /// LAN-reachable host/port for this backend, used to pre-fill the camera
  /// pairing QR (the camera cannot reach `localhost`).
  Future<BackendNetworkInfo> networkInfo() async {
    final body = await _getObject('/api/v1/system/network');
    return BackendNetworkInfo.fromJson(body['data'] as Map<String, dynamic>);
  }

  Future<List<EdgeDevice>> listDevices() async {
    final body = await _getObject('/api/v1/devices');
    final items = body['data'] as List<dynamic>;
    return items
        .map((item) => EdgeDevice.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<EdgeDevice> updateDevice({
    required String deviceId,
    required String name,
    String? location,
  }) async {
    final body = await _putObject('/api/v1/devices/$deviceId', {
      'name': name,
      'location': _emptyToNull(location),
    });
    return EdgeDevice.fromJson(body['data'] as Map<String, dynamic>);
  }

  Future<EdgeDevice> getDevice(String deviceId) async {
    final body = await _getObject('/api/v1/devices/$deviceId');
    return EdgeDevice.fromJson(body['data'] as Map<String, dynamic>);
  }

  /// Relays a pan command (0???180??) to the edge device and returns the result.
  Future<DeviceCommandResult> panDevice(String deviceId, int angle) async {
    final body = await _postObject('/api/v1/devices/$deviceId/pan', {
      'angle': angle,
    });
    return DeviceCommandResult.fromJson(body['data'] as Map<String, dynamic>);
  }

  /// Relays a tilt command (0???180??) to the edge device and returns the result.
  Future<DeviceCommandResult> tiltDevice(String deviceId, int angle) async {
    final body = await _postObject('/api/v1/devices/$deviceId/tilt', {
      'angle': angle,
    });
    return DeviceCommandResult.fromJson(body['data'] as Map<String, dynamic>);
  }

  /// Requests a live snapshot from the edge device.
  Future<DeviceCommandResult> snapshotDevice(String deviceId) async {
    final body = await _postObject('/api/v1/devices/$deviceId/snapshot', null);
    return DeviceCommandResult.fromJson(body['data'] as Map<String, dynamic>);
  }

  /// Mints a short-lived signed URL for the device's live MJPEG stream. The
  /// returned URL is absolute and can be used directly as an `<img>` source.
  Future<LiveStreamUrl> liveStreamUrl(String deviceId) async {
    final body = await _postObject('/api/v1/devices/$deviceId/stream-url', null);
    return LiveStreamUrl.fromJson(body['data'] as Map<String, dynamic>);
  }

  Future<EdgeDevice> sendHeartbeat({
    required String edgeToken,
    required String healthStatus,
    required double rssi,
    required double fps,
    required int currentPan,
    int currentTilt = 90,
  }) async {
    final body = await _postObject(
      '/api/v1/edge/heartbeat',
      {
        'health_status': healthStatus,
        'rssi': rssi,
        'fps': fps,
        'current_pan': currentPan,
        'current_tilt': currentTilt,
      },
      headers: {'Authorization': 'Bearer $edgeToken'},
    );
    return EdgeDevice.fromJson(body['data'] as Map<String, dynamic>);
  }

  Future<SurveillanceAgent> createAgent({
    required String name,
    String? location,
    required String rule,
    String? deviceId,
  }) async {
    final body = await _postObject('/api/v1/agents', {
      'device_id': _emptyToNull(deviceId),
      'name': name,
      'location': _emptyToNull(location),
      'nl_rule': rule,
    });
    return SurveillanceAgent.fromJson(body['data'] as Map<String, dynamic>);
  }

  Future<SurveillanceAgent> updateAgent({
    required String agentId,
    required String name,
    String? location,
    required String rule,
  }) async {
    final body = await _putObject('/api/v1/agents/$agentId', {
      'name': name,
      'location': _emptyToNull(location),
      'nl_rule': rule,
    });
    return SurveillanceAgent.fromJson(body['data'] as Map<String, dynamic>);
  }

  Future<List<SurveillanceAgent>> listAgents() async {
    final body = await _getObject('/api/v1/agents');
    final items = body['data'] as List<dynamic>;
    return items
        .map((item) => SurveillanceAgent.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  /// Assigns a main agent (definition) onto a device, creating a per-camera
  /// sub-agent. Returns the sub-agent.
  Future<SurveillanceAgent> assignAgent(
    String agentId, {
    required String deviceId,
  }) async {
    final body = await _postObject('/api/v1/agents/$agentId/assign', {
      'device_id': deviceId,
    });
    return SurveillanceAgent.fromJson(body['data'] as Map<String, dynamic>);
  }

  /// Unassigns (deletes) the sub-agent for the given definition + device.
  Future<void> unassignAgent(String agentId, {required String deviceId}) async {
    await _postObject('/api/v1/agents/$agentId/unassign', {
      'device_id': deviceId,
    });
  }

  Future<List<EdgeAgentConfig>> activeConfigs(String edgeToken) async {
    final body = await _getObject(
      '/api/v1/edge/agents/active',
      headers: {'Authorization': 'Bearer $edgeToken'},
    );
    final items = body['data'] as List<dynamic>;
    return items
        .map((item) => EdgeAgentConfig.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<SecurityEvent>> listEvents() async {
    final body = await _getObject('/api/v1/events');
    final items = body['data'] as List<dynamic>;
    return items
        .map((item) => SecurityEvent.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<SecurityEvent> getEvent(String eventId) async {
    final body = await _getObject('/api/v1/events/$eventId');
    return SecurityEvent.fromJson(body['data'] as Map<String, dynamic>);
  }

  Future<List<MediaClip>> listEventClips(String eventId) async {
    final body = await _getObject('/api/v1/events/$eventId/clips');
    final items = body['data'] as List<dynamic>;
    return items
        .map((item) => MediaClip.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<ClipPlaybackUrl> signedClipPlaybackUrl(String clipId) async {
    final body = await _postObject('/api/v1/clips/$clipId/signed-url', null);
    return ClipPlaybackUrl.fromJson(body['data'] as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> _getObject(
    String path, {
    Map<String, String>? headers,
  }) async {
    final response = await _httpClient.get(
      Uri.parse('${BackendAuthClient.baseUrl}$path'),
      headers: headers,
    );
    return _handleObject(response);
  }

  Future<Map<String, dynamic>> _postObject(
    String path,
    Map<String, dynamic>? payload, {
    Map<String, String>? headers,
  }) async {
    final requestHeaders = <String, String>{
      if (payload != null) 'Content-Type': 'application/json',
      ...?headers,
    };
    final response = await _httpClient.post(
      Uri.parse('${BackendAuthClient.baseUrl}$path'),
      headers: requestHeaders,
      body: payload == null ? null : jsonEncode(payload),
    );
    return _handleObject(response);
  }

  Future<Map<String, dynamic>> _putObject(
    String path,
    Map<String, dynamic> payload,
  ) async {
    final response = await _httpClient.put(
      Uri.parse('${BackendAuthClient.baseUrl}$path'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
    return _handleObject(response);
  }

  Map<String, dynamic> _handleObject(http.Response response) {
    final body = _decodeObject(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw BackendAuthException.fromBody(
        body,
        fallback: 'Backend request failed',
      );
    }
    return body;
  }
}

Map<String, dynamic> _decodeObject(http.Response response) {
  if (response.body.isEmpty) {
    return <String, dynamic>{};
  }
  final decoded = jsonDecode(response.body);
  if (decoded is Map<String, dynamic>) {
    return decoded;
  }
  return <String, dynamic>{'data': decoded};
}

String? _emptyToNull(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  return trimmed;
}

class BackendAuthException implements Exception {
  BackendAuthException(this.code, this.message);

  final String code;
  final String message;

  factory BackendAuthException.fromBody(
    Map<String, dynamic> body, {
    required String fallback,
  }) {
    final error = body['error'] as Map<String, dynamic>?;
    return BackendAuthException(
      error?['code']?.toString() ?? 'backend_error',
      error?['message']?.toString() ?? fallback,
    );
  }

  @override
  String toString() => '$code: $message';
}

class BackendUser {
  const BackendUser({
    required this.userId,
    required this.email,
    required this.emailVerified,
    required this.role,
    this.displayName,
    this.avatarUrl,
  });

  final String userId;
  final String email;
  final bool emailVerified;
  final String role;
  final String? displayName;
  final String? avatarUrl;

  factory BackendUser.fromJson(Map<String, dynamic> json) {
    return BackendUser(
      userId: json['user_id'].toString(),
      email: json['email'].toString(),
      emailVerified: json['email_verified'] == true,
      role: json['role'].toString(),
      displayName: json['display_name']?.toString(),
      avatarUrl: json['avatar_url']?.toString(),
    );
  }
}

class EdgeDevice {
  const EdgeDevice({
    required this.deviceId,
    required this.name,
    required this.healthStatus,
    required this.currentPan,
    required this.currentTilt,
    this.location,
    this.rssi,
    this.fps,
    this.lastSeen,
  });

  final String deviceId;
  final String name;
  final String? location;
  final String healthStatus;
  final int currentPan;
  final int currentTilt;
  final double? rssi;
  final double? fps;
  final DateTime? lastSeen;

  factory EdgeDevice.fromJson(Map<String, dynamic> json) {
    return EdgeDevice(
      deviceId: json['device_id'].toString(),
      name: json['name'].toString(),
      location: json['location']?.toString(),
      healthStatus: json['health_status'].toString(),
      currentPan: int.tryParse(json['current_pan'].toString()) ?? 90,
      currentTilt: int.tryParse(json['current_tilt'].toString()) ?? 90,
      rssi: _tryDouble(json['rssi']),
      fps: _tryDouble(json['fps']),
      lastSeen: json['last_seen'] == null
          ? null
          : DateTime.tryParse(json['last_seen'].toString()),
    );
  }
}

class DeviceRegistration {
  const DeviceRegistration({required this.device, required this.edgeToken});

  final EdgeDevice device;
  final String edgeToken;

  factory DeviceRegistration.fromJson(Map<String, dynamic> json) {
    return DeviceRegistration(
      device: EdgeDevice.fromJson(json['device'] as Map<String, dynamic>),
      edgeToken: json['edge_token'].toString(),
    );
  }
}

/// Result of relaying a command (pan, snapshot, ???) to an edge device.
class DeviceCommandResult {
  const DeviceCommandResult({
    required this.requestId,
    required this.status,
    required this.payload,
  });

  final String requestId;
  final String status;
  final Map<String, dynamic> payload;

  bool get ok => status == 'ok' || status == 'success';

  factory DeviceCommandResult.fromJson(Map<String, dynamic> json) {
    return DeviceCommandResult(
      requestId: json['request_id'].toString(),
      status: json['status'].toString(),
      payload: Map<String, dynamic>.from(
        json['payload'] as Map? ?? const {},
      ),
    );
  }
}

class SurveillanceAgent {
  const SurveillanceAgent({
    required this.agentId,
    required this.deviceId,
    required this.name,
    required this.rule,
    required this.state,
    required this.enabled,
    required this.compiledEdgeConfig,
    this.location,
    this.parentAgentId,
  });

  final String agentId;
  final String? deviceId;
  final String? parentAgentId;
  final String name;
  final String? location;
  final String rule;
  final String state;
  final bool enabled;
  final Map<String, dynamic> compiledEdgeConfig;

  /// A main agent (definition) created in the Agents tab. Sub-agents created by
  /// assigning to a camera have a [parentAgentId].
  bool get isDefinition => parentAgentId == null;

  factory SurveillanceAgent.fromJson(Map<String, dynamic> json) {
    return SurveillanceAgent(
      agentId: json['agent_id'].toString(),
      deviceId: json['device_id']?.toString(),
      parentAgentId: json['parent_agent_id']?.toString(),
      name: json['name'].toString(),
      location: json['location']?.toString(),
      rule: json['nl_rule'].toString(),
      state: json['state'].toString(),
      enabled: json['enabled'] == true,
      compiledEdgeConfig: Map<String, dynamic>.from(
        json['compiled_edge_config'] as Map? ?? const {},
      ),
    );
  }
}

class EdgeAgentConfig {
  const EdgeAgentConfig({
    required this.agentId,
    required this.deviceId,
    required this.state,
    required this.config,
  });

  final String agentId;
  final String deviceId;
  final String state;
  final Map<String, dynamic> config;

  factory EdgeAgentConfig.fromJson(Map<String, dynamic> json) {
    return EdgeAgentConfig(
      agentId: json['agent_id'].toString(),
      deviceId: json['device_id'].toString(),
      state: json['state'].toString(),
      config: Map<String, dynamic>.from(
        json['compiled_edge_config'] as Map? ?? const {},
      ),
    );
  }
}

class SecurityEvent {
  const SecurityEvent({
    required this.eventId,
    required this.agentId,
    required this.deviceId,
    required this.eventType,
    required this.severity,
    required this.degraded,
    required this.status,
    required this.stage1Result,
    required this.stage2Verdict,
    required this.stage3Verdict,
    this.timestamp,
    this.confidence,
    this.summary,
  });

  final String eventId;
  final String agentId;
  final String deviceId;
  final DateTime? timestamp;
  final String eventType;
  final Map<String, dynamic>? stage1Result;
  final Map<String, dynamic>? stage2Verdict;
  final Map<String, dynamic>? stage3Verdict;
  final String severity;
  final double? confidence;
  final String? summary;
  final bool degraded;
  final String status;

  factory SecurityEvent.fromJson(Map<String, dynamic> json) {
    return SecurityEvent(
      eventId: json['event_id'].toString(),
      agentId: json['agent_id'].toString(),
      deviceId: json['device_id'].toString(),
      timestamp: json['timestamp'] == null
          ? null
          : DateTime.tryParse(json['timestamp'].toString()),
      eventType: json['event_type'].toString(),
      stage1Result: _tryMap(json['stage1_result']),
      stage2Verdict: _tryMap(json['stage2_verdict']),
      stage3Verdict: _tryMap(json['stage3_verdict']),
      severity: json['severity'].toString(),
      confidence: _tryDouble(json['confidence']),
      summary: json['summary']?.toString(),
      degraded: json['degraded'] == true,
      status: json['status'].toString(),
    );
  }
}

class MediaClip {
  const MediaClip({
    required this.clipId,
    required this.eventId,
    required this.deviceId,
    required this.storageType,
    required this.clipType,
    required this.status,
    this.ossObjectKey,
    this.durationSeconds,
    this.fileSizeBytes,
    this.mimeType,
    this.checksumSha256,
    this.uploadCompletedAt,
  });

  final String clipId;
  final String eventId;
  final String deviceId;
  final String storageType;
  final String? ossObjectKey;
  final String clipType;
  final int? durationSeconds;
  final int? fileSizeBytes;
  final String? mimeType;
  final String? checksumSha256;
  final String status;
  final DateTime? uploadCompletedAt;

  factory MediaClip.fromJson(Map<String, dynamic> json) {
    return MediaClip(
      clipId: json['clip_id'].toString(),
      eventId: json['event_id'].toString(),
      deviceId: json['device_id'].toString(),
      storageType: json['storage_type'].toString(),
      ossObjectKey: json['oss_object_key']?.toString(),
      clipType: json['clip_type'].toString(),
      durationSeconds: int.tryParse(json['duration_seconds'].toString()),
      fileSizeBytes: int.tryParse(json['file_size_bytes'].toString()),
      mimeType: json['mime_type']?.toString(),
      checksumSha256: json['checksum_sha256']?.toString(),
      status: json['status'].toString(),
      uploadCompletedAt: json['upload_completed_at'] == null
          ? null
          : DateTime.tryParse(json['upload_completed_at'].toString()),
    );
  }
}

class ClipPlaybackUrl {
  const ClipPlaybackUrl({
    required this.clipId,
    required this.playbackUrl,
    this.expiresAt,
  });

  final String clipId;
  final String playbackUrl;
  final DateTime? expiresAt;

  factory ClipPlaybackUrl.fromJson(Map<String, dynamic> json) {
    return ClipPlaybackUrl(
      clipId: json['clip_id'].toString(),
      playbackUrl: json['playback_url'].toString(),
      expiresAt: json['expires_at'] == null
          ? null
          : DateTime.tryParse(json['expires_at'].toString()),
    );
  }
}

class BackendNetworkInfo {
  const BackendNetworkInfo({this.lanIp, required this.port});

  final String? lanIp;
  final int port;

  factory BackendNetworkInfo.fromJson(Map<String, dynamic> json) {
    return BackendNetworkInfo(
      lanIp: json['lan_ip']?.toString(),
      port: int.tryParse(json['port'].toString()) ?? 8000,
    );
  }
}

class LiveStreamUrl {
  const LiveStreamUrl({required this.streamUrl, this.expiresAt});

  final String streamUrl;
  final DateTime? expiresAt;

  factory LiveStreamUrl.fromJson(Map<String, dynamic> json) {
    return LiveStreamUrl(
      streamUrl: json['stream_url'].toString(),
      expiresAt: json['expires_at'] == null
          ? null
          : DateTime.tryParse(json['expires_at'].toString()),
    );
  }
}

double? _tryDouble(Object? value) {
  if (value == null) {
    return null;
  }
  return double.tryParse(value.toString());
}

Map<String, dynamic>? _tryMap(Object? value) {
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  return null;
}

