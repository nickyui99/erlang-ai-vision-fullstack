import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentineledge_app/features/dashboard/device_control_view.dart';
import 'package:sentineledge_app/features/dashboard/workspace_view.dart';
import 'package:sentineledge_app/main.dart';
import 'package:sentineledge_app/services/backend_auth_client.dart';

void main() {
  testWidgets('shows sign in action', (WidgetTester tester) async {
    await tester.pumpWidget(const SentinelEdgeApp());
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('SentinelEdge'), findsOneWidget);
    expect(find.text('Sign in with Google'), findsOneWidget);
  });

  testWidgets('renders the camera-first dashboard and opens camera controls', (
    WidgetTester tester,
  ) async {
    final apiClient = _FakeSentinelEdgeApiClient();

    await tester.pumpWidget(
      MaterialApp(
        home: WorkspaceView(
          user: _user,
          apiClient: apiClient,
          onSignOut: () async {},
          autoLoad: false,
          initialDevices: const [_camera],
          initialAgents: const [_rule],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Cameras'), findsWidgets);
    expect(find.text('Front Door'), findsOneWidget);
    expect(find.text('Live ready'), findsOneWidget);
    expect(find.text('Protection'), findsOneWidget);

    final cameraTitle = find.text('Front Door');
    await tester.ensureVisible(cameraTitle);
    await tester.tap(cameraTitle);
    await tester.pumpAndSettle();

    expect(find.text('Snapshot'), findsWidgets);
    expect(find.text('Record'), findsOneWidget);
    expect(find.text('Mute'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();

    expect(find.text('PTZ control'), findsOneWidget);
    expect(find.text('Front Gate'), findsOneWidget);
  });

  testWidgets(
    'camera controls show snapshot result and disabled placeholders',
    (WidgetTester tester) async {
      final apiClient = _FakeSentinelEdgeApiClient();

      await tester.pumpWidget(
        MaterialApp(
          home: DeviceControlView(
            device: _camera,
            apiClient: apiClient,
            agents: const [_rule],
            onChanged: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Record'), findsOneWidget);

      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pumpAndSettle();

      expect(find.text('Pan & Tilt correction'), findsOneWidget);

      await tester.drag(find.byType(ListView), const Offset(0, 500));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Snapshot').first);
      await tester.pumpAndSettle();

      expect(find.text('Latest snapshot'), findsOneWidget);
      expect(find.textContaining('front-door.jpg'), findsOneWidget);
    },
  );
}

const _user = BackendUser(
  userId: 'user-1',
  email: 'owner@example.com',
  emailVerified: true,
  role: 'owner',
  displayName: 'Owner',
);

const _camera = EdgeDevice(
  deviceId: 'camera-1',
  name: 'Front Door',
  location: 'Porch',
  healthStatus: 'online',
  currentPan: 90,
  currentTilt: 90,
  rssi: -52,
  fps: 15,
);

const _rule = SurveillanceAgent(
  agentId: 'rule-1',
  deviceId: null,
  name: 'Person detection',
  rule: 'Alert when a person is at the front door.',
  state: 'armed',
  enabled: true,
  compiledEdgeConfig: {},
);

class _FakeSentinelEdgeApiClient extends SentinelEdgeApiClient {
  _FakeSentinelEdgeApiClient();

  @override
  Future<List<EdgeDevice>> listDevices() async => const [_camera];

  @override
  Future<EdgeDevice> getDevice(String deviceId) async => _camera;

  @override
  Future<List<SurveillanceAgent>> listAgents() async => const [_rule];

  @override
  Future<List<SecurityEvent>> listEvents() async => const [];

  @override
  Future<DeviceCommandResult> snapshotDevice(String deviceId) async {
    return const DeviceCommandResult(
      requestId: 'snapshot-1',
      status: 'ok',
      payload: {'snapshot_path': 'snapshots/front-door.jpg'},
    );
  }

  @override
  Future<DeviceCommandResult> panDevice(String deviceId, int angle) async {
    return const DeviceCommandResult(
      requestId: 'pan-1',
      status: 'ok',
      payload: {},
    );
  }

  @override
  Future<DeviceCommandResult> tiltDevice(String deviceId, int angle) async {
    return const DeviceCommandResult(
      requestId: 'tilt-1',
      status: 'ok',
      payload: {},
    );
  }

  @override
  Future<SurveillanceAgent> assignAgent(
    String agentId, {
    required String deviceId,
  }) async {
    return _rule;
  }

  @override
  Future<void> unassignAgent(
    String agentId, {
    required String deviceId,
  }) async {}
}
