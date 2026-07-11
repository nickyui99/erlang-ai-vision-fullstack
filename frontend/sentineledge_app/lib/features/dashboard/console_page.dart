import 'package:flutter/material.dart';

import '../../app/session_controller.dart';
import '../../services/backend_auth_client.dart';
import 'device_control_view.dart';
import 'workspace_view.dart';

/// Route host for `/console/:section` (and `/console/events/:eventId`). Reads the
/// authenticated user from [SessionScope] and hands the current section +
/// selection down to the single, long-lived [WorkspaceView]. The router gives
/// every section route the same page key, so this widget (and the workspace
/// state it owns: realtime stream, loaded devices/agents/events) is reused as
/// the URL changes rather than rebuilt.
class ConsolePage extends StatelessWidget {
  const ConsolePage({
    required this.section,
    this.selectedEventId,
    super.key,
  });

  final WorkspaceSection section;
  final String? selectedEventId;

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    final user = session.user;
    if (user == null) {
      // Session restore is still in flight; the redirect guard will move us to
      // /login if it resolves signed-out.
      return const _ConsoleLoading();
    }
    return WorkspaceView(
      key: const ValueKey('workspace'),
      user: user,
      apiClient: session.apiClient,
      onSignOut: session.signOut,
      section: section,
      selectedEventId: selectedEventId,
    );
  }
}

/// Route host for `/console/cameras/:deviceId`. Deep-link safe: loads the device
/// (and agent definitions, needed for protection assignment) by id so the
/// camera detail screen survives a page refresh.
class DeviceControlPage extends StatefulWidget {
  const DeviceControlPage({required this.deviceId, super.key});

  final String deviceId;

  @override
  State<DeviceControlPage> createState() => _DeviceControlPageState();
}

class _DeviceControlPageState extends State<DeviceControlPage> {
  ErlangVisionApiClient? _apiClient;
  EdgeDevice? _device;
  List<SurveillanceAgent> _agents = const [];
  Object? _error;
  bool _loading = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reading an InheritedWidget must happen here, not in initState.
    if (_apiClient != null) return;
    _apiClient = SessionScope.of(context).apiClient;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final apiClient = _apiClient!;
    try {
      final device = await apiClient.getDevice(widget.deviceId);
      final agents = await apiClient.listAgents();
      if (!mounted) return;
      setState(() {
        _device = device;
        _agents = agents;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final device = _device;
    if (_loading) {
      return const _ConsoleLoading();
    }
    if (device == null) {
      return _ConsoleMessage(
        icon: Icons.videocam_off_outlined,
        title: 'Camera unavailable',
        message: _error?.toString() ?? 'This camera could not be loaded.',
        onRetry: _load,
      );
    }
    return DeviceControlView(
      device: device,
      apiClient: _apiClient!,
      agents: _agents,
      onChanged: _load,
    );
  }
}

class _ConsoleLoading extends StatelessWidget {
  const _ConsoleLoading();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

class _ConsoleMessage extends StatelessWidget {
  const _ConsoleMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, color: theme.colorScheme.outline),
              const SizedBox(height: 16),
              Text(title, style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
