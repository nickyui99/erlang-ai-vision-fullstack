import 'package:flutter/material.dart';

import '../../design/app_colors.dart';
import '../../design/app_motion.dart';
import '../../design/app_spacing.dart';
import '../../design/app_typography.dart';
import '../../services/backend_auth_client.dart';
import '../../services/realtime/realtime_client.dart';
import '../../shared/console_widgets.dart';
import 'agent_templates.dart';

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
  final _edgeTokenController = TextEditingController();
  final _deviceSearchController = TextEditingController();
  final _agentSearchController = TextEditingController();

  List<EdgeDevice> _devices = const [];
  List<SurveillanceAgent> _agents = const [];
  List<EdgeAgentConfig> _activeConfigs = const [];
  List<SecurityEvent> _events = const [];
  List<MediaClip> _eventClips = const [];
  RealtimeConnection? _realtimeConnection;
  RealtimeStatus _realtimeStatus = RealtimeStatus.connecting;
  String? _selectedDeviceId;
  String? _selectedAgentId;
  String? _selectedEventId;
  String? _assigningAgentId;
  String? _lastEdgeToken;
  ClipPlaybackUrl? _lastPlaybackUrl;
  String? _error;
  int _selectedTab = 0;
  bool _isRefreshing = false;
  bool _isRegisteringDevice = false;
  bool _isSendingHeartbeat = false;
  bool _isCreatingAgent = false;
  bool _isChangingAgentState = false;
  bool _isSyncingConfigs = false;
  bool _isLoadingEvents = false;
  bool _isLoadingClips = false;
  bool _isRequestingPlayback = false;
  bool _edgeTokenObscured = true;

  bool get _isBusy =>
      _isRefreshing ||
      _isRegisteringDevice ||
      _isSendingHeartbeat ||
      _isCreatingAgent ||
      _isChangingAgentState ||
      _isSyncingConfigs ||
      _isLoadingEvents ||
      _isLoadingClips ||
      _isRequestingPlayback;

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
    _realtimeConnection = connectRealtime(
      onMessage: _handleRealtimeMessage,
      onStatus: (status) {
        if (!mounted) return;
        setState(() => _realtimeStatus = status);
      },
    );
  }

  @override
  void dispose() {
    _edgeTokenController.dispose();
    _deviceSearchController.dispose();
    _agentSearchController.dispose();
    _realtimeConnection?.dispose();
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
          _events = const [];
          _eventClips = const [];
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

  Future<void> _refreshDevicesOnly() async {
    try {
      final devices = await widget.apiClient.listDevices();
      if (!mounted) return;
      setState(() {
        _devices = devices;
        _selectedDeviceId = _chooseExisting(
          _selectedDeviceId,
          devices.map((device) => device.deviceId),
        );
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    }
  }

  Future<void> _refreshAgentsOnly() async {
    try {
      final agents = await widget.apiClient.listAgents();
      if (!mounted) return;
      setState(() {
        _agents = agents;
        _selectedAgentId = _chooseExisting(
          _selectedAgentId,
          agents.map((agent) => agent.agentId),
        );
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    }
  }

  Future<void> _loadEvents({bool showSuccess = true}) async {
    await _run(
      successMessage: 'Events refreshed',
      setBusy: (value) => _isLoadingEvents = value,
      showSuccess: showSuccess,
      action: () async {
        final events = await widget.apiClient.listEvents();
        if (!mounted) return;
        setState(() {
          _events = events;
          _selectedEventId = _chooseExisting(
            _selectedEventId,
            events.map((event) => event.eventId),
          );
          _eventClips = const [];
          _lastPlaybackUrl = null;
        });
        final selected = _selectedEventId;
        if (selected != null) {
          await _loadEventClips(selected, showSuccess: false);
        }
      },
    );
  }

  Future<void> _loadEventClips(
    String eventId, {
    bool showSuccess = false,
  }) async {
    await _run(
      successMessage: 'Event media refreshed',
      setBusy: (value) => _isLoadingClips = value,
      showSuccess: showSuccess,
      action: () async {
        final clips = await widget.apiClient.listEventClips(eventId);
        if (!mounted) return;
        setState(() {
          _eventClips = clips;
          _lastPlaybackUrl = null;
        });
      },
    );
  }

  Future<void> _requestPlaybackUrl(MediaClip clip) async {
    await _run(
      successMessage: 'Playback URL generated',
      setBusy: (value) => _isRequestingPlayback = value,
      action: () async {
        final playback = await widget.apiClient.signedClipPlaybackUrl(
          clip.clipId,
        );
        if (!mounted) return;
        setState(() => _lastPlaybackUrl = playback);
      },
    );
  }

  Future<void> _openRegisterDeviceDialog() async {
    final result = await showDialog<({String name, String location})>(
      context: context,
      builder: (_) => const _DeviceFormDialog(),
    );
    if (result == null) return;
    await _registerDevice(name: result.name, location: result.location);
    if (_lastEdgeToken != null && mounted) {
      await _showTokenDialog(_lastEdgeToken!);
    }
  }

  Future<void> _registerDevice({required String name, String? location}) async {
    await _run(
      successMessage:
          'Device registered. Copy the edge token now; it is only returned once.',
      setBusy: (value) => _isRegisteringDevice = value,
      action: () async {
        final registration = await widget.apiClient.registerDevice(
          name: name,
          location: location,
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

  Future<void> _showTokenDialog(String token) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Device edge token'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Copy this token into the edge device now. It is shown only once.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.md),
            TokenBox(token: token),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
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

  Future<void> _openCreateAgentDialog() async {
    final result = await showDialog<_AgentFormResult>(
      context: context,
      builder: (_) => const _AgentFormDialog(),
    );
    if (result == null) return;
    await _createAgent(
      name: result.name,
      location: result.location,
      rule: result.rule,
    );
  }

  Future<void> _openEditAgentDialog(SurveillanceAgent agent) async {
    final result = await showDialog<_AgentFormResult>(
      context: context,
      builder: (_) => _AgentFormDialog(agent: agent),
    );
    if (result == null) return;
    await _saveAgentEdits(
      agentId: agent.agentId,
      name: result.name,
      location: result.location,
      rule: result.rule,
    );
  }

  Future<void> _createAgent({
    required String name,
    String? location,
    required String rule,
  }) async {
    await _run(
      successMessage: 'Agent created',
      setBusy: (value) => _isCreatingAgent = value,
      action: () async {
        final agent = await widget.apiClient.createAgent(
          name: name,
          location: location,
          rule: rule,
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

  Future<void> _saveAgentEdits({
    required String agentId,
    required String name,
    String? location,
    required String rule,
  }) async {
    await _run(
      successMessage: 'Agent updated',
      setBusy: (value) => _isCreatingAgent = value,
      action: () async {
        final agent = await widget.apiClient.updateAgent(
          agentId: agentId,
          name: name,
          location: location,
          rule: rule,
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

  Future<void> _assignAgent(String agentId, String deviceId) async {
    await _run(
      successMessage: 'Agent assigned',
      setBusy: (value) {
        _isChangingAgentState = value;
        _assigningAgentId = value ? agentId : null;
      },
      action: () async {
        await widget.apiClient.assignAgent(agentId, deviceId: deviceId);
        final agents = await widget.apiClient.listAgents();
        if (!mounted) return;
        setState(() => _agents = agents);
      },
    );
  }

  Future<void> _unassignAgent(String agentId, String deviceId) async {
    await _run(
      successMessage: 'Agent unassigned',
      setBusy: (value) {
        _isChangingAgentState = value;
        _assigningAgentId = value ? agentId : null;
      },
      action: () async {
        await widget.apiClient.unassignAgent(agentId, deviceId: deviceId);
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

  void _selectTab(int index) {
    setState(() => _selectedTab = index);
    if (_destinations[index].label == 'Events' && _events.isEmpty) {
      _loadEvents(showSuccess: false);
    }
  }

  void _handleRealtimeMessage(RealtimeMessage message) {
    if (!mounted) return;
    switch (message.type) {
      case 'event.created':
        _loadEvents(showSuccess: false);
        break;
      case 'clip.available':
        final eventId = message.data['event_id']?.toString();
        if (eventId != null && eventId == _selectedEventId) {
          _loadEventClips(eventId);
        }
        break;
      case 'device.health_changed':
        _refreshDevicesOnly();
        break;
      case 'agent.state_changed':
        _refreshAgentsOnly();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final compact = width < AppBreakpoints.compact;
        final railExtended = width >= AppBreakpoints.medium;
        final destinations = _destinations;

        final body = _WorkspaceBody(
          title: destinations[_selectedTab].label,
          subtitle: destinations[_selectedTab].subtitle,
          user: widget.user,
          isBusy: _isBusy,
          isRefreshing: _isRefreshing,
          realtimeStatus: _realtimeStatus,
          error: _error,
          onRefresh: () => _refreshAll(),
          onSignOut: widget.onSignOut,
          onDismissError: () => setState(() => _error = null),
          child: _AnimatedTabContent(
            tabIndex: _selectedTab,
            child: _selectedContent(compact),
          ),
        );

        if (compact) {
          return Scaffold(
            body: SafeArea(child: body),
            bottomNavigationBar: NavigationBar(
              selectedIndex: _selectedTab,
              onDestinationSelected: _selectTab,
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
                _Sidebar(
                  destinations: destinations,
                  selectedIndex: _selectedTab,
                  extended: railExtended,
                  user: widget.user,
                  isBusy: _isBusy,
                  onSelect: _selectTab,
                  onSignOut: widget.onSignOut,
                ),
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
      3 => _eventsPanel(compact),
      _ => _edgePanel(),
    };
  }

  Widget _overviewPanel(bool compact) {
    final onlineDevices = _devices
        .where((device) => device.healthStatus == 'online')
        .length;
    final activeAssignments = _agents
        .where((agent) => !agent.isDefinition && agent.state == 'armed')
        .length;
    final offlineDevices = _devices.length - onlineDevices;
    final metricColumns = compact ? 2 : 4;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GridView.count(
          crossAxisCount: metricColumns,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: AppSpacing.md,
          mainAxisSpacing: AppSpacing.md,
          childAspectRatio: compact ? 1.35 : 1.55,
          children: [
            MetricTile(
              label: 'Total devices',
              value: _devices.length.toString(),
              icon: Icons.videocam_outlined,
            ),
            MetricTile(
              label: 'Online',
              value: onlineDevices.toString(),
              icon: Icons.sensors_outlined,
              accent: AppColors.success,
            ),
            MetricTile(
              label: 'Offline',
              value: offlineDevices.toString(),
              icon: Icons.signal_wifi_bad_outlined,
              accent: AppColors.danger,
            ),
            MetricTile(
              label: 'Active assignments',
              value: activeAssignments.toString(),
              icon: Icons.shield_outlined,
              accent: AppColors.warning,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        if (compact) ...[
          _operationsPanel(),
          const SizedBox(height: AppSpacing.lg),
          _recentConfigPanel(),
        ] else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _operationsPanel()),
              const SizedBox(width: AppSpacing.lg),
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
      subtitle: 'What this console is anchored to right now',
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
              compact: true,
            )
          else
            _FocusRow(
              icon: Icons.videocam_outlined,
              title: selectedDevice.name,
              detail:
                  '${selectedDevice.location ?? 'No location'} · ${selectedDevice.healthStatus}',
              tone: StatusToneColor.fromStatus(selectedDevice.healthStatus),
            ),
          const SizedBox(height: AppSpacing.sm),
          if (selectedAgent == null)
            const EmptyState(
              icon: Icons.radar_outlined,
              title: 'No agent selected',
              message: 'Create or select an agent to arm surveillance rules.',
              compact: true,
            )
          else
            _FocusRow(
              icon: Icons.radar_outlined,
              title: selectedAgent.name,
              detail: '${selectedAgent.state} · ${selectedAgent.rule}',
              tone: StatusToneColor.fromStatus(selectedAgent.state),
            ),
        ],
      ),
    );
  }

  Widget _recentConfigPanel() {
    return ConsolePanel(
      title: 'Edge sync state',
      subtitle: 'Configs last pulled to the edge',
      icon: Icons.hub_outlined,
      child: _activeConfigs.isEmpty
          ? const EmptyState(
              icon: Icons.download_outlined,
              title: 'No active config synced',
              message:
                  'Arm an agent, paste the edge token, then sync active agents.',
              compact: true,
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConsolePanel(
          title: 'Devices',
          subtitle: '${_devices.length} registered · tap to select',
          icon: Icons.videocam_outlined,
          action: AppButton(
            label: 'Register device',
            icon: Icons.add_circle_outline,
            loading: _isRegisteringDevice,
            loadingLabel: 'Registering',
            onPressed: _openRegisterDeviceDialog,
          ),
          child: Column(
            children: [
              TextField(
                controller: _deviceSearchController,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search devices',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              if (_isRefreshing && _devices.isEmpty)
                const SkeletonList()
              else if (_devices.isEmpty)
                EmptyState(
                  icon: Icons.videocam_off_outlined,
                  title: 'No devices registered',
                  message:
                      'Add your first camera or edge device to start the surveillance loop.',
                  action: AppButton(
                    label: 'Register device',
                    icon: Icons.add_circle_outline,
                    onPressed: _openRegisterDeviceDialog,
                  ),
                )
              else if (visibleDevices.isEmpty)
                const EmptyState(
                  icon: Icons.search_off_outlined,
                  title: 'No matching devices',
                  message:
                      'Clear the search field to show every registered device.',
                  compact: true,
                )
              else
                ...visibleDevices.map(
                  (device) => SelectableConsoleTile(
                    selected: _selectedDeviceId == device.deviceId,
                    title: device.name,
                    subtitle:
                        '${device.location ?? 'No location'} · pan ${device.currentPan}°',
                    leading: IconChip(icon: Icons.videocam_outlined, size: 34),
                    trailing: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        StatusPill.fromStatus(device.healthStatus),
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
        const SizedBox(height: AppSpacing.lg),
        _armingPanel(),
      ],
    );
  }

  Widget _armingPanel() {
    final selectedDevice = _devices
        .where((device) => device.deviceId == _selectedDeviceId)
        .firstOrNull;
    final definitions = _definitions;
    return ConsolePanel(
      title: 'Assign agents',
      subtitle: selectedDevice == null
          ? 'Select a device to assign agents to it'
          : 'Assign agents to ${selectedDevice.name}',
      icon: Icons.shield_outlined,
      child: selectedDevice == null
          ? const EmptyState(
              icon: Icons.videocam_off_outlined,
              title: 'No device selected',
              message:
                  'Pick a device from the list above, then assign any agent to it.',
              compact: true,
            )
          : definitions.isEmpty
          ? const EmptyState(
              icon: Icons.radar_outlined,
              title: 'No agents yet',
              message:
                  'Create an agent in the Agents tab, then assign it to this device here.',
              compact: true,
            )
          : Column(
              children: definitions.map((agent) {
                return _AssignAgentTile(
                  agent: agent,
                  assigned: _isAssigned(agent.agentId, selectedDevice.deviceId),
                  assignmentCount: _assignmentCount(agent.agentId),
                  busy: _assigningAgentId == agent.agentId,
                  enabled: !_isChangingAgentState,
                  onChanged: (assign) => assign
                      ? _assignAgent(agent.agentId, selectedDevice.deviceId)
                      : _unassignAgent(agent.agentId, selectedDevice.deviceId),
                );
              }).toList(),
            ),
    );
  }

  List<SurveillanceAgent> get _definitions =>
      _agents.where((agent) => agent.isDefinition).toList();

  Iterable<SurveillanceAgent> _subsForDefinition(String definitionId) =>
      _agents.where((agent) => agent.parentAgentId == definitionId);

  int _assignmentCount(String definitionId) =>
      _subsForDefinition(definitionId).length;

  bool _isAssigned(String definitionId, String deviceId) => _subsForDefinition(
    definitionId,
  ).any((agent) => agent.deviceId == deviceId);

  Widget _agentPanel(bool compact) {
    final query = _agentSearchController.text.trim().toLowerCase();
    final definitions = _definitions;
    final visibleAgents = definitions.where((agent) {
      if (query.isEmpty) return true;
      return agent.name.toLowerCase().contains(query) ||
          agent.rule.toLowerCase().contains(query);
    }).toList();

    return ConsolePanel(
      title: 'Agents',
      subtitle: '${definitions.length} agents · tap to edit',
      icon: Icons.radar_outlined,
      action: AppButton(
        label: 'Create agent',
        icon: Icons.add_task_outlined,
        loading: _isCreatingAgent,
        loadingLabel: 'Saving',
        onPressed: _openCreateAgentDialog,
      ),
      child: Column(
        children: [
          TextField(
            controller: _agentSearchController,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search agents',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (_isRefreshing && definitions.isEmpty)
            const SkeletonList()
          else if (definitions.isEmpty)
            EmptyState(
              icon: Icons.radar_outlined,
              title: 'No agents created',
              message:
                  'Create an agent from a template or your own rule, then assign it to a camera in the Devices tab.',
              action: AppButton(
                label: 'Create agent',
                icon: Icons.add_task_outlined,
                onPressed: _openCreateAgentDialog,
              ),
            )
          else if (visibleAgents.isEmpty)
            const EmptyState(
              icon: Icons.search_off_outlined,
              title: 'No matching agents',
              message:
                  'Clear the search field to show every surveillance rule.',
              compact: true,
            )
          else
            ...visibleAgents.map((agent) {
              final count = _assignmentCount(agent.agentId);
              return SelectableConsoleTile(
                selected: false,
                title: agent.name,
                subtitle: agent.rule,
                leading: IconChip(icon: Icons.radar_outlined, size: 34),
                trailing: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    StatusPill(
                      label: count > 0
                          ? '$count ${count == 1 ? 'camera' : 'cameras'}'
                          : 'unassigned',
                      tone: count > 0 ? StatusTone.success : StatusTone.neutral,
                    ),
                    const SizedBox(height: 4),
                    Icon(
                      Icons.edit_outlined,
                      size: 16,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
                onTap: () => _openEditAgentDialog(agent),
              );
            }),
        ],
      ),
    );
  }

  Widget _edgePanel() {
    return ConsolePanel(
      title: 'Edge setup',
      subtitle: 'Authenticate and sync the device fleet',
      icon: Icons.hub_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _edgeTokenController,
            decoration: InputDecoration(
              labelText: 'Edge token',
              prefixIcon: const Icon(Icons.key_outlined),
              suffixIcon: IconButton(
                tooltip: _edgeTokenObscured ? 'Show token' : 'Hide token',
                icon: Icon(
                  _edgeTokenObscured
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                onPressed: () =>
                    setState(() => _edgeTokenObscured = !_edgeTokenObscured),
              ),
            ),
            obscureText: _edgeTokenObscured,
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            children: [
              AppButton(
                label: 'Check connection',
                loadingLabel: 'Checking',
                icon: Icons.favorite_border,
                loading: _isSendingHeartbeat,
                onPressed: _sendHeartbeat,
              ),
              AppButton(
                label: 'Sync active agents',
                loadingLabel: 'Syncing',
                icon: Icons.download_outlined,
                variant: AppButtonVariant.secondary,
                loading: _isSyncingConfigs,
                onPressed: _pullActiveConfigs,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
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

  Widget _eventsPanel(bool compact) {
    final selectedEvent = _events
        .where((event) => event.eventId == _selectedEventId)
        .firstOrNull;
    return _responsivePair(
      compact: compact,
      first: ConsolePanel(
        title: 'Event review',
        subtitle: '${_events.length} detections',
        icon: Icons.warning_amber_outlined,
        action: IconButton.filledTonal(
          onPressed: _isLoadingEvents ? null : () => _loadEvents(),
          tooltip: 'Refresh events',
          icon: _isLoadingEvents
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_isLoadingEvents && _events.isEmpty)
              const SkeletonList(rows: 4)
            else if (_events.isEmpty)
              const EmptyState(
                icon: Icons.event_busy_outlined,
                title: 'No events yet',
                message:
                    'Submit an edge event after arming an agent to review detections here.',
              )
            else
              ..._events.map(
                (event) => SelectableConsoleTile(
                  selected: _selectedEventId == event.eventId,
                  title: event.summary?.isNotEmpty == true
                      ? event.summary!
                      : event.eventType,
                  subtitle:
                      '${_formatDate(event.timestamp)} · ${event.deviceId}',
                  leading: IconChip(
                    icon: Icons.warning_amber_outlined,
                    size: 34,
                    color: StatusToneColor.fromStatus(event.severity).base,
                  ),
                  trailing: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      StatusPill.fromStatus(event.severity),
                      const SizedBox(height: 4),
                      Text(
                        event.status,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                  onTap: () {
                    setState(() {
                      _selectedEventId = event.eventId;
                      _lastPlaybackUrl = null;
                    });
                    _loadEventClips(event.eventId);
                  },
                ),
              ),
          ],
        ),
      ),
      second: ConsolePanel(
        title: 'Event detail',
        subtitle: 'Stage results and media',
        icon: Icons.manage_search_outlined,
        child: selectedEvent == null
            ? const EmptyState(
                icon: Icons.manage_search_outlined,
                title: 'Select an event',
                message: 'Choose an event to inspect stage results and media.',
              )
            : _EventDetail(
                event: selectedEvent,
                clips: _eventClips,
                playbackUrl: _lastPlaybackUrl,
                isLoadingClips: _isLoadingClips,
                isRequestingPlayback: _isRequestingPlayback,
                onRefreshClips: () => _loadEventClips(selectedEvent.eventId),
                onPlayback: _requestPlaybackUrl,
              ),
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
        children: [
          first,
          const SizedBox(height: AppSpacing.lg),
          second,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: first),
        const SizedBox(width: AppSpacing.lg),
        Expanded(child: second),
      ],
    );
  }

  static const _destinations = [
    _Destination(
      label: 'Overview',
      subtitle: 'Fleet status at a glance',
      icon: Icons.dashboard_outlined,
      selectedIcon: Icons.dashboard,
    ),
    _Destination(
      label: 'Devices',
      subtitle: 'Cameras, edge nodes and arming',
      icon: Icons.videocam_outlined,
      selectedIcon: Icons.videocam,
    ),
    _Destination(
      label: 'Agents',
      subtitle: 'Author and edit surveillance rules',
      icon: Icons.radar_outlined,
      selectedIcon: Icons.radar,
    ),
    _Destination(
      label: 'Events',
      subtitle: 'Detections and media review',
      icon: Icons.warning_amber_outlined,
      selectedIcon: Icons.warning_amber,
    ),
    _Destination(
      label: 'Edge',
      subtitle: 'Device authentication and sync',
      icon: Icons.hub_outlined,
      selectedIcon: Icons.hub,
    ),
  ];
}

// ---------------------------------------------------------------------------
// Shell
// ---------------------------------------------------------------------------

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.destinations,
    required this.selectedIndex,
    required this.extended,
    required this.user,
    required this.isBusy,
    required this.onSelect,
    required this.onSignOut,
  });

  final List<_Destination> destinations;
  final int selectedIndex;
  final bool extended;
  final BackendUser user;
  final bool isBusy;
  final ValueChanged<int> onSelect;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final width = extended ? 252.0 : 76.0;

    return AnimatedContainer(
      duration: AppMotion.duration(context, AppMotion.base),
      curve: AppMotion.easeOut,
      width: width,
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(right: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Brand lockup
          Padding(
            padding: EdgeInsets.fromLTRB(
              extended ? AppSpacing.lg : 0,
              AppSpacing.xl,
              extended ? AppSpacing.lg : 0,
              AppSpacing.lg,
            ),
            child: Row(
              mainAxisAlignment: extended
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.center,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.primary, AppColors.brandDeep],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(
                    Icons.shield_outlined,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                if (extended) ...[
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      'SentinelEdge',
                      style: theme.textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Destinations
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              children: [
                for (var i = 0; i < destinations.length; i++)
                  _NavItem(
                    destination: destinations[i],
                    selected: i == selectedIndex,
                    extended: extended,
                    onTap: () => onSelect(i),
                  ),
              ],
            ),
          ),
          Divider(color: scheme.outlineVariant, height: 1),
          // Account
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: _AccountRow(
              user: user,
              extended: extended,
              isBusy: isBusy,
              onSignOut: onSignOut,
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.destination,
    required this.selected,
    required this.extended,
    required this.onTap,
  });

  final _Destination destination;
  final bool selected;
  final bool extended;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fg = selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant;
    final item = Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: EdgeInsets.symmetric(
        horizontal: extended ? AppSpacing.md : 0,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: selected ? scheme.primaryContainer : Colors.transparent,
        borderRadius: AppRadius.mdAll,
      ),
      child: Row(
        mainAxisAlignment: extended
            ? MainAxisAlignment.start
            : MainAxisAlignment.center,
        children: [
          Icon(
            selected ? destination.selectedIcon : destination.icon,
            size: 22,
            color: fg,
          ),
          if (extended) ...[
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                destination.label,
                style:
                    (selected
                            ? theme.textTheme.labelLarge
                            : theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w500,
                              ))
                        ?.copyWith(color: selected ? scheme.onSurface : fg),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );

    final tappable = Material(
      color: Colors.transparent,
      child: InkWell(borderRadius: AppRadius.mdAll, onTap: onTap, child: item),
    );

    return extended
        ? tappable
        : Tooltip(message: destination.label, child: tappable);
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({
    required this.user,
    required this.extended,
    required this.isBusy,
    required this.onSignOut,
  });

  final BackendUser user;
  final bool extended;
  final bool isBusy;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final avatar = _Avatar(user: user);

    if (!extended) {
      return Column(
        children: [
          avatar,
          const SizedBox(height: AppSpacing.sm),
          IconButton(
            tooltip: 'Sign out',
            onPressed: isBusy ? null : onSignOut,
            icon: const Icon(Icons.logout, size: 20),
          ),
        ],
      );
    }

    return Row(
      children: [
        avatar,
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                user.displayName ?? user.email,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall,
              ),
              Text(
                user.role,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Sign out',
          onPressed: isBusy ? null : onSignOut,
          icon: const Icon(Icons.logout, size: 20),
          color: scheme.onSurfaceVariant,
        ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.user});

  final BackendUser user;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final url = user.avatarUrl;
    final source = (user.displayName?.isNotEmpty == true)
        ? user.displayName!
        : user.email;
    final initials = source.trim().isEmpty
        ? '?'
        : source.trim()[0].toUpperCase();
    return CircleAvatar(
      radius: 18,
      backgroundColor: scheme.primaryContainer,
      foregroundImage: (url != null && url.isNotEmpty)
          ? NetworkImage(url)
          : null,
      child: Text(
        initials,
        style: TextStyle(
          color: scheme.onPrimaryContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _AnimatedTabContent extends StatelessWidget {
  const _AnimatedTabContent({required this.tabIndex, required this.child});

  final int tabIndex;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: AppMotion.duration(context, AppMotion.base),
      switchInCurve: AppMotion.easeOut,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.02),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: KeyedSubtree(key: ValueKey(tabIndex), child: child),
    );
  }
}

class _EventDetail extends StatelessWidget {
  const _EventDetail({
    required this.event,
    required this.clips,
    required this.playbackUrl,
    required this.isLoadingClips,
    required this.isRequestingPlayback,
    required this.onRefreshClips,
    required this.onPlayback,
  });

  final SecurityEvent event;
  final List<MediaClip> clips;
  final ClipPlaybackUrl? playbackUrl;
  final bool isLoadingClips;
  final bool isRequestingPlayback;
  final VoidCallback onRefreshClips;
  final Future<void> Function(MediaClip clip) onPlayback;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            StatusPill.fromStatus(event.severity),
            StatusPill.fromStatus(event.status),
            if (event.degraded)
              const StatusPill(label: 'degraded', tone: StatusTone.warning),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        _DetailLine(label: 'Event', value: event.eventId),
        _DetailLine(label: 'Type', value: event.eventType),
        _DetailLine(label: 'Device', value: event.deviceId),
        _DetailLine(label: 'Agent', value: event.agentId),
        _DetailLine(label: 'Time', value: _formatDate(event.timestamp)),
        if (event.confidence != null)
          _DetailLine(
            label: 'Confidence',
            value: '${(event.confidence! * 100).toStringAsFixed(1)}%',
          ),
        if (event.summary != null)
          _DetailLine(label: 'Summary', value: event.summary!),
        const SizedBox(height: AppSpacing.md),
        Text('Stage results', style: theme.textTheme.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        CodeBlock(label: 'Stage 1', value: event.stage1Result?.toString()),
        CodeBlock(label: 'Stage 2', value: event.stage2Verdict?.toString()),
        CodeBlock(label: 'Stage 3', value: event.stage3Verdict?.toString()),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(child: Text('Clips', style: theme.textTheme.titleSmall)),
            IconButton.filledTonal(
              onPressed: isLoadingClips ? null : onRefreshClips,
              tooltip: 'Refresh clips',
              icon: isLoadingClips
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (clips.isEmpty)
          const EmptyState(
            icon: Icons.movie_outlined,
            title: 'No clips attached',
            message: 'Register a clip from the edge service for this event.',
            compact: true,
          )
        else
          ...clips.map(
            (clip) => SelectableConsoleTile(
              selected: false,
              title: clip.clipType,
              subtitle:
                  '${clip.status} · ${clip.mimeType ?? 'media'} · ${clip.durationSeconds ?? 0}s',
              leading: IconChip(icon: Icons.movie_outlined, size: 34),
              trailing: AppButton(
                label: 'URL',
                icon: Icons.link,
                variant: AppButtonVariant.secondary,
                onPressed: isRequestingPlayback || clip.status != 'available'
                    ? null
                    : () => onPlayback(clip),
              ),
              onTap: () {},
            ),
          ),
        if (playbackUrl != null) ...[
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: AppRadius.mdAll,
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Playback URL',
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    CopyIconButton(
                      value: playbackUrl!.playbackUrl,
                      tooltip: 'Copy playback URL',
                    ),
                  ],
                ),
                SelectableText(
                  playbackUrl!.playbackUrl,
                  style: AppTypography.mono(color: scheme.onSurface),
                ),
                if (playbackUrl!.expiresAt != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Expires ${_formatDate(playbackUrl!.expiresAt)}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 84,
            child: Text(label, style: theme.textTheme.labelMedium),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkspaceBody extends StatelessWidget {
  const _WorkspaceBody({
    required this.title,
    required this.subtitle,
    required this.user,
    required this.isBusy,
    required this.isRefreshing,
    required this.realtimeStatus,
    required this.error,
    required this.onRefresh,
    required this.onSignOut,
    required this.onDismissError,
    required this.child,
  });

  final String title;
  final String subtitle;
  final BackendUser user;
  final bool isBusy;
  final bool isRefreshing;
  final RealtimeStatus realtimeStatus;
  final String? error;
  final VoidCallback onRefresh;
  final Future<void> Function() onSignOut;
  final VoidCallback onDismissError;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CustomScrollView(
      slivers: [
        SliverAppBar(
          pinned: true,
          titleSpacing: AppSpacing.xl,
          toolbarHeight: 72,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(title, style: theme.textTheme.headlineSmall),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
          actions: [
            _RealtimeStatusPill(status: realtimeStatus),
            const SizedBox(width: AppSpacing.sm),
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
            const SizedBox(width: AppSpacing.lg),
          ],
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.sm,
            AppSpacing.xl,
            AppSpacing.xxl,
          ),
          sliver: SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AppBreakpoints.contentMaxWidth,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (error != null) ...[
                      Row(
                        children: [
                          Expanded(child: AppBanner(text: error!)),
                          IconButton(
                            tooltip: 'Dismiss',
                            iconSize: 18,
                            onPressed: onDismissError,
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
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

class _RealtimeStatusPill extends StatelessWidget {
  const _RealtimeStatusPill({required this.status});

  final RealtimeStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, tone) = switch (status) {
      RealtimeStatus.live => ('Live', StatusTone.success),
      RealtimeStatus.connecting => ('Connecting', StatusTone.warning),
      RealtimeStatus.reconnecting => ('Reconnecting', StatusTone.warning),
      RealtimeStatus.offline => ('Offline', StatusTone.danger),
    };
    return Tooltip(
      message: 'Realtime connection: $label',
      child: StatusPill(label: label, tone: tone),
    );
  }
}

class _FocusRow extends StatelessWidget {
  const _FocusRow({
    required this.icon,
    required this.title,
    required this.detail,
    required this.tone,
  });

  final IconData icon;
  final String title;
  final String detail;
  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          IconChip(icon: icon, color: tone.base),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TemplateChip extends StatelessWidget {
  const _TemplateChip({
    required this.template,
    required this.selected,
    required this.onTap,
  });

  final AgentTemplate template;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Tooltip(
      message: template.description,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: AppRadius.pillAll,
          onTap: onTap,
          child: AnimatedContainer(
            duration: AppMotion.duration(context, AppMotion.fast),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: selected
                  ? scheme.primaryContainer
                  : scheme.surfaceContainerLow,
              borderRadius: AppRadius.pillAll,
              border: Border.all(
                color: selected ? scheme.primary : scheme.outlineVariant,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  template.icon,
                  size: 16,
                  color: selected ? scheme.onPrimaryContainer : scheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  template.label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: selected
                        ? scheme.onPrimaryContainer
                        : scheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AssignAgentTile extends StatelessWidget {
  const _AssignAgentTile({
    required this.agent,
    required this.assigned,
    required this.assignmentCount,
    required this.busy,
    required this.enabled,
    required this.onChanged,
  });

  final SurveillanceAgent agent;
  final bool assigned;
  final int assignmentCount;
  final bool busy;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final elsewhere = assignmentCount - (assigned ? 1 : 0);
    final subtitle = elsewhere > 0
        ? '${agent.rule}  ·  also on $elsewhere other ${elsewhere == 1 ? 'camera' : 'cameras'}'
        : agent.rule;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          IconChip(
            icon: Icons.radar_outlined,
            size: 34,
            color: assigned ? AppColors.success : scheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  agent.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          if (busy)
            const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Switch(value: assigned, onChanged: enabled ? onChanged : null),
        ],
      ),
    );
  }
}

class _AgentFormResult {
  const _AgentFormResult({
    required this.name,
    this.location,
    required this.rule,
  });

  final String name;
  final String? location;
  final String rule;
}

class _DeviceFormDialog extends StatefulWidget {
  const _DeviceFormDialog();

  @override
  State<_DeviceFormDialog> createState() => _DeviceFormDialogState();
}

class _DeviceFormDialogState extends State<_DeviceFormDialog> {
  final _nameController = TextEditingController();
  final _locationController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Device name is required.');
      return;
    }
    Navigator.of(
      context,
    ).pop((name: name, location: _locationController.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Register device'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Device name',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _locationController,
              decoration: const InputDecoration(
                labelText: 'Location (optional)',
                prefixIcon: Icon(Icons.place_outlined),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              AppBanner(text: _error!),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Register')),
      ],
    );
  }
}

class _AgentFormDialog extends StatefulWidget {
  const _AgentFormDialog({this.agent});

  final SurveillanceAgent? agent;

  @override
  State<_AgentFormDialog> createState() => _AgentFormDialogState();
}

class _AgentFormDialogState extends State<_AgentFormDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _locationController;
  late final TextEditingController _ruleController;
  String? _activeTemplate;
  String? _error;

  bool get _isEditing => widget.agent != null;

  @override
  void initState() {
    super.initState();
    final agent = widget.agent;
    _nameController = TextEditingController(text: agent?.name ?? '');
    _locationController = TextEditingController(text: agent?.location ?? '');
    _ruleController = TextEditingController(text: agent?.rule ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    _ruleController.dispose();
    super.dispose();
  }

  void _applyTemplate(AgentTemplate template) {
    setState(() {
      _activeTemplate = template.label;
      _nameController.text = template.name;
      _ruleController.text = template.rule;
    });
  }

  void _submit() {
    final name = _nameController.text.trim();
    final rule = _ruleController.text.trim();
    if (name.isEmpty || rule.isEmpty) {
      setState(() => _error = 'Agent name and rule are both required.');
      return;
    }
    Navigator.of(context).pop(
      _AgentFormResult(
        name: name,
        location: _locationController.text.trim(),
        rule: rule,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(_isEditing ? 'Edit agent' : 'Create agent'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!_isEditing) ...[
                Text(
                  'Start from a template',
                  style: theme.textTheme.labelMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: kAgentTemplates
                      .map(
                        (template) => _TemplateChip(
                          template: template,
                          selected: _activeTemplate == template.label,
                          onTap: () => _applyTemplate(template),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Agent name',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _locationController,
                decoration: const InputDecoration(
                  labelText: 'Location (optional)',
                  prefixIcon: Icon(Icons.place_outlined),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _ruleController,
                minLines: 4,
                maxLines: 8,
                onChanged: (_) {
                  if (_activeTemplate != null) {
                    setState(() => _activeTemplate = null);
                  }
                },
                decoration: const InputDecoration(
                  labelText: 'Natural language rule',
                  alignLabelWithHint: true,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.md),
                AppBanner(text: _error!),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(_isEditing ? 'Save changes' : 'Create agent'),
        ),
      ],
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
    return SelectableConsoleTile(
      selected: false,
      title: 'Active config · ${config.agentId}',
      subtitle: '$detectors · confidence $confidence · $ruleText',
      leading: IconChip(icon: Icons.tune_outlined, size: 34),
      trailing: StatusPill.fromStatus(config.state),
      onTap: () {},
    );
  }
}

class _Destination {
  const _Destination({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final String subtitle;
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

String _formatDate(DateTime? value) {
  if (value == null) {
    return 'unknown time';
  }
  return value.toLocal().toString().split('.').first;
}
