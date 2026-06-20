import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'firebase_options.dart';
import 'services/backend_auth_client.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (DefaultFirebaseOptions.isConfigured) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    if (!kIsWeb) {
      await GoogleSignIn.instance.initialize();
    }
  }
  runApp(const SentinelEdgeApp());
}

class SentinelEdgeApp extends StatelessWidget {
  const SentinelEdgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF315A52);
    return MaterialApp(
      title: 'SentinelEdge',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF6F7F4),
        cardTheme: CardThemeData(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: Color(0xFFD9DED7)),
          ),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
          isDense: true,
        ),
        useMaterial3: true,
      ),
      home: const AuthShell(),
    );
  }
}

class AuthShell extends StatefulWidget {
  const AuthShell({super.key});

  @override
  State<AuthShell> createState() => _AuthShellState();
}

class _AuthShellState extends State<AuthShell> {
  final BackendAuthClient _authClient = BackendAuthClient();
  final SentinelEdgeApiClient _apiClient = SentinelEdgeApiClient();
  BackendUser? _backendUser;
  String? _error;
  bool _isLoading = false;

  Future<void> _signIn() async {
    if (!DefaultFirebaseOptions.isConfigured) {
      setState(() => _error = 'Firebase options are not configured yet.');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final userCredential = await _signInWithGoogle();
      final idToken = await userCredential.user?.getIdToken();
      if (idToken == null || idToken.isEmpty) {
        throw StateError('Firebase did not return an ID token.');
      }
      final backendUser = await _authClient.loginWithFirebaseIdToken(idToken);
      setState(() => _backendUser = backendUser);
    } catch (error) {
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<UserCredential> _signInWithGoogle() async {
    final auth = FirebaseAuth.instance;
    if (kIsWeb) {
      return auth.signInWithPopup(GoogleAuthProvider());
    }

    final googleUser = await GoogleSignIn.instance.authenticate();
    final googleAuth = googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      idToken: googleAuth.idToken,
    );
    return auth.signInWithCredential(credential);
  }

  Future<void> _signOut() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      await _authClient.logout();
      await FirebaseAuth.instance.signOut();
      if (!kIsWeb) {
        await GoogleSignIn.instance.signOut();
      }
      setState(() => _backendUser = null);
    } catch (error) {
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _backendUser;
    return Scaffold(
      body: SafeArea(
        child: user == null
            ? _SignInView(
                error: _error,
                isLoading: _isLoading,
                onSignIn: _signIn,
              )
            : WorkspaceView(
                user: user,
                apiClient: _apiClient,
                onSignOut: _signOut,
              ),
      ),
    );
  }
}

class _SignInView extends StatelessWidget {
  const _SignInView({
    required this.error,
    required this.isLoading,
    required this.onSignIn,
  });

  final String? error;
  final bool isLoading;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _ProductHeader(),
              const SizedBox(height: 28),
              if (!DefaultFirebaseOptions.isConfigured) const _SetupNotice(),
              FilledButton.icon(
                onPressed: isLoading ? null : onSignIn,
                icon: isLoading
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.login),
                label: Text(isLoading ? 'Signing in' : 'Sign in with Google'),
              ),
              if (error != null) ...[
                const SizedBox(height: 16),
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 18),
              Text(
                'Backend: ${BackendAuthClient.baseUrl}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class WorkspaceView extends StatefulWidget {
  const WorkspaceView({
    required this.user,
    required this.apiClient,
    required this.onSignOut,
    super.key,
  });

  final BackendUser user;
  final SentinelEdgeApiClient apiClient;
  final Future<void> Function() onSignOut;

  @override
  State<WorkspaceView> createState() => _WorkspaceViewState();
}

class _WorkspaceViewState extends State<WorkspaceView> {
  final _deviceNameController = TextEditingController(
    text: 'Front Door Camera',
  );
  final _deviceLocationController = TextEditingController(text: 'Front Door');
  final _agentNameController = TextEditingController(
    text: 'Night Front Door Watch',
  );
  final _agentLocationController = TextEditingController(text: 'Front Door');
  final _ruleController = TextEditingController(
    text: 'Alert me if a person is lingering near the front door after 10 PM.',
  );
  final _edgeTokenController = TextEditingController();

