import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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

const _aiAgentIconAsset = 'assets/brand/erlang-ai-agent-icon.png';

/// The console tabs, in sidebar/nav-bar order, each with the URL path segment
/// it maps to (`/console/<path>`). The ordinal is the tab index used by the
/// navigation widgets and the body switch.
enum WorkspaceSection {
  cameras('cameras'),
  overview('overview'),
  agents('agents'),
  events('events'),
  settings('settings');

  const WorkspaceSection(this.path);

  final String path;

  int get tabIndex => index;

  static WorkspaceSection fromIndex(int index) =>
      values[index.clamp(0, values.length - 1)];
}

class WorkspaceView extends StatefulWidget {
  const WorkspaceView({
    required this.user,
    required this.apiClient,
    required this.onSignOut,
    this.section = WorkspaceSection.cameras,
    this.selectedEventId,
    this.autoLoad = true,
    this.initialDevices = const [],
    this.initialAgents = const [],
    super.key,
  });

  final BackendUser user;
  final SentinelEdgeApiClient apiClient;
  final Future<void> Function() onSignOut;

  /// The active tab, driven by the URL (`/console/<section>`).
  final WorkspaceSection section;

  /// The event selected in the Events tab, driven by the URL
  /// (`/console/events/<eventId>`); null when no event is selected.
  final String? selectedEventId;

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
  ClipPlaybackUrl? _lastPlaybackUrl;
  String? _error;
  int _selectedTab = 0;
  bool _isRefreshing = false;
  // Registration now happens in the full-screen AddCameraWizard, which manages
  // its own busy state; this stays false so the launcher button never spins.
  final bool _isRegisteringDevice = false;
  bool _isCreatingAgent = false;
  bool _isLoadingEvents = false;
  bool _isLoadingClips = false;
  bool _isLoadingAudit = false;
  bool _isRequestingPlayback = false;

