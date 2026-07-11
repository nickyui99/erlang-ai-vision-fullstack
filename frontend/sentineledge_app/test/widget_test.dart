import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:erlang_ai_vision_app/app/app_router.dart';
import 'package:erlang_ai_vision_app/app/session_controller.dart';
import 'package:erlang_ai_vision_app/features/auth/login_page.dart';
import 'package:erlang_ai_vision_app/features/dashboard/console_page.dart';
import 'package:erlang_ai_vision_app/features/dashboard/device_control_view.dart';
import 'package:erlang_ai_vision_app/features/dashboard/workspace_view.dart';
import 'package:erlang_ai_vision_app/features/landing/landing_page.dart';
import 'package:erlang_ai_vision_app/services/backend_auth_client.dart';

/// Hosts [child] under a [SessionScope] and a minimal [GoRouter] that also
/// serves the camera-detail route, so widgets that navigate with `context.go`
/// / `context.push` work in tests.
Widget _routerHost(Widget child, {required ErlangVisionApiClient apiClient}) {
  final session = SessionController(apiClient: apiClient);
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (context, state) => child),
      GoRoute(
        path: '/console/cameras/:deviceId',
        builder: (context, state) =>
            DeviceControlPage(deviceId: state.pathParameters['deviceId']!),
      ),
    ],
  );
  return SessionScope(
    controller: session,
    child: MaterialApp.router(routerConfig: router),
  );
}

/// Pumps a couple of frames with a fixed duration. Used instead of
/// [WidgetTester.pumpAndSettle] for the router-hosted test: go_router keeps a
/// frame scheduled, so pumpAndSettle never returns.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  testWidgets('native root route opens login instead of landing page', (
    WidgetTester tester,
  ) async {
    final session = SessionController(apiClient: _SignedOutApiClient());

    await tester.pumpWidget(
      SessionScope(
        controller: session,
        child: MaterialApp.router(routerConfig: AppRouter.build(session)),
      ),
    );
    await _settle(tester);

    expect(find.byType(LandingPage), findsNothing);
    expect(find.text('Welcome back'), findsOneWidget);
  });

  testWidgets('shows sign in action', (WidgetTester tester) async {
    final session = SessionController(apiClient: _FakeErlangVisionApiClient());
    await tester.pumpWidget(
      SessionScope(
        controller: session,
        child: const MaterialApp(home: LoginPage()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Erlang AI Vision'), findsOneWidget);
    expect(find.text('Sign in with Google'), findsOneWidget);
    expect(find.text('Back to home'), findsNothing);
  });

  testWidgets('renders the camera-first dashboard and opens camera controls', (
    WidgetTester tester,
  ) async {
    final apiClient = _FakeErlangVisionApiClient();

    await tester.pumpWidget(
      _routerHost(
        WorkspaceView(
          user: _user,
          apiClient: apiClient,
          onSignOut: () async {},
          autoLoad: false,
          initialDevices: const [_camera],
          initialAgents: const [_rule],
        ),
        apiClient: apiClient,
      ),
    );
    await _settle(tester);

    expect(find.text('Cameras'), findsWidgets);
    expect(find.text('Front Door'), findsOneWidget);
    expect(find.text('Live'), findsOneWidget);

    final cameraTitle = find.text('Front Door');
    await tester.ensureVisible(cameraTitle);
    await tester.tap(cameraTitle);
    await _settle(tester);

    expect(find.text('Snapshot'), findsWidgets);
    expect(find.text('Record'), findsOneWidget);
    expect(find.text('Mute'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await _settle(tester);

    expect(find.byTooltip('Pan left'), findsOneWidget);
    expect(find.text('Person detection'), findsOneWidget);
  });

  testWidgets('camera controls show snapshot result and PTZ controls', (
    WidgetTester tester,
  ) async {
    final apiClient = _FakeErlangVisionApiClient();

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

    expect(find.byTooltip('Favorite camera'), findsOneWidget);
    expect(find.text('Record'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Tilt up'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, 500));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Snapshot').first);
    await tester.pumpAndSettle();

    expect(find.text('Latest snapshot'), findsOneWidget);
    expect(find.textContaining('front-door.jpg'), findsOneWidget);
  });
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

class _FakeErlangVisionApiClient extends ErlangVisionApiClient {
  _FakeErlangVisionApiClient();

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

class _SignedOutApiClient extends _FakeErlangVisionApiClient {
  @override
  Future<BackendUser> currentUser() async {
    throw BackendAuthException('not_authenticated', 'No active session.');
  }
}