  List<EdgeDevice> _devices = const [];
  List<SurveillanceAgent> _agents = const [];
  List<EdgeAgentConfig> _activeConfigs = const [];
  String? _selectedDeviceId;
  String? _selectedAgentId;
  String? _lastEdgeToken;
  String? _message;
  String? _error;
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
    _refreshAll();
  }

  @override
  void dispose() {
    _deviceNameController.dispose();
    _deviceLocationController.dispose();
    _agentNameController.dispose();
    _agentLocationController.dispose();
    _ruleController.dispose();
    _edgeTokenController.dispose();
    super.dispose();
  }

  Future<void> _run(
    String successMessage,
    Future<void> Function() action,
  ) async {
    setState(() {
      _isBusy = true;
      _error = null;
      _message = null;
    });
    try {
      await action();
      setState(() => _message = successMessage);
    } catch (error) {
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  Future<void> _refreshAll() async {
    await _run('Dashboard refreshed', () async {
      final devices = await widget.apiClient.listDevices();
      final agents = await widget.apiClient.listAgents();
      setState(() {
        _devices = devices;
        _agents = agents;
        _selectedDeviceId = _chooseExisting(
          _selectedDeviceId,
          devices.map((device) => device.deviceId),
        );
        _selectedAgentId = _chooseExisting(
          _selectedAgentId,
          agents.map((agent) => agent.agentId),
        );
        _activeConfigs = const [];
      });
    });
  }

  Future<void> _registerDevice() async {
    await _run(
      'Device registered. Copy the edge token now; it is only returned once.',
      () async {
        final registration = await widget.apiClient.registerDevice(
          name: _deviceNameController.text,
          location: _deviceLocationController.text,
        );
        final devices = await widget.apiClient.listDevices();
        setState(() {
          _lastEdgeToken = registration.edgeToken;
          _edgeTokenController.text = registration.edgeToken;
          _devices = devices;
          _selectedDeviceId = registration.device.deviceId;
        });
      },
    );
  }

  Future<void> _sendHeartbeat() async {
    final token = _edgeTokenController.text.trim();
    if (token.isEmpty) {
      setState(() => _error = 'Paste an edge token before sending heartbeat.');
      return;
    }
    await _run('Heartbeat accepted', () async {
      await widget.apiClient.sendHeartbeat(
        edgeToken: token,
        healthStatus: 'online',
        rssi: -58.2,
        fps: 15,
        currentPan: 90,
      );
      final devices = await widget.apiClient.listDevices();
      setState(() => _devices = devices);
    });
  }

  Future<void> _createAgent() async {
    final deviceId = _selectedDeviceId;
    if (deviceId == null) {
      setState(
        () => _error = 'Register or select a device before creating an agent.',
      );
      return;
    }
    await _run('Agent created', () async {
      final agent = await widget.apiClient.createAgent(
        deviceId: deviceId,
        name: _agentNameController.text,
        location: _agentLocationController.text,
        rule: _ruleController.text,
      );
      final agents = await widget.apiClient.listAgents();
      setState(() {
        _agents = agents;
        _selectedAgentId = agent.agentId;
      });
    });
  }

  Future<void> _setAgentState(bool armed) async {
    final agentId = _selectedAgentId;
    if (agentId == null) {
      setState(() => _error = 'Select an agent first.');
      return;
    }
    await _run(armed ? 'Agent armed' : 'Agent disarmed', () async {
      if (armed) {
        await widget.apiClient.armAgent(agentId);
      } else {
        await widget.apiClient.disarmAgent(agentId);
      }
      final agents = await widget.apiClient.listAgents();
      setState(() => _agents = agents);
    });
  }

  Future<void> _pullActiveConfigs() async {
    final token = _edgeTokenController.text.trim();
    if (token.isEmpty) {
      setState(
        () => _error = 'Paste an edge token before pulling active configs.',
      );
      return;
    }
    await _run('Active configs pulled', () async {
      final configs = await widget.apiClient.activeConfigs(token);
      setState(() => _activeConfigs = configs);
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 980;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _WorkspaceHeader(
                    user: widget.user,
                    isBusy: _isBusy,
                    onRefresh: _refreshAll,
                    onSignOut: widget.onSignOut,
                  ),
                  const SizedBox(height: 16),
                  if (_error != null)
                    _StatusBanner(text: _error!, isError: true),
                  if (_message != null)
                    _StatusBanner(text: _message!, isError: false),
                  const SizedBox(height: 8),
                  _summaryPanel(),
                  const SizedBox(height: 16),
                  if (wide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _devicePanel()),
                        const SizedBox(width: 16),
                        Expanded(child: _agentPanel()),
                      ],
                    )
                  else ...[
                    _devicePanel(),
                    const SizedBox(height: 16),
                    _agentPanel(),
                  ],
                  const SizedBox(height: 16),
                  _edgePanel(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _summaryPanel() {
    final onlineDevices = _devices
        .where((device) => device.healthStatus == 'online')
        .length;
    final armedAgents = _agents.where((agent) => agent.state == 'armed').length;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _MetricCard(
          label: 'Devices',
          value: _devices.length.toString(),
          icon: Icons.videocam_outlined,
        ),
        _MetricCard(
          label: 'Online',
          value: onlineDevices.toString(),
          icon: Icons.sensors_outlined,
        ),
        _MetricCard(
          label: 'Agents',
          value: _agents.length.toString(),
          icon: Icons.radar_outlined,
        ),
        _MetricCard(
          label: 'Armed',
          value: armedAgents.toString(),
          icon: Icons.shield_outlined,
        ),
      ],
    );
  }

  Widget _devicePanel() {
    return _Panel(
      title: 'Devices',
      icon: Icons.videocam_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _deviceNameController,
                  decoration: const InputDecoration(labelText: 'Device name'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _deviceLocationController,
                  decoration: const InputDecoration(labelText: 'Location'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _isBusy ? null : _registerDevice,
            icon: const Icon(Icons.add_circle_outline),
            label: const Text('Add device'),
          ),
          if (_lastEdgeToken != null) ...[
            const SizedBox(height: 12),
            _TokenBox(token: _lastEdgeToken!),
          ],
          const SizedBox(height: 16),
          if (_devices.isEmpty)
            const _EmptyState(text: 'No devices registered yet.')
          else
            ..._devices.map(
              (device) => _SelectableTile(
                selected: _selectedDeviceId == device.deviceId,
                title: device.name,
                subtitle:
                    '${device.location ?? 'No location'} - ${device.healthStatus} - pan ${device.currentPan}',
                trailing: device.fps == null
                    ? null
                    : '${device.fps!.toStringAsFixed(1)} fps',
                onTap: () =>
                    setState(() => _selectedDeviceId = device.deviceId),
              ),
            ),
        ],
      ),
    );
  }

  Widget _agentPanel() {
    return _Panel(
      title: 'Agents',
      icon: Icons.radar_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _agentNameController,
                  decoration: const InputDecoration(labelText: 'Agent name'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _agentLocationController,
                  decoration: const InputDecoration(labelText: 'Location'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _ruleController,
            minLines: 3,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Natural language rule',
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _isBusy ? null : _createAgent,
            icon: const Icon(Icons.add_task_outlined),
            label: const Text('New agent'),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isBusy ? null : () => _setAgentState(true),
                  icon: const Icon(Icons.play_arrow_outlined),
                  label: const Text('Arm'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isBusy ? null : () => _setAgentState(false),
                  icon: const Icon(Icons.pause_outlined),
                  label: const Text('Disarm'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_agents.isEmpty)
            const _EmptyState(text: 'No agents created yet.')
          else
            ..._agents.map(
              (agent) => _SelectableTile(
                selected: _selectedAgentId == agent.agentId,
                title: agent.name,
                subtitle: '${agent.state} - ${agent.rule}',
                trailing: agent.enabled ? 'enabled' : 'disabled',
                onTap: () => setState(() => _selectedAgentId = agent.agentId),
              ),
            ),
        ],
      ),
    );
  }

  Widget _edgePanel() {
    return _Panel(
      title: 'Edge setup',
      icon: Icons.hub_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _edgeTokenController,
            decoration: const InputDecoration(labelText: 'Edge token'),
            obscureText: true,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: _isBusy ? null : _sendHeartbeat,
                icon: const Icon(Icons.favorite_border),
                label: const Text('Check connection'),
              ),
              OutlinedButton.icon(
                onPressed: _isBusy ? null : _pullActiveConfigs,
                icon: const Icon(Icons.download_outlined),
                label: const Text('Sync active agents'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_activeConfigs.isEmpty)
            const _EmptyState(
              text:
                  'No active agents synced yet. Arm an agent, then sync active agents.',
            )
          else
            ..._activeConfigs.map(
              (config) => _ActiveConfigTile(config: config),
            ),
        ],
      ),
    );
  }
}

