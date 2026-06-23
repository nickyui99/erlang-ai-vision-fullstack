import 'package:flutter/material.dart';

import '../../design/app_colors.dart';
import '../../design/app_spacing.dart';
import '../../design/app_typography.dart';
import '../../services/backend_auth_client.dart';
import '../../shared/console_widgets.dart';

/// Tapo-style device control screen: live view, pan & tilt, protection
/// (armed agents) and recent activity for a single camera. Pushed full-screen
/// when a device card is tapped in the Devices tab.
class DeviceControlView extends StatefulWidget {
  const DeviceControlView({
    required this.device,
    required this.apiClient,
    required this.agents,
    required this.onChanged,
    super.key,
  });

  final EdgeDevice device;
  final SentinelEdgeApiClient apiClient;

  /// All agent definitions (used to assign/unassign protection to this device).
  final List<SurveillanceAgent> agents;

  /// Notifies the parent workspace to refresh devices + agents after a change.
  final Future<void> Function() onChanged;

  @override
  State<DeviceControlView> createState() => _DeviceControlViewState();
}

class _DeviceControlViewState extends State<DeviceControlView> {
  static const int _panStep = 15;

  late EdgeDevice _device;
  late List<SurveillanceAgent> _agents;
  late int _panAngle;
  late int _tiltAngle;

  List<SecurityEvent> _events = const [];
  DeviceCommandResult? _snapshot;
  DateTime? _snapshotAt;
  String? _error;

  bool _isMoving = false;
  bool _isSnapshotting = false;
  bool _isLoadingEvents = false;
  String? _assigningAgentId;

  @override
  void initState() {
    super.initState();
    _device = widget.device;
    _agents = widget.agents;
    _panAngle = widget.device.currentPan;
    _tiltAngle = widget.device.currentTilt;
    _loadEvents();
  }

  List<SurveillanceAgent> get _definitions =>
      _agents.where((agent) => agent.isDefinition).toList();

  Iterable<SurveillanceAgent> _subsForDefinition(String definitionId) =>
      _agents.where((agent) => agent.parentAgentId == definitionId);

  bool _isAssigned(String definitionId) => _subsForDefinition(
    definitionId,
  ).any((agent) => agent.deviceId == _device.deviceId);

  int _assignmentCount(String definitionId) =>
      _subsForDefinition(definitionId).length;

  int get _armedHere => _definitions
      .where((agent) => _isAssigned(agent.agentId))
      .length;

  Future<void> _refreshAgents() async {
    try {
      final agents = await widget.apiClient.listAgents();
      if (!mounted) return;
      setState(() => _agents = agents);
    } catch (_) {
      // Surfaced elsewhere; keep the last known agents on a transient failure.
    }
  }

