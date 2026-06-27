import 'package:flutter/material.dart';

import '../../design/app_colors.dart';
import '../../design/app_motion.dart';
import '../../design/app_spacing.dart';
import '../../app/theme_mode_controller.dart';
import '../../design/app_typography.dart';
import '../../services/backend_auth_client.dart';
import '../../services/realtime/realtime_client.dart';
import '../../shared/console_widgets.dart';
import 'add_camera_wizard.dart';
import 'agent_templates.dart';
import 'device_control_view.dart';

class WorkspaceView extends StatefulWidget {
  const WorkspaceView({
    required this.user,
    required this.apiClient,
    required this.onSignOut,
    this.autoLoad = true,
    this.initialDevices = const [],
    this.initialAgents = const [],
    super.key,
  });

  final BackendUser user;
  final SentinelEdgeApiClient apiClient;
  final Future<void> Function() onSignOut;
  final bool autoLoad;
  final List<EdgeDevice> initialDevices;
  final List<SurveillanceAgent> initialAgents;

  @override
  State<WorkspaceView> createState() => _WorkspaceViewState();
}

class _WorkspaceViewState extends State<WorkspaceView> {
  final _deviceSearchController = TextEditingController();
  final _agentSearchController = TextEditingController();

  List<EdgeDevice> _devices = const [];
  List<SurveillanceAgent> _agents = const [];
  List<SecurityEvent> _events = const [];
  List<MediaClip> _eventClips = const [];
  List<ToolAuditEntry> _eventAudit = const [];
  RealtimeConnection? _realtimeConnection;
  RealtimeStatus _realtimeStatus = RealtimeStatus.connecting;
  String? _selectedDeviceId;
  String? _selectedAgentId;
  String? _selectedEventId;
  String? _assigningAgentId;
  ClipPlaybackUrl? _lastPlaybackUrl;
  String? _error;
  int _selectedTab = 0;
  bool _isRefreshing = false;
  // Registration now happens in the full-screen AddCameraWizard, which manages
  // its own busy state; this stays false so the launcher button never spins.
  final bool _isRegisteringDevice = false;
  bool _isCreatingAgent = false;
  bool _isChangingAgentState = false;
  bool _isLoadingEvents = false;
  bool _isLoadingClips = false;
  bool _isLoadingAudit = false;
  bool _isRequestingPlayback = false;

  bool get _isBusy =>
      _isRefreshing ||
      _isRegisteringDevice ||
      _isCreatingAgent ||
      _isChangingAgentState ||
      _isLoadingEvents ||
      _isLoadingClips ||
      _isLoadingAudit ||
      _isRequestingPlayback;