String? _chooseExisting(String? current, Iterable<String> candidates) {
  final values = candidates.toList();
  if (current != null && values.contains(current)) {
    return current;
  }
  return values.isEmpty ? null : values.first;
}

class _WorkspaceHeader extends StatelessWidget {
  const _WorkspaceHeader({
    required this.user,
    required this.isBusy,
    required this.onRefresh,
    required this.onSignOut,
  });

  final BackendUser user;
  final bool isBusy;
  final VoidCallback onRefresh;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.shield_outlined, size: 34),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SentinelEdge Dashboard',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '${user.displayName ?? user.email} - ${BackendAuthClient.baseUrl}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        IconButton.filledTonal(
          onPressed: isBusy ? null : onRefresh,
          tooltip: 'Refresh',
          icon: const Icon(Icons.refresh),
        ),
        const SizedBox(width: 8),
        IconButton.outlined(
          onPressed: isBusy ? null : onSignOut,
          tooltip: 'Sign out',
          icon: const Icon(Icons.logout),
        ),
      ],
    );
  }
}

class _ProductHeader extends StatelessWidget {
  const _ProductHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.shield_outlined,
          size: 42,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 16),
        Text(
          'SentinelEdge',
          style: Theme.of(
            context,
          ).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          'Manage devices and surveillance agents from one clean workspace.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ],
    );
  }
}