  Future<void> _loadEvents() async {
    setState(() => _isLoadingEvents = true);
    try {
      final events = await widget.apiClient.listEvents();
      if (!mounted) return;
      setState(() {
        _events = events
            .where((event) => event.deviceId == _device.deviceId)
            .toList();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _isLoadingEvents = false);
    }
  }

  Future<void> _refreshDevice() async {
    try {
      final device = await widget.apiClient.getDevice(_device.deviceId);
      if (!mounted) return;
      setState(() {
        _device = device;
        _panAngle = device.currentPan;
        _tiltAngle = device.currentTilt;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    }
    await _loadEvents();
  }

  Future<void> _sendPan(int angle) async {
    final target = angle.clamp(0, 180);
    setState(() {
      _isMoving = true;
      _error = null;
      _panAngle = target;
    });
    try {
      final result = await widget.apiClient.panDevice(_device.deviceId, target);
      if (!mounted) return;
      _toast('Pan to $target° — ${result.status}');
      await widget.onChanged();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
      _toast(error.toString());
    } finally {
      if (mounted) setState(() => _isMoving = false);
    }
  }

  Future<void> _sendTilt(int angle) async {
    final target = angle.clamp(0, 180);
    setState(() {
      _isMoving = true;
      _error = null;
      _tiltAngle = target;
    });
    try {
      final result = await widget.apiClient.tiltDevice(
        _device.deviceId,
        target,
      );
      if (!mounted) return;
      _toast('Tilt to $target° — ${result.status}');
      await widget.onChanged();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
      _toast(error.toString());
    } finally {
      if (mounted) setState(() => _isMoving = false);
    }
  }

  Future<void> _center() async {
    await _sendPan(90);
    if (mounted) await _sendTilt(90);
  }

  Future<void> _takeSnapshot() async {
    setState(() {
      _isSnapshotting = true;
      _error = null;
    });
    try {
      final result = await widget.apiClient.snapshotDevice(_device.deviceId);
      if (!mounted) return;
      setState(() {
        _snapshot = result;
        _snapshotAt = DateTime.now();
      });
      _toast('Snapshot — ${result.status}');
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
      _toast(error.toString());
    } finally {
      if (mounted) setState(() => _isSnapshotting = false);
    }
  }

  Future<void> _toggleAssignment(SurveillanceAgent agent, bool assign) async {
    setState(() {
      _assigningAgentId = agent.agentId;
      _error = null;
    });
    try {
      if (assign) {
        await widget.apiClient.assignAgent(
          agent.agentId,
          deviceId: _device.deviceId,
        );
      } else {
        await widget.apiClient.unassignAgent(
          agent.agentId,
          deviceId: _device.deviceId,
        );
      }
      await _refreshAgents();
      await widget.onChanged();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
      _toast(error.toString());
    } finally {
      if (mounted) setState(() => _assigningAgentId = null);
    }
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact = MediaQuery.sizeOf(context).width < AppBreakpoints.compact;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_device.name, style: theme.textTheme.titleMedium),
            Text(
              _device.location ?? 'No location',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: Center(child: StatusPill.fromStatus(_device.healthStatus)),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refreshDevice,
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppBreakpoints.contentMaxWidth,
            ),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.xxl,
              ),
              children: [
                if (_error != null) ...[
                  AppBanner(text: _error!),
                  const SizedBox(height: AppSpacing.lg),
                ],
                _LiveView(
                  device: _device,
                  panAngle: _panAngle,
                  tiltAngle: _tiltAngle,
                  snapshot: _snapshot,
                  snapshotAt: _snapshotAt,
                  isSnapshotting: _isSnapshotting,
                  onSnapshot: _takeSnapshot,
                ),
                const SizedBox(height: AppSpacing.lg),
                _telemetry(compact),
                const SizedBox(height: AppSpacing.lg),
                _panTiltPanel(),
                const SizedBox(height: AppSpacing.lg),
                _protectionPanel(),
                const SizedBox(height: AppSpacing.lg),
                _activityPanel(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _telemetry(bool compact) {
    final tiles = [
      _StatTile(
        icon: Icons.swap_horiz_outlined,
        label: 'Pan',
        value: '$_panAngle°',
      ),
      _StatTile(
        icon: Icons.swap_vert_outlined,
        label: 'Tilt',
        value: '$_tiltAngle°',
      ),
      _StatTile(
        icon: Icons.speed_outlined,
        label: 'Frame rate',
        value: _device.fps != null
            ? '${_device.fps!.toStringAsFixed(1)} fps'
            : '—',
      ),
      _StatTile(
        icon: Icons.wifi_outlined,
        label: 'Signal',
        value: _device.rssi != null
            ? '${_device.rssi!.toStringAsFixed(0)} dBm'
            : '—',
      ),
    ];
    return GridView.count(
      crossAxisCount: compact ? 2 : 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: AppSpacing.md,
      mainAxisSpacing: AppSpacing.md,
      childAspectRatio: compact ? 2.2 : 1.7,
      children: tiles,
    );
  }

  Widget _panTiltPanel() {
    final busy = _isMoving;
    final theme = Theme.of(context);
    return ConsolePanel(
      title: 'Pan & Tilt',
      subtitle: 'Two-axis SG90 gimbal · pan and tilt, 0–180°',
      icon: Icons.control_camera_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.center,
            spacing: AppSpacing.sm,
            children: [
              StatusPill(
                label: 'Pan $_panAngle°',
                tone: StatusTone.info,
                dot: false,
              ),
              StatusPill(
                label: 'Tilt $_tiltAngle°',
                tone: StatusTone.info,
                dot: false,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          // D-pad: ◀ ▶ drive the pan servo, ▲ ▼ the tilt servo.
          _DirectionPad(
            busy: busy,
            canTiltUp: _tiltAngle < 180,
            canTiltDown: _tiltAngle > 0,
            canPanLeft: _panAngle > 0,
            canPanRight: _panAngle < 180,
            onTiltUp: () => _sendTilt(_tiltAngle + _panStep),
            onTiltDown: () => _sendTilt(_tiltAngle - _panStep),
            onPanLeft: () => _sendPan(_panAngle - _panStep),
            onPanRight: () => _sendPan(_panAngle + _panStep),
            onCenter: _center,
          ),
          if (busy)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.md),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text('Moving…', style: theme.textTheme.bodySmall),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _protectionPanel() {
    final definitions = _definitions;
    return ConsolePanel(
      title: 'Protection',
      subtitle: definitions.isEmpty
          ? 'Create an agent in the Agents tab to arm this camera'
          : '$_armedHere of ${definitions.length} armed on this camera',
      icon: Icons.shield_outlined,
      child: definitions.isEmpty
          ? const EmptyState(
              icon: Icons.radar_outlined,
              title: 'No agents yet',
              message:
                  'Create an agent, then toggle it on here to arm this camera.',
              compact: true,
            )
          : Column(
              children: definitions.map((agent) {
                return _AgentToggleTile(
                  agent: agent,
                  assigned: _isAssigned(agent.agentId),
                  assignmentCount: _assignmentCount(agent.agentId),
                  busy: _assigningAgentId == agent.agentId,
                  enabled: _assigningAgentId == null,
                  onChanged: (assign) => _toggleAssignment(agent, assign),
                );
              }).toList(),
            ),
    );
  }

  Widget _activityPanel() {
    return ConsolePanel(
      title: 'Recent activity',
      subtitle: '${_events.length} detections on this camera',
      icon: Icons.history_outlined,
      action: IconButton.filledTonal(
        onPressed: _isLoadingEvents ? null : _loadEvents,
        tooltip: 'Refresh activity',
        icon: _isLoadingEvents
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.refresh),
      ),
      child: _isLoadingEvents && _events.isEmpty
          ? const SkeletonList(rows: 3)
          : _events.isEmpty
          ? const EmptyState(
              icon: Icons.event_busy_outlined,
              title: 'No activity yet',
              message:
                  'Detections from armed agents on this camera show up here.',
              compact: true,
            )
          : Column(
              children: _events
                  .take(6)
                  .map(
                    (event) => SelectableConsoleTile(
                      selected: false,
                      title: event.summary?.isNotEmpty == true
                          ? event.summary!
                          : event.eventType,
                      subtitle: _formatTimestamp(event.timestamp),
                      leading: IconChip(
                        icon: Icons.warning_amber_outlined,
                        size: 34,
                        color: StatusToneColor.fromStatus(event.severity).base,
                      ),
                      trailing: StatusPill.fromStatus(event.severity),
                      onTap: () {},
                    ),
                  )
                  .toList(),
            ),
    );
  }
}

String _formatTimestamp(DateTime? value) {
  if (value == null) return 'unknown time';
  return value.toLocal().toString().split('.').first;
}

// ---------------------------------------------------------------------------
// Live view
// ---------------------------------------------------------------------------

class _LiveView extends StatelessWidget {
  const _LiveView({
    required this.device,
    required this.panAngle,
    required this.tiltAngle,
    required this.snapshot,
    required this.snapshotAt,
    required this.isSnapshotting,
    required this.onSnapshot,
  });

  final EdgeDevice device;
  final int panAngle;
  final int tiltAngle;
  final DeviceCommandResult? snapshot;
  final DateTime? snapshotAt;
  final bool isSnapshotting;
  final VoidCallback onSnapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final online = device.healthStatus == 'online';
    final snapshotPath = snapshot?.payload['snapshot_path']?.toString();

    return ClipRRect(
      borderRadius: AppRadius.lgAll,
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF11201C), Color(0xFF0A1412)],
                ),
              ),
            ),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    snapshotPath != null
                        ? Icons.photo_camera_back_outlined
                        : Icons.videocam_outlined,
                    color: Colors.white.withValues(alpha: 0.55),
                    size: 48,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    snapshotPath != null
                        ? 'Latest snapshot'
                        : online
                        ? 'Live view unavailable — capture a snapshot'
                        : 'Camera offline',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                  if (snapshotPath != null) ...[
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xl,
                      ),
                      child: Text(
                        snapshotPath,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.mono(
                          color: Colors.white.withValues(alpha: 0.85),
                        ).copyWith(fontSize: 11),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Top-left: pan indicator.
            Positioned(
              top: AppSpacing.md,
              left: AppSpacing.md,
              child: _GlassChip(
                icon: Icons.control_camera_outlined,
                label: 'P $panAngle° · T $tiltAngle°',
              ),
            ),
            // Top-right: capture time.
            if (snapshotAt != null)
              Positioned(
                top: AppSpacing.md,
                right: AppSpacing.md,
                child: _GlassChip(
                  icon: Icons.schedule_outlined,
                  label: _formatTimestamp(snapshotAt),
                ),
              ),
            // Bottom-right: snapshot action.
            Positioned(
              bottom: AppSpacing.md,
              right: AppSpacing.md,
              child: FilledButton.icon(
                onPressed: isSnapshotting ? null : onSnapshot,
                icon: isSnapshotting
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.camera_alt_outlined, size: 18),
                label: Text(isSnapshotting ? 'Capturing' : 'Snapshot'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlassChip extends StatelessWidget {
  const _GlassChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: AppRadius.pillAll,
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white.withValues(alpha: 0.85)),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Controls
// ---------------------------------------------------------------------------

/// Cross-shaped pad: ◀ ▶ drive the pan servo, ▲ ▼ the tilt servo, center
/// recenters both to 90°.
class _DirectionPad extends StatelessWidget {
  const _DirectionPad({
    required this.busy,
    required this.canTiltUp,
    required this.canTiltDown,
    required this.canPanLeft,
    required this.canPanRight,
    required this.onTiltUp,
    required this.onTiltDown,
    required this.onPanLeft,
    required this.onPanRight,
    required this.onCenter,
  });

  final bool busy;
  final bool canTiltUp;
  final bool canTiltDown;
  final bool canPanLeft;
  final bool canPanRight;
  final VoidCallback onTiltUp;
  final VoidCallback onTiltDown;
  final VoidCallback onPanLeft;
  final VoidCallback onPanRight;
  final VoidCallback onCenter;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PadButton(
            icon: Icons.keyboard_arrow_up,
            tooltip: 'Tilt up',
            onPressed: busy || !canTiltUp ? null : onTiltUp,
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _PadButton(
                icon: Icons.keyboard_arrow_left,
                tooltip: 'Pan left',
                onPressed: busy || !canPanLeft ? null : onPanLeft,
              ),
              const SizedBox(width: AppSpacing.sm),
              _PadButton(
                icon: Icons.center_focus_strong_outlined,
                tooltip: 'Center (90° / 90°)',
                onPressed: busy ? null : onCenter,
                filled: true,
              ),
              const SizedBox(width: AppSpacing.sm),
              _PadButton(
                icon: Icons.keyboard_arrow_right,
                tooltip: 'Pan right',
                onPressed: busy || !canPanRight ? null : onPanRight,
              ),
            ],
          ),
          _PadButton(
            icon: Icons.keyboard_arrow_down,
            tooltip: 'Tilt down',
            onPressed: busy || !canTiltDown ? null : onTiltDown,
          ),
        ],
      ),
    );
  }
}

class _PadButton extends StatelessWidget {
  const _PadButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.filled = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final button = filled
        ? IconButton.filled(
            tooltip: tooltip,
            onPressed: onPressed,
            iconSize: 28,
            icon: Icon(icon),
          )
        : IconButton.filledTonal(
            tooltip: tooltip,
            onPressed: onPressed,
            iconSize: 28,
            icon: Icon(icon),
          );
    return Padding(
      padding: const EdgeInsets.all(2),
      child: SizedBox(width: 56, height: 56, child: button),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = scheme.primary;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, size: 20, color: color),
          const Spacer(),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.tabular(
              theme.textTheme.titleLarge ?? const TextStyle(),
            ),
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

class _AgentToggleTile extends StatelessWidget {
  const _AgentToggleTile({
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