  @override
  void initState() {
    super.initState();
    _devices = widget.initialDevices;
    _agents = widget.initialAgents;
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
      if (_shouldReturnToSignIn(error)) {
        await widget.onSignOut();
        return;
      }
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
          _eventAudit = const [];
          _selectedDeviceId = _chooseExisting(
            _selectedDeviceId,
            devices.map((device) => device.deviceId),
          );
          _selectedAgentId = _chooseExisting(
            _selectedAgentId,
            agents.map((agent) => agent.agentId),
          );
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
      if (_shouldReturnToSignIn(error)) {
        await widget.onSignOut();
        return;
      }
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
      if (_shouldReturnToSignIn(error)) {
        await widget.onSignOut();
        return;
      }
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
          _eventAudit = const [];
          _lastPlaybackUrl = null;
        });
        final selected = _selectedEventId;
        if (selected != null) {
          await _loadEventClips(selected, showSuccess: false);
          await _loadEventAudit(selected, showSuccess: false);
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

  Future<void> _loadEventAudit(
    String eventId, {
    bool showSuccess = false,
  }) async {
    await _run(
      successMessage: 'Agent activity refreshed',
      setBusy: (value) => _isLoadingAudit = value,
      showSuccess: showSuccess,
      action: () async {
        final audit = await widget.apiClient.listEventAudit(eventId);
        if (!mounted) return;
        setState(() => _eventAudit = audit);
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

  Future<void> _openDeviceControl(EdgeDevice device) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DeviceControlView(
          device: device,
          apiClient: widget.apiClient,
          agents: _agents,
          onChanged: () async {
            await _refreshDevicesOnly();
            await _refreshAgentsOnly();
          },
        ),
      ),
    );
  }

  Future<void> _openRegisterDeviceDialog() async {
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddCameraWizard(apiClient: widget.apiClient),
        fullscreenDialog: true,
      ),
    );
    if (added == true && mounted) {
      await _refreshAll(showSuccess: false);
    }
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

  bool _shouldReturnToSignIn(Object error) {
    return error is BackendAuthException &&
        (error.code == 'not_authenticated' ||
            error.code == 'invalid_session');
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
      case 'event.verified':
        // Verification finished: refresh so the verdict + agent trail update.
        final eventId = message.data['event_id']?.toString();
        _loadEvents(showSuccess: false);
        if (eventId != null && eventId == _selectedEventId) {
          _loadEventAudit(eventId);
        }
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
      0 => _devicePanel(compact),
      1 => _overviewPanel(compact),
      2 => _agentPanel(compact),
      3 => _eventsPanel(compact),
      _ => _settingsPanel(compact),
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
        _operationsPanel(),
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
              title: 'No camera selected',
              message:
                  'Register or select a camera device to anchor agent operations.',
              compact: true,
            )
          else
            _FocusRow(
              icon: Icons.videocam_outlined,
              title: selectedDevice.name,
              detail:
                  '${selectedDevice.location ?? 'No location'} ?? ${selectedDevice.healthStatus}',
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
              detail: '${selectedAgent.state} ?? ${selectedAgent.rule}',
              tone: StatusToneColor.fromStatus(selectedAgent.state),
            ),
        ],
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
          title: 'Cameras',
          subtitle:
              '${_devices.length} registered - tap a card for live controls',
          icon: Icons.videocam_outlined,
          action: AppButton(
            label: 'Add camera',
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
                  hintText: 'Search cameras',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              if (_isRefreshing && _devices.isEmpty)
                const SkeletonList()
              else if (_devices.isEmpty)
                EmptyState(
                  icon: Icons.videocam_off_outlined,
                  title: 'No cameras registered',
                  message:
                      'Add your first camera or edge device to start the surveillance loop.',
                  action: AppButton(
                    label: 'Add camera',
                    icon: Icons.add_circle_outline,
                    onPressed: _openRegisterDeviceDialog,
                  ),
                )
              else if (visibleDevices.isEmpty)
                const EmptyState(
                  icon: Icons.search_off_outlined,
                  title: 'No matching cameras',
                  message:
                      'Clear the search field to show every registered device.',
                  compact: true,
                )
              else
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: visibleDevices.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: compact ? 1 : 2,
                    crossAxisSpacing: AppSpacing.md,
                    mainAxisSpacing: AppSpacing.md,
                    childAspectRatio: compact ? 1.28 : 1.38,
                  ),
                  itemBuilder: (context, index) {
                    final device = visibleDevices[index];
                    return _CameraDeviceCard(
                      device: device,
                      selected: _selectedDeviceId == device.deviceId,
                      onTap: () {
                        setState(() => _selectedDeviceId = device.deviceId);
                        _openDeviceControl(device);
                      },
                    );
                  },
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
      title: 'Protection',
      subtitle: selectedDevice == null
          ? 'Select a camera to arm detection rules'
          : 'Detection rules for ${selectedDevice.name}',
      icon: Icons.shield_outlined,
      child: selectedDevice == null
          ? const EmptyState(
              icon: Icons.videocam_off_outlined,
              title: 'No camera selected',
              message:
                  'Pick a camera above, then arm the detection rules that should watch it.',
              compact: true,
            )
          : definitions.isEmpty
          ? const EmptyState(
              icon: Icons.radar_outlined,
              title: 'No detection rules yet',
              message:
                  'Create a rule in the Agents tab, then arm it for this camera.',
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
      subtitle: '${definitions.length} agents ?? tap to edit',
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

  Widget _settingsPanel(bool compact) {
    final account = _accountPanel();
    final preferences = _preferencesPanel();
    final about = _aboutPanel();
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          account,
          const SizedBox(height: AppSpacing.lg),
          preferences,
          const SizedBox(height: AppSpacing.lg),
          about,
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: account),
            const SizedBox(width: AppSpacing.lg),
            Expanded(child: preferences),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        about,
      ],
    );
  }

  Widget _accountPanel() {
    final theme = Theme.of(context);
    final user = widget.user;
    return ConsolePanel(
      title: 'Account',
      subtitle: 'Signed in to SentinelEdge',
      icon: Icons.person_outline,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _Avatar(user: user),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.displayName ?? user.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                    Text(
                      user.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              StatusPill(label: user.role, tone: StatusTone.neutral),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          AppButton(
            label: 'Sign out',
            icon: Icons.logout,
            variant: AppButtonVariant.secondary,
            onPressed: _isBusy ? null : () => widget.onSignOut(),
          ),
        ],
      ),
    );
  }

  Widget _preferencesPanel() {
    final controller = AppThemeModeScope.maybeOf(context);
    return ConsolePanel(
      title: 'Appearance',
      subtitle: 'Choose how SentinelEdge looks',
      icon: Icons.palette_outlined,
      child: controller == null
          ? const EmptyState(
              icon: Icons.palette_outlined,
              title: 'Theme unavailable',
              message: 'Theme control is not available in this context.',
              compact: true,
            )
          : ValueListenableBuilder<ThemeMode>(
              valueListenable: controller,
              builder: (context, mode, _) {
                return SegmentedButton<ThemeMode>(
                  segments: ThemeMode.values
                      .map(
                        (themeMode) => ButtonSegment<ThemeMode>(
                          value: themeMode,
                          icon: Icon(_themeModeIcon(themeMode)),
                          label: Text(_themeModeLabel(themeMode)),
                        ),
                      )
                      .toList(),
                  selected: {mode},
                  showSelectedIcon: false,
                  onSelectionChanged: (selection) =>
                      controller.setMode(selection.first),
                );
              },
            ),
    );
  }

  Widget _aboutPanel() {
    final realtimeLabel = switch (_realtimeStatus) {
      RealtimeStatus.live => 'Live',
      RealtimeStatus.connecting => 'Connecting',
      RealtimeStatus.reconnecting => 'Reconnecting',
      RealtimeStatus.offline => 'Offline',
    };
    return ConsolePanel(
      title: 'About',
      subtitle: 'Connection and app details',
      icon: Icons.info_outline,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _DetailLine(label: 'App', value: 'SentinelEdge'),
          _DetailLine(label: 'Backend', value: BackendAuthClient.baseUrl),
          _DetailLine(label: 'Realtime', value: realtimeLabel),
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
                (event) => _EventTimelineCard(
                  event: event,
                  selected: _selectedEventId == event.eventId,
                  onTap: () {
                    setState(() {
                      _selectedEventId = event.eventId;
                      _lastPlaybackUrl = null;
                    });
                    _loadEventClips(event.eventId);
                    _loadEventAudit(event.eventId);
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
                audit: _eventAudit,
                playbackUrl: _lastPlaybackUrl,
                isLoadingClips: _isLoadingClips,
                isLoadingAudit: _isLoadingAudit,
                isRequestingPlayback: _isRequestingPlayback,
                onRefreshClips: () => _loadEventClips(selectedEvent.eventId),
                onRefreshAudit: () => _loadEventAudit(selectedEvent.eventId),
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
      label: 'Cameras',
      subtitle: 'Live views, PTZ and protection',
      icon: Icons.videocam_outlined,
      selectedIcon: Icons.videocam,
    ),
    _Destination(
      label: 'Overview',
      subtitle: 'Fleet status at a glance',
      icon: Icons.dashboard_outlined,
      selectedIcon: Icons.dashboard,
    ),
    _Destination(
      label: 'Agents',
      subtitle: 'Author and edit detection rules',
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
      label: 'Settings',
      subtitle: 'Account and preferences',
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings,
    ),
  ];
}

class _CameraDeviceCard extends StatelessWidget {
  const _CameraDeviceCard({
    required this.device,
    required this.selected,
    required this.onTap,
  });

  final EdgeDevice device;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final online = device.healthStatus == 'online';
    final signal = device.rssi != null
        ? '${device.rssi!.toStringAsFixed(0)} dBm'
        : 'No signal';
    final fps = device.fps != null
        ? '${device.fps!.toStringAsFixed(1)} fps'
        : 'No stream';

    return AppCard(
      selected: selected,
      hoverable: true,
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppRadius.lg),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: online
                            ? const [Color(0xFF10231F), Color(0xFF091311)]
                            : const [Color(0xFF2A3036), Color(0xFF171B20)],
                      ),
                    ),
                  ),
                  Center(
                    child: Icon(
                      online
                          ? Icons.videocam_outlined
                          : Icons.videocam_off_outlined,
                      size: 46,
                      color: Colors.white.withValues(alpha: 0.62),
                    ),
                  ),
                  Positioned(
                    left: AppSpacing.md,
                    top: AppSpacing.md,
                    child: _CameraGlassLabel(
                      icon: online ? Icons.circle : Icons.circle_outlined,
                      label: online ? 'Live ready' : 'Offline',
                    ),
                  ),
                  Positioned(
                    right: AppSpacing.md,
                    bottom: AppSpacing.md,
                    child: _CameraGlassLabel(
                      icon: Icons.control_camera_outlined,
                      label: 'P ${device.currentPan} / T ${device.currentTilt}',
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        device.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    StatusPill.fromStatus(device.healthStatus),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  device.location ?? 'No location',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: _CameraMeta(icon: Icons.wifi, label: signal),
                    ),
                    Expanded(
                      child: _CameraMeta(icon: Icons.speed, label: fps),
                    ),
                    Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraGlassLabel extends StatelessWidget {
  const _CameraGlassLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.46),
        borderRadius: AppRadius.pillAll,
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white.withValues(alpha: 0.86)),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraMeta extends StatelessWidget {
  const _CameraMeta({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      children: [
        Icon(icon, size: 15, color: scheme.onSurfaceVariant),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall,
          ),
        ),
      ],
    );
  }
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
    final logoAsset = theme.brightness == Brightness.dark
        ? 'assets/brand/sentineledge-logo-light.png'
        : 'assets/brand/sentineledge-logo-dark.png';

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
                    borderRadius: BorderRadius.circular(11),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Image.asset(
                    logoAsset,
                    fit: BoxFit.cover,
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

class _EventTimelineCard extends StatelessWidget {
  const _EventTimelineCard({
    required this.event,
    required this.selected,
    required this.onTap,
  });

  final SecurityEvent event;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tone = StatusToneColor.fromStatus(event.severity);
    final title = event.summary?.isNotEmpty == true
        ? event.summary!
        : event.eventType;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppCard(
        selected: selected,
        hoverable: true,
        padding: EdgeInsets.zero,
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 92,
                decoration: BoxDecoration(
                  color: tone.base.withValues(alpha: 0.12),
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(AppRadius.lg),
                  ),
                ),
                child: Icon(
                  Icons.photo_camera_back_outlined,
                  color: tone.base,
                  size: 30,
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall,
                            ),
                          ),
                          StatusPill.fromStatus(event.severity),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        _formatDate(event.timestamp),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        children: [
                          Icon(
                            Icons.videocam_outlined,
                            size: 15,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              event.deviceId,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall,
                            ),
                          ),
                          StatusPill.fromStatus(event.status),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// AI verification verdict (from `stage3_verdict`) plus the agent's tool-call
/// trail (from `/events/{id}/audit`) — the "what the AI did and decided" story.
class _AiVerificationSection extends StatelessWidget {
  const _AiVerificationSection({
    required this.verdict,
    required this.audit,
    required this.isLoadingAudit,
    required this.onRefresh,
  });

  final Map<String, dynamic>? verdict;
  final List<ToolAuditEntry> audit;
  final bool isLoadingAudit;
  final VoidCallback onRefresh;

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_outlined, size: 18, color: scheme.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text('AI verification', style: theme.textTheme.titleSmall),
              ),
              if (isLoadingAudit)
                const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                IconButton(
                  tooltip: 'Refresh agent activity',
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _verdictBlock(context),
          const SizedBox(height: AppSpacing.md),
          Text('Agent activity', style: theme.textTheme.labelLarge),
          const SizedBox(height: AppSpacing.sm),
          _activityBlock(context),
        ],
      ),
    );
  }

  Widget _verdictBlock(BuildContext context) {
    final theme = Theme.of(context);
    final data = verdict;
    if (data == null) {
      return Text(
        'Not verified yet.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }
    if (data['status'] == 'degraded') {
      return Row(
        children: [
          const StatusPill(label: 'unavailable', tone: StatusTone.warning),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Verification could not complete${data['reason'] != null ? ' (${data['reason']})' : ''}.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      );
    }

    final verified = data['verified'] == true;
    final confidence = (data['confidence'] as num?)?.toDouble();
    final action = data['recommended_action']?.toString();
    final summary = data['summary']?.toString();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            StatusPill(
              label: verified ? 'verified' : 'not verified',
              tone: verified ? StatusTone.success : StatusTone.neutral,
            ),
            if (action != null && action.isNotEmpty)
              StatusPill(label: action, tone: StatusTone.neutral),
            if (confidence != null)
              StatusPill(
                label: '${(confidence * 100).toStringAsFixed(0)}% confident',
                tone: StatusTone.neutral,
              ),
          ],
        ),
        if (summary != null && summary.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(summary, style: theme.textTheme.bodyMedium),
        ],
      ],
    );
  }

  Widget _activityBlock(BuildContext context) {
    final theme = Theme.of(context);
    if (audit.isEmpty) {
      return Text(
        isLoadingAudit ? 'Loading agent activity…' : 'No agent actions for this event.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }
    return Column(
      children: audit.map((entry) => _ToolCallRow(entry: entry)).toList(),
    );
  }
}

class _ToolCallRow extends StatelessWidget {
  const _ToolCallRow({required this.entry});

  final ToolAuditEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final failed = !entry.ok;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            _toolIcon(entry.toolName),
            size: 18,
            color: failed ? AppColors.warning : scheme.primary,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_humanizeToolCall(entry), style: theme.textTheme.bodyMedium),
                Text(
                  failed && entry.error != null
                      ? '${_formatDate(entry.timestamp)} · ${entry.error}'
                      : _formatDate(entry.timestamp),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: failed ? AppColors.warning : scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _humanizeToolCall(ToolAuditEntry entry) {
  switch (entry.toolName) {
    case 'get_live_snapshot':
      return 'Requested a live snapshot';
    case 'pan_camera':
      final angle = entry.arguments?['angle'];
      return angle != null ? 'Panned the camera to $angle°' : 'Panned the camera';
    case 'get_device_status':
      return 'Checked device status';
    case 'query_recent_events':
      return 'Reviewed recent events';
    case 'get_event_clip':
      return 'Fetched the event clip';
    default:
      return entry.toolName;
  }
}

IconData _toolIcon(String toolName) {
  switch (toolName) {
    case 'get_live_snapshot':
      return Icons.camera_alt_outlined;
    case 'pan_camera':
      return Icons.control_camera_outlined;
    case 'get_device_status':
      return Icons.monitor_heart_outlined;
    case 'query_recent_events':
      return Icons.history_outlined;
    case 'get_event_clip':
      return Icons.movie_outlined;
    default:
      return Icons.bolt_outlined;
  }
}

class _EventDetail extends StatelessWidget {
  const _EventDetail({
    required this.event,
    required this.clips,
    required this.audit,
    required this.playbackUrl,
    required this.isLoadingClips,
    required this.isLoadingAudit,
    required this.isRequestingPlayback,
    required this.onRefreshClips,
    required this.onRefreshAudit,
    required this.onPlayback,
  });

  final SecurityEvent event;
  final List<MediaClip> clips;
  final List<ToolAuditEntry> audit;
  final ClipPlaybackUrl? playbackUrl;
  final bool isLoadingClips;
  final bool isLoadingAudit;
  final bool isRequestingPlayback;
  final VoidCallback onRefreshClips;
  final VoidCallback onRefreshAudit;
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
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: AppRadius.mdAll,
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                event.summary?.isNotEmpty == true
                    ? event.summary!
                    : event.eventType,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              _DetailLine(label: 'Camera', value: event.deviceId),
              _DetailLine(label: 'Time', value: _formatDate(event.timestamp)),
              if (event.confidence != null)
                _DetailLine(
                  label: 'Confidence',
                  value: '${(event.confidence! * 100).toStringAsFixed(1)}%',
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _AiVerificationSection(
          verdict: event.stage3Verdict,
          audit: audit,
          isLoadingAudit: isLoadingAudit,
          onRefresh: onRefreshAudit,
        ),
        const SizedBox(height: AppSpacing.md),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: EdgeInsets.zero,
          title: Text('Technical details', style: theme.textTheme.titleSmall),
          children: [
            _DetailLine(label: 'Event', value: event.eventId),
            _DetailLine(label: 'Type', value: event.eventType),
            _DetailLine(label: 'Agent', value: event.agentId),
            CodeBlock(label: 'Stage 1', value: event.stage1Result?.toString()),
            CodeBlock(label: 'Stage 2', value: event.stage2Verdict?.toString()),
            CodeBlock(label: 'Stage 3', value: event.stage3Verdict?.toString()),
          ],
        ),
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
                  '${clip.status} ?? ${clip.mimeType ?? 'media'} ?? ${clip.durationSeconds ?? 0}s',
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
            const _ThemeModeButton(),
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

class _ThemeModeButton extends StatelessWidget {
  const _ThemeModeButton();

  @override
  Widget build(BuildContext context) {
    final controller = AppThemeModeScope.maybeOf(context);
    if (controller == null) return const SizedBox.shrink();

    return ValueListenableBuilder<ThemeMode>(
      valueListenable: controller,
      builder: (context, mode, _) {
        return PopupMenuButton<ThemeMode>(
          tooltip: 'Theme',
          initialValue: mode,
          icon: Icon(_themeModeIcon(mode)),
          onSelected: controller.setMode,
          itemBuilder: (context) => ThemeMode.values
              .map(
                (themeMode) => PopupMenuItem<ThemeMode>(
                  value: themeMode,
                  child: Row(
                    children: [
                      Icon(_themeModeIcon(themeMode), size: 18),
                      const SizedBox(width: AppSpacing.md),
                      Text(_themeModeLabel(themeMode)),
                    ],
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

IconData _themeModeIcon(ThemeMode mode) => switch (mode) {
  ThemeMode.system => Icons.brightness_auto_outlined,
  ThemeMode.light => Icons.light_mode_outlined,
  ThemeMode.dark => Icons.dark_mode_outlined,
};

String _themeModeLabel(ThemeMode mode) => switch (mode) {
  ThemeMode.system => 'System',
  ThemeMode.light => 'Light',
  ThemeMode.dark => 'Dark',
};
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
        ? '${agent.rule}  ??  also on $elsewhere other ${elsewhere == 1 ? 'camera' : 'cameras'}'
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