class _SetupNotice extends StatelessWidget {
  const _SetupNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E0),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2B84C)),
      ),
      child: const Text(
        'Fill lib/firebase_options.dart with Firebase app settings before using Google sign-in.',
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.icon, required this.child});

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 180,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(label, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActiveConfigTile extends StatelessWidget {
  const _ActiveConfigTile({required this.config});

  final EdgeAgentConfig config;

  @override
  Widget build(BuildContext context) {
    final detectors =
        (config.config['detectors'] as List?)?.join(', ') ?? 'detector';
    final ruleText =
        config.config['rule_text']?.toString() ?? 'Active surveillance rule';
    final confidence = config.config['min_confidence']?.toString() ?? 'default';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAF7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFDDE2DA)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.tune_outlined,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Active config for ${config.agentId}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text('$detectors - confidence $confidence'),
                Text(ruleText, maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          _StatusPill(label: config.state, color: const Color(0xFF2E7D5B)),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _SelectableTile extends StatelessWidget {
  const _SelectableTile({
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  final bool selected;
  final String title;
  final String subtitle;
  final String? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? const Color(0xFFE5EFEA) : const Color(0xFFF8FAF7),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    trailing!,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TokenBox extends StatelessWidget {
  const _TokenBox({required this.token});

  final String token;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF101A17),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'One-time edge token',
            style: TextStyle(
              color: Color(0xFFB9D8CC),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          SelectableText(
            token,
            style: const TextStyle(
              color: Colors.white,
              fontFamily: 'monospace',
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.text, required this.isError});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isError ? const Color(0xFFFFECE8) : const Color(0xFFE9F5EE),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isError ? const Color(0xFFD95E48) : const Color(0xFF79A88D),
        ),
      ),
      child: Text(text),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAF7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD9DED7)),
      ),
      child: Text(text),
    );
  }
}

