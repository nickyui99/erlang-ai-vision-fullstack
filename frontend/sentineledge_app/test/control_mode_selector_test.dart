import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:erlang_ai_vision_app/features/dashboard/device_control_view.dart';
import 'package:erlang_ai_vision_app/services/backend_auth_client.dart';

/// Focused coverage for the per-camera control-mode selector (Off / Auto-track /
/// Agent) added to the device-control screen. Verifies the card renders and that
/// picking a mode calls ErlangVisionApiClient.setControlMode with the right value.
void main() {
  testWidgets('control-mode selector renders and switches mode', (tester) async {
    final api = _FakeApi();

    await tester.pumpWidget(
      MaterialApp(
        home: DeviceControlView(
          device: _camera,
          apiClient: api,
          agents: const [],
          onChanged: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The card sits below the live view / action bar — scroll it into view.
    await tester.scrollUntilVisible(
      find.text('Auto-track'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Camera control'), findsOneWidget);
    expect(find.text('Off'), findsOneWidget);
    expect(find.text('Auto-track'), findsOneWidget);
    expect(find.text('Agent'), findsOneWidget);

    await tester.tap(find.text('Auto-track'));
    await tester.pumpAndSettle();
    expect(api.lastMode, 'auto_track');

    await tester.tap(find.text('Agent'));
    await tester.pumpAndSettle();
    expect(api.lastMode, 'agent');
  });
}

const _camera = EdgeDevice(
  deviceId: 'camera-1',
  name: 'Front Door',
  location: 'Porch',
  healthStatus: 'online',
  currentPan: 90,
  currentTilt: 90,
  controlMode: 'off',
);

class _FakeApi extends ErlangVisionApiClient {
  _FakeApi();

  String? lastMode;

  @override
  Future<List<EdgeDevice>> listDevices() async => const [_camera];

  @override
  Future<EdgeDevice> getDevice(String deviceId) async => _camera;

  @override
  Future<List<SurveillanceAgent>> listAgents() async => const [];

  @override
  Future<List<SecurityEvent>> listEvents() async => const [];

  @override
  Future<EdgeDevice> setControlMode(String deviceId, String mode) async {
    lastMode = mode;
    return EdgeDevice(
      deviceId: _camera.deviceId,
      name: _camera.name,
      location: _camera.location,
      healthStatus: _camera.healthStatus,
      currentPan: _camera.currentPan,
      currentTilt: _camera.currentTilt,
      controlMode: mode,
    );
  }
}
