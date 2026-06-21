import 'package:flutter/material.dart';

import '../../services/backend_auth_client.dart';
import '../../shared/console_widgets.dart';

class WorkspaceView extends StatefulWidget {
  const WorkspaceView({
    required this.user,
    required this.apiClient,
    required this.onSignOut,
    this.autoLoad = true,
    this.initialDevices = const [],
    this.initialAgents = const [],
    this.initialActiveConfigs = const [],
    super.key,
  });

  final BackendUser user;
  final SentinelEdgeApiClient apiClient;
  final Future<void> Function() onSignOut;
  final bool autoLoad;
  final List<EdgeDevice> initialDevices;
  final List<SurveillanceAgent> initialAgents;
  final List<EdgeAgentConfig> initialActiveConfigs;

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
  final _deviceSearchController = TextEditingController();
  final _agentSearchController = TextEditingController();

  List<EdgeDevice> _devices = const [];
  List<SurveillanceAgent> _agents = const [];
  List<EdgeAgentConfig> _activeConfigs = const [];
  String? _selectedDeviceId;
  String? _selectedAgentId;
  String? _lastEdgeToken;
  String? _error;
  int _selectedTab = 0;
  bool _isRefreshing = false;
  bool _isRegisteringDevice = false;
  bool _isSendingHeartbeat = false;
  bool _isCreatingAgent = false;
  bool _isChangingAgentState = false;
  bool _isSyncingConfigs = false;

  bool get _isBusy =>
      _isRefreshing ||
      _isRegisteringDevice ||
      _isSendingHeartbeat ||
      _isCreatingAgent ||
      _isChangingAgentState ||
      _isSyncingConfigs;

  @override
  void initState() {
    super.initState();
    _devices = widget.initialDevices;
    _agents = widget.initialAgents;
    _activeConfigs = widget.initialActiveConfigs;
    _selectedDeviceId = _chooseExisting(
      null,
      _devices.map((device) => device.deviceId),
    );
    _selectedAgentId = _chooseExisting(
      null,
      _agents.map((agent) => agent.agentId),
    );
    if (widget.autoLoad) {
      _refreshAll(showSuccess: false);
    }
  }

  @override
  void dispose() {
    _deviceNameController.dispose();
    _deviceLocationController.dispose();
    _agentNameController.dispose();
    _agentLocationController.dispose();
    _ruleController.dispose();
    _edgeTokenController.dispose();
    _deviceSearchController.dispose();
    _agentSearchController.dispose();
    super.dispose();
  }