  bool get _isBusy =>
      _isRefreshing ||
      _isRegisteringDevice ||
      _isCreatingAgent ||
      _isLoadingEvents ||
      _isLoadingClips ||
      _isLoadingAudit ||
      _isRequestingPlayback;

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.section.tabIndex;
    _selectedEventId = widget.selectedEventId;
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
      if (_sectionLoadsEvents) {
        _loadEvents(showSuccess: false);
      }
    }
    _realtimeConnection = connectRealtime(
      onMessage: _handleRealtimeMessage,
      onStatus: (status) {
        if (!mounted) return;
        setState(() => _realtimeStatus = status);
      },
    );
  }

  /// The Overview and Events tabs both render the event timeline, so both need
  /// the events list loaded when entered (or deep-linked).
  bool get _sectionLoadsEvents =>
      widget.section == WorkspaceSection.events ||
      widget.section == WorkspaceSection.overview;

  @override
  void didUpdateWidget(covariant WorkspaceView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The URL changed: sync the active tab and the selected event from the
    // route rather than from local taps.
    if (oldWidget.section != widget.section) {
      setState(() => _selectedTab = widget.section.tabIndex);
      if (_sectionLoadsEvents && _events.isEmpty) {
        _loadEvents(showSuccess: false);
      }
    }
    if (oldWidget.selectedEventId != widget.selectedEventId) {
      _applySelectedEvent(widget.selectedEventId);
    }
  }

  void _applySelectedEvent(String? eventId) {
    setState(() {
      _selectedEventId = eventId;
      _lastPlaybackUrl = null;
      _eventClips = const [];
      _eventAudit = const [];
    });
    if (eventId != null) {
      _loadEventClips(eventId);
      _loadEventAudit(eventId);
    }
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
    setState(() => _selectedDeviceId = device.deviceId);
    // The camera detail is a real route (/console/cameras/:deviceId), so the
    // URL is shareable and survives refresh. Refresh the fleet on return since
    // the detail screen can rename/delete the camera or change protection.
    await context.push('/console/cameras/${device.deviceId}');
    if (!mounted) return;
    await _refreshDevicesOnly();
    await _refreshAgentsOnly();
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
    final mode = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => const _CreateAgentChooser(),
    );
    if (mode == null || !mounted) return;
    final result = await showDialog<_AgentFormResult>(
      context: context,
      builder: (_) => mode == 'ai'
          ? _AgentBuilderDialog(apiClient: widget.apiClient)
          : const _AgentFormDialog(),
    );
    if (result == null) return;
    await _createAgent(
      name: result.name,
      location: result.location,
      rule: result.rule,
    );
  }

  Future<void> _openAiAgentChat() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _AiAgentChatScreen(user: widget.user),
      ),
    );
  }

  Future<void> _openEditAgentDialog(SurveillanceAgent agent) async {
    final mode = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => const _CreateAgentChooser(isEdit: true),
    );
    if (mode == null || !mounted) return;
    final result = await showDialog<_AgentFormResult>(
      context: context,
      builder: (_) => mode == 'ai'
          ? _AgentBuilderDialog(apiClient: widget.apiClient, initialAgent: agent)
          : _AgentFormDialog(agent: agent),
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

  bool _shouldReturnToSignIn(Object error) {
    return error is BackendAuthException &&
        (error.code == 'not_authenticated' || error.code == 'invalid_session');
  }

  void _selectTab(int index) {
    // Navigate rather than setState: the URL becomes the source of truth and
    // didUpdateWidget syncs _selectedTab (and lazy-loads events) in response.
    context.go('/console/${WorkspaceSection.fromIndex(index).path}');
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
            floatingActionButton: _AiAgentChatFab(
              compact: true,
              onPressed: _openAiAgentChat,
            ),
            floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
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
          floatingActionButton: _AiAgentChatFab(
            compact: false,
            onPressed: _openAiAgentChat,
          ),
          floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
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
    final offlineDevices = _devices
        .where((device) => device.healthStatus != 'online')
        .toList();
    final weakSignalDevices = _devices
        .where((device) => device.rssi != null && device.rssi! <= -70)
        .toList();
    final lowFpsDevices = _devices
        .where((device) => device.fps != null && device.fps! < 8)
        .toList();
    final activeAssignments = _agents
        .where((agent) => !agent.isDefinition && agent.state == 'armed')
        .length;
    final assignedDeviceIds = _agents
        .where((agent) => agent.deviceId != null && agent.state == 'armed')
        .map((agent) => agent.deviceId!)
        .toSet();
    final unassignedDevices = _devices
        .where((device) => !assignedDeviceIds.contains(device.deviceId))
        .toList();
    final eventsToday = _events.where(_isToday).length;
    final pendingEvents = _events.where(_needsReview).toList();
    final recentEvents = [..._events]
      ..sort(
        (a, b) => (b.timestamp ?? DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(a.timestamp ?? DateTime.fromMillisecondsSinceEpoch(0)),
      );
    final avgFps = _averageFps(_devices);
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
              label: 'Online cameras',
              value: '$onlineDevices/${_devices.length}',
              icon: Icons.videocam_outlined,
              accent: onlineDevices == _devices.length
                  ? AppColors.success
                  : AppColors.warning,
              caption: offlineDevices.isEmpty ? 'all live' : 'attention',
            ),
            MetricTile(
              label: 'Armed agents',
              value: activeAssignments.toString(),
              icon: Icons.radar_outlined,
              accent: AppColors.success,
              caption: '${unassignedDevices.length} unassigned',
            ),
            MetricTile(
              label: 'Events today',
              value: eventsToday.toString(),
              icon: Icons.timeline_outlined,
              accent: AppColors.info,
              caption: _events.isEmpty ? 'load events' : '24h',
            ),
            MetricTile(
              label: 'Pending review',
              value: pendingEvents.length.toString(),
              icon: Icons.fact_check_outlined,
              accent: pendingEvents.isEmpty
                  ? AppColors.success
                  : AppColors.warning,
              caption: pendingEvents.isEmpty ? 'clear' : 'review',
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        if (compact) ...[
          _attentionPanel(
            offlineDevices: offlineDevices,
            weakSignalDevices: weakSignalDevices,
            lowFpsDevices: lowFpsDevices,
            unassignedDevices: unassignedDevices,
            pendingEvents: pendingEvents,
          ),
          const SizedBox(height: AppSpacing.lg),
          _recentActivityPanel(recentEvents.take(5).toList()),
        ] else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 5,
                child: _attentionPanel(
                  offlineDevices: offlineDevices,
                  weakSignalDevices: weakSignalDevices,
                  lowFpsDevices: lowFpsDevices,
                  unassignedDevices: unassignedDevices,
                  pendingEvents: pendingEvents,
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                flex: 4,
                child: _recentActivityPanel(recentEvents.take(5).toList()),
              ),
            ],
          ),
        const SizedBox(height: AppSpacing.lg),
        _performancePanel(avgFps: avgFps, weakSignalDevices: weakSignalDevices),
        const SizedBox(height: AppSpacing.lg),
        _operationsPanel(),
      ],
    );
  }

  bool _isToday(SecurityEvent event) {
    final timestamp = event.timestamp?.toLocal();
    if (timestamp == null) return false;
    final now = DateTime.now();
    return timestamp.year == now.year &&
        timestamp.month == now.month &&
        timestamp.day == now.day;
  }

  bool _needsReview(SecurityEvent event) {
    final status = event.status.toLowerCase();
    if (status.contains('verified') || status.contains('closed')) return false;
    return event.stage3Verdict == null ||
        status.contains('pending') ||
        status.contains('new') ||
        status.contains('open');
  }

  double? _averageFps(List<EdgeDevice> devices) {
    final values = devices
        .map((device) => device.fps)
        .whereType<double>()
        .where((fps) => fps > 0)
        .toList();
    if (values.isEmpty) return null;
    return values.reduce((a, b) => a + b) / values.length;
  }

  String _cameraName(String deviceId) {
    return _devices
            .where((device) => device.deviceId == deviceId)
            .map((device) => device.name)
            .firstOrNull ??
        deviceId;
  }

  Widget _attentionPanel({
    required List<EdgeDevice> offlineDevices,
    required List<EdgeDevice> weakSignalDevices,
    required List<EdgeDevice> lowFpsDevices,
    required List<EdgeDevice> unassignedDevices,
    required List<SecurityEvent> pendingEvents,
  }) {
    final items = <Widget>[
      if (offlineDevices.isNotEmpty)
        _InsightRow(
          icon: Icons.signal_wifi_off_outlined,
          title: '${offlineDevices.length} camera offline',
          detail: offlineDevices
              .map((device) => device.name)
              .take(3)
              .join(', '),
          tone: StatusTone.danger,
        ),
      if (weakSignalDevices.isNotEmpty)
        _InsightRow(
          icon: Icons.wifi_2_bar_outlined,
          title: '${weakSignalDevices.length} weak Wi-Fi signal',
          detail: weakSignalDevices
              .map((device) => device.name)
              .take(3)
              .join(', '),
          tone: StatusTone.warning,
        ),
      if (lowFpsDevices.isNotEmpty)
        _InsightRow(
          icon: Icons.speed_outlined,
          title: '${lowFpsDevices.length} low FPS stream',
          detail: lowFpsDevices.map((device) => device.name).take(3).join(', '),
          tone: StatusTone.warning,
        ),
      if (unassignedDevices.isNotEmpty)
        _InsightRow(
          icon: Icons.shield_outlined,
          title: '${unassignedDevices.length} camera without armed agent',
          detail: unassignedDevices
              .map((device) => device.name)
              .take(3)
              .join(', '),
          tone: StatusTone.neutral,
        ),
      if (pendingEvents.isNotEmpty)
        _InsightRow(
          icon: Icons.fact_check_outlined,
          title: '${pendingEvents.length} event pending review',
          detail: pendingEvents
              .map((event) => _cameraName(event.deviceId))
              .take(3)
              .join(', '),
          tone: StatusTone.warning,
        ),
    ];

    return ConsolePanel(
      title: 'Attention needed',
      subtitle: 'Issues that may affect coverage',
      icon: Icons.priority_high_outlined,
      child: items.isEmpty
          ? const EmptyState(
              icon: Icons.verified_outlined,
              title: 'Coverage looks healthy',
              message: 'No offline cameras, weak streams, or pending reviews.',
              compact: true,
            )
          : Column(children: _withSpacing(items)),
    );
  }

  Widget _recentActivityPanel(List<SecurityEvent> recentEvents) {
    return ConsolePanel(
      title: 'Recent activity',
      subtitle: 'Latest detections and verification states',
      icon: Icons.history_outlined,
      action: AppButton(
        label: 'Review',
        icon: Icons.open_in_new,
        variant: AppButtonVariant.secondary,
        onPressed: () => _selectTab(3),
      ),
      child: recentEvents.isEmpty
          ? EmptyState(
              icon: _isLoadingEvents
                  ? Icons.hourglass_top_outlined
                  : Icons.event_available_outlined,
              title: _isLoadingEvents ? 'Loading events' : 'No recent events',
              message: _isLoadingEvents
                  ? 'Fetching recent detections from the backend.'
                  : 'New detections will appear here as cameras report them.',
              compact: true,
            )
          : Column(
              children: _withSpacing(
                recentEvents
                    .map(
                      (event) => _InsightRow(
                        icon: Icons.warning_amber_outlined,
                        title: _cameraName(event.deviceId),
                        detail:
                            '${event.eventType} - ${event.severity} - ${_formatDate(event.timestamp)}',
                        tone: StatusToneColor.fromStatus(event.severity),
                        trailing: StatusPill.fromStatus(event.status),
                      ),
                    )
                    .toList(),
              ),
            ),
    );
  }

  Widget _performancePanel({
    required double? avgFps,
    required List<EdgeDevice> weakSignalDevices,
  }) {
    final weakest = _devices.where((device) => device.rssi != null).toList()
      ..sort((a, b) => a.rssi!.compareTo(b.rssi!));
    return ConsolePanel(
      title: 'Camera performance',
      subtitle: 'Signal and stream quality summary',
      icon: Icons.monitor_heart_outlined,
      child: Row(
        children: [
          Expanded(
            child: _MiniStat(
              label: 'Average FPS',
              value: avgFps == null ? '--' : avgFps.toStringAsFixed(1),
              icon: Icons.speed_outlined,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: _MiniStat(
              label: 'Weak signals',
              value: weakSignalDevices.length.toString(),
              icon: Icons.wifi_2_bar_outlined,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: _MiniStat(
              label: 'Weakest RSSI',
              value: weakest.isEmpty
                  ? '--'
                  : '${weakest.first.rssi!.toStringAsFixed(0)} dBm',
              icon: Icons.network_check_outlined,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _withSpacing(List<Widget> children) {
    return [
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0) const SizedBox(height: AppSpacing.sm),
        children[i],
      ],
    ];
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
    }).toList()
      // Favorited cameras (heart) float to the top; stable by name otherwise.
      ..sort((a, b) {
        if (a.isFavorite != b.isFavorite) {
          return a.isFavorite ? -1 : 1;
        }
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

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
                    crossAxisCount: compact ? 2 : 4,
                    crossAxisSpacing: AppSpacing.md,
                    mainAxisSpacing: AppSpacing.md,
                    childAspectRatio: 1.08,
                  ),
                  itemBuilder: (context, index) {
                    final device = visibleDevices[index];
                    return _CameraDeviceCard(
                      device: device,
                      selected: _selectedDeviceId == device.deviceId,
                      armedCount: _armedCountForDevice(device.deviceId),
                      onTap: () => _openDeviceControl(device),
                      onArmTap: () => _openQuickArm(device),
                    );
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }

  List<SurveillanceAgent> get _definitions =>
      _agents.where((agent) => agent.isDefinition).toList();

  // Rules armed on a camera = sub-agents bound to that device.
  int _armedCountForDevice(String deviceId) => _agents
      .where((agent) => !agent.isDefinition && agent.deviceId == deviceId)
      .length;

  Future<void> _openQuickArm(EdgeDevice device) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _QuickArmSheet(
        device: device,
        apiClient: widget.apiClient,
        agents: _agents,
        onChanged: _refreshAgentsOnly,
      ),
    );
  }

  Iterable<SurveillanceAgent> _subsForDefinition(String definitionId) =>
      _agents.where((agent) => agent.parentAgentId == definitionId);

  int _assignmentCount(String definitionId) =>
      _subsForDefinition(definitionId).length;

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
      subtitle: 'Signed in to Erlang AI Vision',
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
      subtitle: 'Your theme choice is saved on this device',
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
                final darkMode = mode == ThemeMode.dark;
                return Align(
                  alignment: Alignment.centerLeft,
                  child: _ThemeModeToggle(
                    darkMode: darkMode,
                    onChanged: controller.setDarkMode,
                    showLabel: true,
                  ),
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
          const _DetailLine(label: 'App', value: 'Erlang AI Vision'),
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
                  onTap: () =>
                      context.go('/console/events/${event.eventId}'),
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
    required this.armedCount,
    required this.onTap,
    required this.onArmTap,
  });

  final EdgeDevice device;
  final bool selected;
  final int armedCount;
  final VoidCallback onTap;
  final VoidCallback onArmTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final online = device.healthStatus == 'online';
    final statusColor = StatusToneColor.fromStatus(device.healthStatus).base;
    final bodyFill = online
        ? scheme.surface
        : Color.alphaBlend(
            scheme.onSurface.withValues(alpha: 0.045),
            scheme.surface,
          );
    // Signature: a cool "AI/tech" gradient for live cameras (contrasts the
    // app's red brand); a quiet slate gradient when the camera is offline.
    final headerColors = online
        ? const [Color(0xFF312E81), Color(0xFF7C3AED), Color(0xFF06B6D4)]
        : const [Color(0xFF334155), Color(0xFF475569), Color(0xFF64748B)];

    return AppCard(
      selected: selected,
      hoverable: true,
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: ClipRRect(
        borderRadius: AppRadius.lgAll,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Gradient header — fills the top and carries the thumbnail + status.
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: headerColors,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.28),
                      ),
                    ),
                    child: Opacity(
                      opacity: online ? 1 : 0.6,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(9),
                        child: Image.asset(
                          'assets/brand/erlang-ai-camera-tile-icon.png',
                          width: 34,
                          height: 34,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  _GlassStatusPill(
                    label: online ? 'Live' : 'Offline',
                    dotColor: statusColor,
                  ),
                ],
              ),
            ),
            // Body — name, location, and the favorite heart pinned bottom-right.
            Expanded(
              child: Container(
                width: double.infinity,
                color: bodyFill,
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: online
                            ? scheme.onSurface
                            : scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      device.location ?? _cameraSummary(device),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        _ArmShieldChip(count: armedCount, onTap: onArmTap),
                        const Spacer(),
                        if (device.isFavorite)
                          const Icon(
                            Icons.favorite,
                            size: 18,
                            color: AppColors.danger,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tappable armed-status chip on a camera card. Opens the quick-arm sheet.
class _ArmShieldChip extends StatelessWidget {
  const _ArmShieldChip({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final armed = count > 0;
    final color = armed ? AppColors.success : scheme.onSurfaceVariant;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: AppRadius.pillAll,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: armed ? 0.12 : 0.06),
            borderRadius: AppRadius.pillAll,
            border: Border.all(
              color: color.withValues(alpha: armed ? 0.35 : 0.20),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                armed ? Icons.shield : Icons.shield_outlined,
                size: 13,
                color: color,
              ),
              const SizedBox(width: 4),
              Text(
                armed ? '$count armed' : 'Arm',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet to arm/disarm detection rules on a single camera. Rules whose
/// detectors match what this camera already watches are surfaced as recommended.
class _QuickArmSheet extends StatefulWidget {
  const _QuickArmSheet({
    required this.device,
    required this.apiClient,
    required this.agents,
    required this.onChanged,
  });

  final EdgeDevice device;
  final SentinelEdgeApiClient apiClient;
  final List<SurveillanceAgent> agents;
  final Future<void> Function() onChanged;

  @override
  State<_QuickArmSheet> createState() => _QuickArmSheetState();
}

class _QuickArmSheetState extends State<_QuickArmSheet> {
  late List<SurveillanceAgent> _agents = widget.agents;
  String? _busyId;
  String? _error;

  List<SurveillanceAgent> get _definitions =>
      _agents.where((agent) => agent.isDefinition).toList();

  bool _armed(String definitionId) => _agents.any(
    (agent) =>
        agent.parentAgentId == definitionId &&
        agent.deviceId == widget.device.deviceId,
  );

  Set<String> _classesOf(SurveillanceAgent agent) {
    final raw = agent.compiledEdgeConfig['classes'];
    return raw is List ? raw.map((e) => e.toString()).toSet() : <String>{};
  }

  // What this camera already watches, inferred from its armed sub-agents.
  Set<String> get _deviceClasses => _agents
      .where((agent) => agent.deviceId == widget.device.deviceId)
      .expand(_classesOf)
      .toSet();

  bool _recommended(SurveillanceAgent definition) {
    final deviceClasses = _deviceClasses;
    if (deviceClasses.isEmpty) return false;
    return _classesOf(definition).intersection(deviceClasses).isNotEmpty;
  }

  Future<void> _reload() async {
    final agents = await widget.apiClient.listAgents();
    if (!mounted) return;
    setState(() => _agents = agents);
    await widget.onChanged();
  }

  Future<void> _toggle(SurveillanceAgent definition, bool arm) async {
    setState(() {
      _busyId = definition.agentId;
      _error = null;
    });
    try {
      if (arm) {
        await widget.apiClient.assignAgent(
          definition.agentId,
          deviceId: widget.device.deviceId,
        );
      } else {
        await widget.apiClient.unassignAgent(
          definition.agentId,
          deviceId: widget.device.deviceId,
        );
      }
      await _reload();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _armRecommended() async {
    for (final definition in _definitions.where(_recommended)) {
      if (!_armed(definition.agentId)) {
        await _toggle(definition, true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final definitions = _definitions;
    final recommended = definitions.where(_recommended).toList();
    final others = definitions.where((d) => !_recommended(d)).toList();
    final unarmedRecommended = recommended
        .where((d) => !_armed(d.agentId))
        .toList();

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Arm ${widget.device.name}', style: theme.textTheme.titleMedium),
              const SizedBox(height: 2),
              Text(
                'Choose which detection rules watch this camera',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              if (definitions.isEmpty)
                const _CompactSheetEmpty()
              else
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (recommended.isNotEmpty)
                          _sectionLabel('Recommended for this scene'),
                        ...recommended.map(_ruleRow),
                        if (others.isNotEmpty) _sectionLabel('Other rules'),
                        ...others.map(_ruleRow),
                      ],
                    ),
                  ),
                ),
              if (unarmedRecommended.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                AppButton(
                  label: 'Arm recommended (${unarmedRecommended.length})',
                  icon: Icons.shield_outlined,
                  onPressed: _busyId == null ? _armRecommended : null,
                  expand: true,
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                AppBanner(text: _error!),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: 4),
    child: Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        letterSpacing: 0.6,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  Widget _ruleRow(SurveillanceAgent definition) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final armed = _armed(definition.agentId);
    final busy = _busyId == definition.agentId;
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  definition.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  definition.rule,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
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
            Switch(
              value: armed,
              onChanged: _busyId == null
                  ? (value) => _toggle(definition, value)
                  : null,
            ),
        ],
      ),
    );
  }
}

class _CompactSheetEmpty extends StatelessWidget {
  const _CompactSheetEmpty();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Column(
        children: [
          Icon(
            Icons.radar_outlined,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text('No detection rules yet', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            'Create a rule in the Agents tab, then arm it here.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

String _cameraSummary(EdgeDevice device) {
  if (device.fps != null) return '${device.fps!.toStringAsFixed(1)} fps';
  if (device.rssi != null) return '${device.rssi!.toStringAsFixed(0)} dBm';
  return 'Camera device';
}

class _GlassStatusPill extends StatelessWidget {
  const _GlassStatusPill({required this.label, required this.dotColor});

  final String label;
  final Color dotColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: AppRadius.pillAll,
        border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
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
        ? 'assets/brand/erlang-ai-vision-logo-light.png'
        : 'assets/brand/erlang-ai-vision-logo-dark.png';
    const iconAsset = 'assets/brand/erlang-ai-vision-icon.png';

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
                if (extended)
                  Expanded(
                    child: SizedBox(
                      height: 42,
                      child: Image.asset(
                        logoAsset,
                        fit: BoxFit.contain,
                        alignment: Alignment.centerLeft,
                      ),
                    ),
                  )
                else
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(11),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Image.asset(iconAsset, fit: BoxFit.contain),
                  ),
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
              Icon(
                Icons.auto_awesome_outlined,
                size: 18,
                color: scheme.primary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'AI verification',
                  style: theme.textTheme.titleSmall,
                ),
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
        isLoadingAudit
            ? 'Loading agent activity…'
            : 'No agent actions for this event.',
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
                Text(
                  _humanizeToolCall(entry),
                  style: theme.textTheme.bodyMedium,
                ),
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
      return angle != null
          ? 'Panned the camera to $angle°'
          : 'Panned the camera';
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

class _InsightRow extends StatelessWidget {
  const _InsightRow({
    required this.icon,
    required this.title,
    required this.detail,
    required this.tone,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String detail;
  final StatusTone tone;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          IconChip(icon: icon, color: tone.base, size: 34),
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
                  detail.isEmpty ? 'No detail available' : detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppSpacing.sm),
            trailing!,
          ],
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: scheme.primary),
          const SizedBox(height: AppSpacing.sm),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium,
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
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

class _AiAgentChatFab extends StatelessWidget {
  const _AiAgentChatFab({required this.compact, required this.onPressed});

  final bool compact;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      // The orb is its own dark glass surface + glow, so the FAB itself is
      // transparent and flat — the aurora provides the shape and shadow.
      return FloatingActionButton(
        tooltip: 'Erlang AI Agent',
        onPressed: onPressed,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        highlightElevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        child: const _AnimatedAiAgentIcon(size: 56),
      );
    }

    return FloatingActionButton.extended(
      tooltip: 'Erlang AI Agent',
      onPressed: onPressed,
      backgroundColor: AppColors.darkSurface,
      foregroundColor: Colors.white,
      icon: const _AnimatedAiAgentIcon(size: 34),
      label: const Text('AI Agent'),
    );
  }
}

class _AiAgentChatScreen extends StatelessWidget {
  const _AiAgentChatScreen({required this.user});

  final BackendUser user;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final compact = MediaQuery.sizeOf(context).width < AppBreakpoints.compact;
    final firstName = (user.displayName?.trim().isNotEmpty == true)
        ? user.displayName!.trim().split(' ').first
        : user.email.split('@').first;
    final prompts = const [
      'Which cameras need attention right now?',
      'Summarize today\'s security events.',
      'Help me create a smarter agent rule.',
      'What should I review before leaving?',
    ];

    return Scaffold(
      backgroundColor: theme.brightness == Brightness.dark
          ? AppColors.darkBackground
          : scheme.surface,
      appBar: AppBar(
        title: const Text('Erlang AI Agent'),
        actions: [
          IconButton(
            tooltip: 'Agent menu',
            onPressed: null,
            icon: const Icon(Icons.menu_rounded),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                compact ? AppSpacing.lg : AppSpacing.xxl,
                compact ? AppSpacing.md : AppSpacing.xl,
                compact ? AppSpacing.lg : AppSpacing.xxl,
                AppSpacing.lg,
              ),
              child: Column(
                children: [
                  Expanded(
                    child: ListView(
                      children: [
                        const SizedBox(height: AppSpacing.lg),
                        const Center(child: _AnimatedAiAgentIcon(size: 86)),
                        const SizedBox(height: AppSpacing.xl),
                        Text(
                          'Hi, I\'m Erlang AI Agent.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          'Ready when the agent backend is connected, $firstName.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xxl),
                        ...prompts.map(
                          (prompt) => _AgentSuggestionRow(label: prompt),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const _AgentComposerDock(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AnimatedAiAgentIcon extends StatefulWidget {
  const _AnimatedAiAgentIcon({this.size = 88});

  final double size;

  @override
  State<_AnimatedAiAgentIcon> createState() => _AnimatedAiAgentIconState();
}

class _AnimatedAiAgentIconState extends State<_AnimatedAiAgentIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reducedMotion = AppMotion.reduced(context);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = reducedMotion ? 0.0 : _controller.value;
        // 0..1 breathing curve that drives the soft pulsing outer glow.
        final breath = 0.5 + 0.5 * math.sin(t * math.pi * 2);
        return SizedBox.square(
          dimension: widget.size,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              // Twin coloured glows offset to opposite sides make the whole
              // orb read as a single soft light source, not a flat disc.
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.16 + breath * 0.16),
                  blurRadius: widget.size * (0.24 + breath * 0.14),
                  spreadRadius: widget.size * 0.01,
                  offset: Offset(-widget.size * 0.04, widget.size * 0.06),
                ),
                BoxShadow(
                  color: AppColors.info.withValues(alpha: 0.18 + breath * 0.16),
                  blurRadius: widget.size * (0.28 + breath * 0.16),
                  spreadRadius: widget.size * 0.01,
                  offset: Offset(widget.size * 0.04, widget.size * 0.10),
                ),
              ],
            ),
            child: ClipOval(
              child: CustomPaint(
                painter: _AgentAuroraPainter(progress: t),
                child: Center(
                  // The mascot floats directly on the aurora — its own
                  // transparent bubble shape lets the glow show through.
                  child: _AiAgentIconMark(size: widget.size * 0.74),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A calm "liquid aurora" background: a dark glass disc lit from within by two
/// drifting pools of light — one red, one blue — blended additively so where
/// they overlap the light brightens toward magenta/white instead of muddying.
class _AgentAuroraPainter extends CustomPainter {
  const _AgentAuroraPainter({required this.progress});

  final double progress;

  static const _red = Color(0xFFF03A24);
  static const _blue = Color(0xFF2E6BF0);
  static const _spark = Color(0xFFFF4D7D);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = size.shortestSide / 2;
    final phase = progress * math.pi * 2;
    final breath = 0.5 + 0.5 * math.sin(phase);
    final drift = math.sin(phase);

    // 1. Dark glass base so the coloured light reads as a glow.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFF17213B), Color(0xFF080B14)],
          stops: [0.0, 1.0],
        ).createShader(rect),
    );

    // Keep every glow contained within the disc.
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: center, radius: radius)));

    void glow(double angle, double dist, double blobRadius, Color color, double alpha) {
      final c = center + Offset(math.cos(angle) * dist, math.sin(angle) * dist);
      final r = Rect.fromCircle(center: c, radius: blobRadius);
      canvas.drawCircle(
        c,
        blobRadius,
        Paint()
          ..blendMode = BlendMode.plus // additive: overlaps brighten, never mud
          ..shader = RadialGradient(
            colors: [color.withValues(alpha: alpha), color.withValues(alpha: 0)],
            stops: const [0.0, 1.0],
          ).createShader(r),
      );
    }

    // 2. Red and blue pools drifting on opposite sides, breathing in size.
    glow(phase * 0.9, radius * (0.34 + 0.08 * drift),
        radius * (0.82 + 0.10 * breath), _red, 0.80);
    glow(phase * 0.9 + math.pi + 0.5, radius * (0.36 - 0.08 * drift),
        radius * (0.84 + 0.10 * (1 - breath)), _blue, 0.82);
    // A small mingling spark keeps the centre alive without clutter.
    glow(-phase * 0.6, radius * 0.16 * drift,
        radius * (0.42 + 0.08 * breath), _spark, 0.28);

    // 3. Glassy specular highlight, upper-left.
    final hl = center + Offset(-radius * 0.30, -radius * 0.34);
    canvas.drawCircle(
      hl,
      radius * 0.60,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = RadialGradient(
          colors: [Colors.white.withValues(alpha: 0.20), Colors.white.withValues(alpha: 0)],
          stops: const [0.0, 1.0],
        ).createShader(Rect.fromCircle(center: hl, radius: radius * 0.60)),
    );

    // 4. Gentle light lift behind the mascot so its dark outline stays legible.
    canvas.drawCircle(
      center,
      radius * 0.52,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = RadialGradient(
          colors: [Colors.white.withValues(alpha: 0.10), Colors.white.withValues(alpha: 0)],
          stops: const [0.0, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: radius * 0.52)),
    );

    // 5. A soft highlight arc sweeping the rim — definition without a hard ring.
    canvas.drawCircle(
      center,
      radius - 1,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..shader = SweepGradient(
          colors: [
            Colors.white.withValues(alpha: 0.0),
            Colors.white.withValues(alpha: 0.26),
            Colors.white.withValues(alpha: 0.0),
            Colors.white.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.12, 0.36, 1.0],
          transform: GradientRotation(phase),
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _AgentAuroraPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _AgentSuggestionRow extends StatelessWidget {
  const _AgentSuggestionRow({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.subdirectory_arrow_right_rounded,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AgentComposerDock extends StatelessWidget {
  const _AgentComposerDock();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            enabled: false,
            decoration: InputDecoration(
              hintText: 'Ask anything',
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              prefixIcon: const Icon(Icons.chat_bubble_outline),
              suffixIcon: IconButton(
                tooltip: 'Voice input',
                onPressed: null,
                icon: const Icon(Icons.mic_none_rounded),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: null,
              icon: const Icon(Icons.auto_awesome_outlined, size: 18),
              label: const Text('Reason'),
            ),
          ),
        ],
      ),
    );
  }
}

class _AiAgentIconMark extends StatelessWidget {
  const _AiAgentIconMark({this.size = 36});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: Image.asset(
        _aiAgentIconAsset,
        fit: BoxFit.contain,
        semanticLabel: 'Erlang AI Agent',
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
        final darkMode = mode == ThemeMode.dark;
        return _ThemeModeToggle(
          darkMode: darkMode,
          onChanged: controller.setDarkMode,
        );
      },
    );
  }
}

class _ThemeModeToggle extends StatelessWidget {
  const _ThemeModeToggle({
    required this.darkMode,
    required this.onChanged,
    this.showLabel = false,
  });

  final bool darkMode;
  final ValueChanged<bool> onChanged;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = darkMode ? 'Night' : 'Day';
    final accent = darkMode ? AppColors.primary : AppColors.warning;
    final background = darkMode
        ? const LinearGradient(
            colors: [AppColors.primaryPressed, AppColors.primary],
          )
        : LinearGradient(colors: [AppColors.neutral100, AppColors.neutral150]);

    final toggle = Tooltip(
      message: darkMode ? 'Switch to day mode' : 'Switch to night mode',
      child: Semantics(
        button: true,
        toggled: darkMode,
        label: '$label mode',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: AppRadius.pillAll,
            onTap: () => onChanged(!darkMode),
            child: AnimatedContainer(
              duration: AppMotion.duration(context, AppMotion.base),
              curve: AppMotion.standard,
              width: 66,
              height: 34,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                gradient: background,
                borderRadius: AppRadius.pillAll,
                border: Border.all(
                  color: darkMode
                      ? AppColors.primaryHover
                      : theme.colorScheme.outlineVariant,
                ),
              ),
              child: AnimatedAlign(
                duration: AppMotion.duration(context, AppMotion.base),
                curve: AppMotion.standard,
                alignment: darkMode
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(
                    darkMode ? Icons.nightlight_round : Icons.wb_sunny_outlined,
                    size: 16,
                    color: darkMode
                        ? AppColors.primaryPressed
                        : AppColors.warning,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showLabel) ...[
          Text(
            '$label mode',
            style: theme.textTheme.labelMedium?.copyWith(
              color: accent,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
        toggle,
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

/// Conversational agent builder. The user describes what to watch for; the AI
/// refines it over a few turns and proposes a rule + preview, then saves.
class _AgentBuilderDialog extends StatefulWidget {
  const _AgentBuilderDialog({required this.apiClient, this.initialAgent});

  final SentinelEdgeApiClient apiClient;

  /// When set, the builder edits this agent: the chat is seeded with its current
  /// rule and the proposal starts populated so it can be saved after tweaking.
  final SurveillanceAgent? initialAgent;

  @override
  State<_AgentBuilderDialog> createState() => _AgentBuilderDialogState();
}

class _BuilderMessage {
  const _BuilderMessage(this.role, this.text);
  final String role; // 'user' | 'assistant'
  final String text;
}

class _AgentBuilderDialogState extends State<_AgentBuilderDialog> {
  final _input = TextEditingController();
  final _nameController = TextEditingController();
  final _scroll = ScrollController();
  late final List<_BuilderMessage> _messages;
  bool _sending = false;
  String? _error;
  String? _proposedRule;
  List<String> _classes = const [];
  String? _scheduleLabel;

  bool get _isEdit => widget.initialAgent != null;

  @override
  void initState() {
    super.initState();
    final agent = widget.initialAgent;
    if (agent != null) {
      // Seed the edit session: current rule shown as the proposal so the user
      // can save right away, and the chat carries the rule as context.
      _proposedRule = agent.rule;
      _classes =
          (agent.compiledEdgeConfig['classes'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [];
      _scheduleLabel = _scheduleLabelOf(agent.compiledEdgeConfig);
      _nameController.text = agent.name;
      _messages = [
        _BuilderMessage(
          'assistant',
          'You\'re editing "${agent.name}". Its current rule is:\n'
              '"${agent.rule}"\n\nTell me what you\'d like to change.',
        ),
      ];
    } else {
      _messages = [
        const _BuilderMessage(
          'assistant',
          "Hi! Tell me what you'd like this camera to watch for, and I'll turn "
              'it into a detection rule.',
        ),
      ];
    }
  }

  String? _scheduleLabelOf(Map<String, dynamic> config) {
    final schedule = config['schedule'];
    if (schedule is Map && schedule['start'] != null && schedule['end'] != null) {
      return '${schedule['start']}–${schedule['end']}';
    }
    return null;
  }

  @override
  void dispose() {
    _input.dispose();
    _nameController.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() {
      _messages.add(_BuilderMessage('user', text));
      _input.clear();
      _sending = true;
      _error = null;
    });
    _scrollToEnd();
    try {
      final history = _messages
          .map((m) => {'role': m.role, 'content': m.text})
          .toList();
      final reply = await widget.apiClient.agentBuilder(history);
      if (!mounted) return;
      setState(() {
        _messages.add(_BuilderMessage('assistant', reply.reply));
        if (reply.rule != null) {
          _proposedRule = reply.rule;
          _classes = reply.classes;
          _scheduleLabel = reply.scheduleLabel;
          if (_nameController.text.trim().isEmpty && reply.name != null) {
            _nameController.text = reply.name!;
          }
        }
      });
      _scrollToEnd();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _save() {
    final rule = _proposedRule;
    if (rule == null) return;
    final typed = _nameController.text.trim();
    final name = typed.isEmpty ? _deriveName(rule) : typed;
    Navigator.of(context).pop(
      _AgentFormResult(
        name: name,
        // Preserve the agent's location when editing; new agents have none.
        location: widget.initialAgent?.location,
        rule: rule,
      ),
    );
  }

  String _deriveName(String rule) {
    final words = rule.replaceAll(RegExp(r'[^\w\s]'), '').split(RegExp(r'\s+'));
    final picked = words.where((w) => w.isNotEmpty).take(4).join(' ');
    return picked.isEmpty ? 'New rule' : picked;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(AppSpacing.lg),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.auto_awesome, color: AppColors.primary),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      _isEdit ? 'Refine agent' : 'Build an agent',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              Text(
                _isEdit
                    ? 'Tell the AI what to change, then save.'
                    : 'Describe what to watch for — refine it together, then save.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Flexible(
                child: ListView.builder(
                  controller: _scroll,
                  shrinkWrap: true,
                  itemCount: _messages.length + (_sending ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index >= _messages.length) {
                      return const _BuilderBubble(
                        role: 'assistant',
                        child: SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      );
                    }
                    final message = _messages[index];
                    return _BuilderBubble(
                      role: message.role,
                      child: Text(message.text),
                    );
                  },
                ),
              ),
              if (_proposedRule != null) ...[
                const SizedBox(height: AppSpacing.sm),
                _ProposalCard(
                  rule: _proposedRule!,
                  classes: _classes,
                  scheduleLabel: _scheduleLabel,
                  nameController: _nameController,
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                AppBanner(text: _error!),
              ],
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      enabled: !_sending,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: 'e.g. tell me if a car pulls into the driveway',
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    icon: const Icon(Icons.send_rounded),
                  ),
                ],
              ),
              if (_proposedRule != null) ...[
                const SizedBox(height: AppSpacing.sm),
                AppButton(
                  label: _isEdit ? 'Save changes' : 'Create agent',
                  icon: Icons.check_circle_outline,
                  onPressed: _sending ? null : _save,
                  expand: true,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BuilderBubble extends StatelessWidget {
  const _BuilderBubble({required this.role, required this.child});

  final String role;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isUser = role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.62,
        ),
        decoration: BoxDecoration(
          color: isUser ? scheme.primaryContainer : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(isUser ? 14 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 14),
          ),
        ),
        child: DefaultTextStyle.merge(
          style: theme.textTheme.bodyMedium?.copyWith(
            color: isUser ? scheme.onPrimaryContainer : scheme.onSurface,
          ),
          child: child,
        ),
      ),
    );
  }
}

class _ProposalCard extends StatelessWidget {
  const _ProposalCard({
    required this.rule,
    required this.classes,
    required this.scheduleLabel,
    required this.nameController,
  });

  final String rule;
  final List<String> classes;
  final String? scheduleLabel;
  final TextEditingController nameController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'PROPOSED RULE',
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 4),
          Text(rule, style: theme.textTheme.bodyMedium),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final label in classes) _PreviewChip(label: label),
              if (scheduleLabel != null)
                _PreviewChip(label: scheduleLabel!, icon: Icons.schedule),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: nameController,
            decoration: InputDecoration(
              labelText: 'Agent name',
              isDense: true,
              filled: true,
              fillColor: scheme.surface,
              prefixIcon: const Icon(Icons.badge_outlined, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewChip extends StatelessWidget {
  const _PreviewChip({required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: AppRadius.pillAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: scheme.onSecondaryContainer),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSecondaryContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Lets the user pick how to create an agent: the AI chat builder or the
/// classic form. Returns 'ai' or 'classic'.
class _CreateAgentChooser extends StatelessWidget {
  const _CreateAgentChooser({this.isEdit = false});

  final bool isEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              isEdit ? 'Edit agent' : 'Create an agent',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 2),
            Text(
              isEdit ? 'Pick how you\'d like to edit it.' : 'Pick how you\'d like to start.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _ChooserOption(
              icon: Icons.auto_awesome,
              iconColor: AppColors.primary,
              title: isEdit ? 'Refine with AI' : 'Build with AI',
              subtitle: isEdit
                  ? 'Chat with AI to adjust this rule.'
                  : 'Describe what to watch for and refine it in a chat.',
              onTap: () => Navigator.of(context).pop('ai'),
            ),
            const SizedBox(height: AppSpacing.sm),
            _ChooserOption(
              icon: Icons.edit_note_outlined,
              title: 'Classic form',
              subtitle: isEdit
                  ? 'Edit the rule fields yourself.'
                  : 'Write the rule yourself, optionally from a template.',
              onTap: () => Navigator.of(context).pop('classic'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChooserOption extends StatelessWidget {
  const _ChooserOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.iconColor,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: AppRadius.mdAll,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLowest,
            borderRadius: AppRadius.mdAll,
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Row(
            children: [
              Icon(icon, color: iconColor ?? scheme.onSurfaceVariant),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
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