  Future<void> _run({
    required String successMessage,
    required void Function(bool value) setBusy,
    required Future<void> Function() action,
    bool showSuccess = true,
  }) async {
    setState(() {
      setBusy(true);
      _error = null;
    });
    try {
      await action();
      if (!mounted) return;
      if (showSuccess) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(successMessage)));
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => setBusy(false));
      }
    }
  }

  Future<void> _refreshAll({bool showSuccess = true}) async {
    await _run(
      successMessage: 'Dashboard refreshed',
      setBusy: (value) => _isRefreshing = value,
      showSuccess: showSuccess,
      action: () async {
        final devices = await widget.apiClient.listDevices();
        final agents = await widget.apiClient.listAgents();
        if (!mounted) return;
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
      },
    );
  }

  Future<void> _registerDevice() async {
    await _run(
      successMessage:
          'Device registered. Copy the edge token now; it is only returned once.',
      setBusy: (value) => _isRegisteringDevice = value,
      action: () async {
        final registration = await widget.apiClient.registerDevice(
          name: _deviceNameController.text,
          location: _deviceLocationController.text,
        );
        final devices = await widget.apiClient.listDevices();
        if (!mounted) return;
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
      _showLocalError('Paste an edge token before sending heartbeat.');
      return;
    }
    await _run(
      successMessage: 'Heartbeat accepted',
      setBusy: (value) => _isSendingHeartbeat = value,
      action: () async {
        await widget.apiClient.sendHeartbeat(
          edgeToken: token,
          healthStatus: 'online',
          rssi: -58.2,
          fps: 15,
          currentPan: 90,
        );
        final devices = await widget.apiClient.listDevices();
        if (!mounted) return;
        setState(() => _devices = devices);
      },
    );
  }

  Future<void> _createAgent() async {
    final deviceId = _selectedDeviceId;
    if (deviceId == null) {
      _showLocalError('Register or select a device before creating an agent.');
      return;
    }
    await _run(
      successMessage: 'Agent created',
      setBusy: (value) => _isCreatingAgent = value,
      action: () async {
        final agent = await widget.apiClient.createAgent(
          deviceId: deviceId,
          name: _agentNameController.text,
          location: _agentLocationController.text,
          rule: _ruleController.text,
        );
        final agents = await widget.apiClient.listAgents();
        if (!mounted) return;
        setState(() {
          _agents = agents;
          _selectedAgentId = agent.agentId;
        });
      },
    );
  }

  Future<void> _setAgentState(bool armed) async {
    final agentId = _selectedAgentId;
    if (agentId == null) {
      _showLocalError('Select an agent first.');
      return;
    }
    await _run(
      successMessage: armed ? 'Agent armed' : 'Agent disarmed',
      setBusy: (value) => _isChangingAgentState = value,
      action: () async {
        if (armed) {
          await widget.apiClient.armAgent(agentId);
        } else {
          await widget.apiClient.disarmAgent(agentId);
        }
        final agents = await widget.apiClient.listAgents();
        if (!mounted) return;
        setState(() => _agents = agents);
      },
    );
  }

  Future<void> _pullActiveConfigs() async {
    final token = _edgeTokenController.text.trim();
    if (token.isEmpty) {
      _showLocalError('Paste an edge token before pulling active configs.');
      return;
    }
    await _run(
      successMessage: 'Active configs pulled',
      setBusy: (value) => _isSyncingConfigs = value,
      action: () async {
        final configs = await widget.apiClient.activeConfigs(token);
        if (!mounted) return;
        setState(() => _activeConfigs = configs);
      },
    );
  }

  void _showLocalError(String text) {
    setState(() => _error = text);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        final destinations = _destinations;
        final body = _WorkspaceBody(
          title: destinations[_selectedTab].label,
          user: widget.user,
          isBusy: _isBusy,
          isRefreshing: _isRefreshing,
          error: _error,
          onRefresh: () => _refreshAll(),
          onSignOut: widget.onSignOut,
          child: _selectedContent(compact),
        );

        if (compact) {
          return Scaffold(
            body: SafeArea(child: body),
            bottomNavigationBar: NavigationBar(
              selectedIndex: _selectedTab,
              onDestinationSelected: (index) =>
                  setState(() => _selectedTab = index),
              destinations: destinations
                  .map(
                    (item) => NavigationDestination(
                      icon: Icon(item.icon),
                      selectedIcon: Icon(item.selectedIcon),
                      label: item.label,
                    ),
                  )
                  .toList(),
            ),
          );
        }

        return Scaffold(
          body: SafeArea(
            child: Row(
              children: [
                NavigationRail(
                  selectedIndex: _selectedTab,
                  onDestinationSelected: (index) =>
                      setState(() => _selectedTab = index),
                  extended: constraints.maxWidth >= 1120,
                  leading: Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 20),
                    child: Icon(
                      Icons.shield_outlined,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  destinations: destinations
                      .map(
                        (item) => NavigationRailDestination(
                          icon: Icon(item.icon),
                          selectedIcon: Icon(item.selectedIcon),
                          label: Text(item.label),
                        ),
                      )
                      .toList(),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: body),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _selectedContent(bool compact) {
    return switch (_selectedTab) {
      0 => _overviewPanel(compact),
      1 => _devicePanel(compact),
      2 => _agentPanel(compact),
      _ => _edgePanel(),
    };
  }

  Widget _overviewPanel(bool compact) {
    final onlineDevices = _devices
        .where((device) => device.healthStatus == 'online')
        .length;
    final armedAgents = _agents.where((agent) => agent.state == 'armed').length;
    final offlineDevices = _devices.length - onlineDevices;
    final metricColumns = compact ? 2 : 4;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GridView.count(
          crossAxisCount: metricColumns,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: compact ? 1.55 : 1.85,
          children: [
            MetricTile(
              label: 'Devices',
              value: _devices.length.toString(),
              icon: Icons.videocam_outlined,
            ),
            MetricTile(
              label: 'Online',
              value: onlineDevices.toString(),
              icon: Icons.sensors_outlined,
              accent: const Color(0xFF2E8B57),
            ),
            MetricTile(
              label: 'Offline',
              value: offlineDevices.toString(),
              icon: Icons.signal_wifi_bad_outlined,
              accent: const Color(0xFFC44732),
            ),
            MetricTile(
              label: 'Armed agents',
              value: armedAgents.toString(),
              icon: Icons.shield_outlined,
              accent: const Color(0xFFB68416),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (compact) ...[
          _operationsPanel(),
          const SizedBox(height: 16),
          _recentConfigPanel(),
        ] else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _operationsPanel()),
              const SizedBox(width: 16),
              Expanded(child: _recentConfigPanel()),
            ],
          ),
      ],
    );
  }

  Widget _operationsPanel() {
    final selectedDevice = _devices
        .where((device) => device.deviceId == _selectedDeviceId)
        .firstOrNull;
    final selectedAgent = _agents
        .where((agent) => agent.agentId == _selectedAgentId)
        .firstOrNull;
    return ConsolePanel(
      title: 'Operational focus',
      icon: Icons.center_focus_strong_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (selectedDevice == null)
            const EmptyState(
              icon: Icons.videocam_off_outlined,
              title: 'No device selected',
              message:
                  'Register or select a camera device to anchor agent operations.',
            )
          else
            _FocusRow(
              icon: Icons.videocam_outlined,
              title: selectedDevice.name,
              detail:
                  '${selectedDevice.location ?? 'No location'} - ${selectedDevice.healthStatus}',
            ),
          const SizedBox(height: 10),
          if (selectedAgent == null)
            const EmptyState(
              icon: Icons.radar_outlined,
              title: 'No agent selected',
              message: 'Create or select an agent to arm surveillance rules.',
            )
          else
            _FocusRow(
              icon: Icons.radar_outlined,
              title: selectedAgent.name,
              detail: '${selectedAgent.state} - ${selectedAgent.rule}',
            ),
        ],
      ),
    );
  }

  Widget _recentConfigPanel() {
    return ConsolePanel(
      title: 'Edge sync state',
      icon: Icons.hub_outlined,
      child: _activeConfigs.isEmpty
          ? const EmptyState(
              icon: Icons.download_outlined,
              title: 'No active config synced',
              message:
                  'Arm an agent, paste the edge token, then sync active agents.',
            )
          : Column(
              children: _activeConfigs
                  .take(3)
                  .map((config) => _ActiveConfigTile(config: config))
                  .toList(),
            ),
    );
  }

  Widget _devicePanel(bool compact) {
    final query = _deviceSearchController.text.trim().toLowerCase();
    final visibleDevices = _devices.where((device) {
      if (query.isEmpty) return true;
      return device.name.toLowerCase().contains(query) ||
          (device.location ?? '').toLowerCase().contains(query) ||
          device.healthStatus.toLowerCase().contains(query);
    }).toList();

    return _responsivePair(
      compact: compact,
      first: ConsolePanel(
        title: 'Register device',
        icon: Icons.add_circle_outline,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _deviceNameController,
              decoration: const InputDecoration(labelText: 'Device name'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _deviceLocationController,
              decoration: const InputDecoration(labelText: 'Location'),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _isRegisteringDevice ? null : _registerDevice,
              icon: _isRegisteringDevice
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_circle_outline),
              label: Text(_isRegisteringDevice ? 'Registering' : 'Add device'),
            ),
            if (_lastEdgeToken != null) ...[
              const SizedBox(height: 12),
              TokenBox(token: _lastEdgeToken!),
            ],
          ],
        ),
      ),
      second: ConsolePanel(
        title: 'Device roster',
        icon: Icons.videocam_outlined,
        child: Column(
          children: [
            TextField(
              controller: _deviceSearchController,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: 'Search devices',
              ),
            ),
            const SizedBox(height: 12),
            if (_devices.isEmpty)
              const EmptyState(
                icon: Icons.videocam_off_outlined,
                title: 'No devices registered',
                message:
                    'Add your first camera or edge device to start the surveillance loop.',
              )
            else if (visibleDevices.isEmpty)
              const EmptyState(
                icon: Icons.search_off_outlined,
                title: 'No matching devices',
                message:
                    'Clear the search field to show every registered device.',
              )
            else
              ...visibleDevices.map(
                (device) => SelectableConsoleTile(
                  selected: _selectedDeviceId == device.deviceId,
                  title: device.name,
                  subtitle:
                      '${device.location ?? 'No location'} - pan ${device.currentPan}',
                  trailing: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      StatusPill(
                        label: device.healthStatus,
                        color: _statusColor(device.healthStatus),
                      ),
                      if (device.fps != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          '${device.fps!.toStringAsFixed(1)} fps',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ],
                  ),
                  onTap: () =>
                      setState(() => _selectedDeviceId = device.deviceId),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _agentPanel(bool compact) {
    final query = _agentSearchController.text.trim().toLowerCase();
    final visibleAgents = _agents.where((agent) {
      if (query.isEmpty) return true;
      return agent.name.toLowerCase().contains(query) ||
          agent.rule.toLowerCase().contains(query) ||
          agent.state.toLowerCase().contains(query);
    }).toList();

    return _responsivePair(
      compact: compact,
      first: ConsolePanel(
        title: 'Create agent',
        icon: Icons.add_task_outlined,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _selectedDeviceId,
              items: _devices
                  .map(
                    (device) => DropdownMenuItem(
                      value: device.deviceId,
                      child: Text(device.name, overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
              onChanged: _devices.isEmpty
                  ? null
                  : (value) => setState(() => _selectedDeviceId = value),
              decoration: const InputDecoration(labelText: 'Linked device'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _agentNameController,
              decoration: const InputDecoration(labelText: 'Agent name'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _agentLocationController,
              decoration: const InputDecoration(labelText: 'Location'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _ruleController,
              minLines: 4,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Natural language rule',
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _isCreatingAgent ? null : _createAgent,
              icon: _isCreatingAgent
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_task_outlined),
              label: Text(_isCreatingAgent ? 'Creating' : 'New agent'),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isChangingAgentState
                        ? null
                        : () => _setAgentState(true),
                    icon: const Icon(Icons.play_arrow_outlined),
                    label: const Text('Arm'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isChangingAgentState
                        ? null
                        : () => _setAgentState(false),
                    icon: const Icon(Icons.pause_outlined),
                    label: const Text('Disarm'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      second: ConsolePanel(
        title: 'Agent roster',
        icon: Icons.radar_outlined,
        child: Column(
          children: [
            TextField(
              controller: _agentSearchController,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: 'Search agents',
              ),
            ),
            const SizedBox(height: 12),
            if (_agents.isEmpty)
              const EmptyState(
                icon: Icons.radar_outlined,
                title: 'No agents created',
                message:
                    'Create an agent and describe what SentinelEdge should watch for.',
              )
            else if (visibleAgents.isEmpty)
              const EmptyState(
                icon: Icons.search_off_outlined,
                title: 'No matching agents',
                message:
                    'Clear the search field to show every surveillance rule.',
              )
            else
              ...visibleAgents.map(
                (agent) => SelectableConsoleTile(
                  selected: _selectedAgentId == agent.agentId,
                  title: agent.name,
                  subtitle: agent.rule,
                  trailing: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      StatusPill(
                        label: agent.state,
                        color: _statusColor(agent.state),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        agent.enabled ? 'enabled' : 'disabled',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                  onTap: () => setState(() => _selectedAgentId = agent.agentId),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _edgePanel() {
    return ConsolePanel(
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
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: _isSendingHeartbeat ? null : _sendHeartbeat,
                icon: _isSendingHeartbeat
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.favorite_border),
                label: Text(
                  _isSendingHeartbeat ? 'Checking' : 'Check connection',
                ),
              ),
              OutlinedButton.icon(
                onPressed: _isSyncingConfigs ? null : _pullActiveConfigs,
                icon: _isSyncingConfigs
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download_outlined),
                label: Text(
                  _isSyncingConfigs ? 'Syncing' : 'Sync active agents',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_activeConfigs.isEmpty)
            const EmptyState(
              icon: Icons.settings_input_component_outlined,
              title: 'No active agents synced',
              message:
                  'Arm an agent, then sync active agents with the device edge token.',
            )
          else
            ..._activeConfigs.map(
              (config) => _ActiveConfigTile(config: config),
            ),
        ],
      ),
    );
  }

  Widget _responsivePair({
    required bool compact,
    required Widget first,
    required Widget second,
  }) {
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [first, const SizedBox(height: 16), second],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: first),
        const SizedBox(width: 16),
        Expanded(child: second),
      ],
    );
  }

  static const _destinations = [
    _Destination(
      label: 'Overview',
      icon: Icons.dashboard_outlined,
      selectedIcon: Icons.dashboard,
    ),
    _Destination(
      label: 'Devices',
      icon: Icons.videocam_outlined,
      selectedIcon: Icons.videocam,
    ),
    _Destination(
      label: 'Agents',
      icon: Icons.radar_outlined,
      selectedIcon: Icons.radar,
    ),
    _Destination(
      label: 'Edge',
      icon: Icons.hub_outlined,
      selectedIcon: Icons.hub,
    ),
  ];
}

class _WorkspaceBody extends StatelessWidget {
  const _WorkspaceBody({
    required this.title,
    required this.user,
    required this.isBusy,
    required this.isRefreshing,
    required this.error,
    required this.onRefresh,
    required this.onSignOut,
    required this.child,
  });

  final String title;
  final BackendUser user;
  final bool isBusy;
  final bool isRefreshing;
  final String? error;
  final VoidCallback onRefresh;
  final Future<void> Function() onSignOut;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CustomScrollView(
      slivers: [
        SliverAppBar(
          pinned: true,
          titleSpacing: 20,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(
                '${user.displayName ?? user.email} - ${BackendAuthClient.baseUrl}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          actions: [
            IconButton.filledTonal(
              onPressed: isRefreshing ? null : onRefresh,
              tooltip: 'Refresh',
              icon: isRefreshing
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
            ),
            const SizedBox(width: 6),
            IconButton.outlined(
              onPressed: isBusy ? null : onSignOut,
              tooltip: 'Sign out',
              icon: const Icon(Icons.logout),
            ),
            const SizedBox(width: 12),
          ],
        ),
        SliverPadding(
          padding: const EdgeInsets.all(20),
          sliver: SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1180),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (error != null) ...[
                      _ErrorBanner(text: error!),
                      const SizedBox(height: 12),
                    ],
                    child,
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.error.withValues(alpha: 0.35)),
      ),
      child: Text(text, style: TextStyle(color: scheme.onErrorContainer)),
    );
  }
}

class _FocusRow extends StatelessWidget {
  const _FocusRow({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(icon, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SelectableConsoleTile(
        selected: false,
        title: 'Active config for ${config.agentId}',
        subtitle: '$detectors - confidence $confidence - $ruleText',
        leading: Icon(
          Icons.tune_outlined,
          color: Theme.of(context).colorScheme.primary,
        ),
        trailing: StatusPill(
          label: config.state,
          color: _statusColor(config.state),
        ),
        onTap: () {},
      ),
    );
  }
}

class _Destination {
  const _Destination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

String? _chooseExisting(String? current, Iterable<String> candidates) {
  final values = candidates.toList();
  if (current != null && values.contains(current)) {
    return current;
  }
  return values.isEmpty ? null : values.first;
}

Color _statusColor(String value) {
  final normalized = value.toLowerCase();
  if (normalized == 'online' ||
      normalized == 'armed' ||
      normalized == 'active') {
    return const Color(0xFF2E8B57);
  }
  if (normalized == 'offline' ||
      normalized == 'error' ||
      normalized == 'disabled') {
    return const Color(0xFFC44732);
  }
  return const Color(0xFFB68416);
}
