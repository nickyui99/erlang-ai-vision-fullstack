import 'package:flutter/material.dart';

import '../../design/app_colors.dart';
import '../../design/app_spacing.dart';
import '../../design/app_typography.dart';
import '../../services/backend_auth_client.dart';
import '../../shared/console_widgets.dart';
import 'live_stream_view.dart';

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
  String? _streamUrl;
  String? _error;

  bool _isMoving = false;
  bool _isSnapshotting = false;
  bool _isDeleting = false;
  bool _isLoadingEvents = false;
  int _selectedSecondaryPanel = 0;
  String? _assigningAgentId;

  @override
  void initState() {
    super.initState();
    _device = widget.device;
    _agents = widget.agents;
    _panAngle = widget.device.currentPan;
    _tiltAngle = widget.device.currentTilt;
    _loadEvents();
    _resolveStreamUrl();
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

  int get _armedHere =>
      _definitions.where((agent) => _isAssigned(agent.agentId)).length;

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
      await _resolveStreamUrl();
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
      _toast('Pan to $target deg - ${result.status}');
      await widget.onChanged();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
      _toast(error.toString());
    } finally {
      if (mounted) setState(() => _isMoving = false);
    }
  }

  // Tilt is mechanically limited to 60..140 on the rig (firmware SERVO_TILT_MIN/MAX_DEG;
  // backend rejects out-of-range). Pan spans the full 0..180.
  static const int _tiltMinDeg = 60;
  static const int _tiltMaxDeg = 140;

  Future<void> _sendTilt(int angle) async {
    final target = angle.clamp(_tiltMinDeg, _tiltMaxDeg);
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
      _toast('Tilt to $target deg - ${result.status}');
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
      _toast('Snapshot - ${result.status}');
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
      _toast(error.toString());
    } finally {
      if (mounted) setState(() => _isSnapshotting = false);
    }
  }

  /// Confirms, then unregisters this camera. On success pops back to the
  /// workspace and asks it to refresh, since the device no longer exists.
  Future<void> _confirmAndDelete() async {
    final armedCount = _armedHere;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete camera?'),
        content: Text(
          'This unregisters "${_device.name}" and removes it for good.'
          '${armedCount > 0 ? ' Its $armedCount armed ${armedCount == 1 ? 'agent' : 'agents'} and ' : ' Its '}'
          'recorded events will also be deleted. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _isDeleting = true;
      _error = null;
    });
    try {
      await widget.apiClient.deleteDevice(_device.deviceId);
      await widget.onChanged();
      if (!mounted) return;
      Navigator.of(context).pop();
      _toast('Camera "${_device.name}" deleted');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isDeleting = false;
        _error = error.toString();
      });
      _toast(error.toString());
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

  /// Fetches a short-lived signed MJPEG URL from the backend when the camera is
  /// online, then feeds it to [LiveStreamView]. Cleared when offline.
  Future<void> _resolveStreamUrl() async {
    if (_device.healthStatus != 'online') {
      if (mounted) setState(() => _streamUrl = null);
      return;
    }
    try {
      final result = await widget.apiClient.liveStreamUrl(_device.deviceId);
      if (!mounted) return;
      setState(() => _streamUrl = result.streamUrl);
    } catch (_) {
      // Live view is best-effort; the snapshot fallback still works.
      if (!mounted) return;
      setState(() => _streamUrl = null);
    }
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact = MediaQuery.sizeOf(context).width < AppBreakpoints.compact;
    final primaryControls = _primaryControls(compact: compact);
    final secondaryPanels = _secondaryPanels(compact: compact);

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
            onPressed: _isDeleting ? null : _refreshDevice,
            icon: const Icon(Icons.refresh),
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            enabled: !_isDeleting,
            onSelected: (value) {
              if (value == 'delete') _confirmAndDelete();
            },
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline, color: AppColors.danger),
                    const SizedBox(width: AppSpacing.sm),
                    const Text('Delete camera'),
                  ],
                ),
              ),
            ],
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
              padding: EdgeInsets.fromLTRB(
                compact ? AppSpacing.md : AppSpacing.lg,
                compact ? AppSpacing.sm : AppSpacing.lg,
                compact ? AppSpacing.md : AppSpacing.lg,
                AppSpacing.xxl,
              ),
              children: [
                if (_error != null) ...[
                  AppBanner(text: _error!),
                  const SizedBox(height: AppSpacing.md),
                ],
                if (compact) ...[
                  primaryControls,
                  const SizedBox(height: AppSpacing.md),
                  secondaryPanels,
                ] else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 7, child: primaryControls),
                      const SizedBox(width: AppSpacing.lg),
                      Expanded(flex: 5, child: secondaryPanels),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _primaryControls({required bool compact}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _LiveView(
          device: _device,
          panAngle: _panAngle,
          tiltAngle: _tiltAngle,
          snapshot: _snapshot,
          snapshotAt: _snapshotAt,
          liveStreamUrl: _device.healthStatus == 'online' ? _streamUrl : null,
          isSnapshotting: _isSnapshotting,
          onSnapshot: _takeSnapshot,
        ),
        const SizedBox(height: AppSpacing.sm),
        _CameraActionBar(
          isSnapshotting: _isSnapshotting,
          onSnapshot: _takeSnapshot,
        ),
        const SizedBox(height: AppSpacing.sm),
        _compactPtzSurface(compact: compact),
      ],
    );
  }

  Widget _compactPtzSurface({required bool compact}) {
    final busy = _isMoving;
    final theme = Theme.of(context);
    return AppCard(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? AppSpacing.md : AppSpacing.lg,
        vertical: compact ? AppSpacing.sm : AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DirectionPad(
            busy: busy,
            size: compact ? 172 : 190,
            buttonSize: compact ? 44 : 50,
            iconSize: compact ? 24 : 26,
            canTiltUp: _tiltAngle < _tiltMaxDeg,
            canTiltDown: _tiltAngle > _tiltMinDeg,
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
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text('Moving...', style: theme.textTheme.bodySmall),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _secondaryPanels({required bool compact}) {
    if (!compact) {
      return Column(
        children: [
          _protectionPanel(compact: false),
          const SizedBox(height: AppSpacing.lg),
          _activityPanel(compact: false),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<int>(
          segments: const [
            ButtonSegment<int>(
              value: 0,
              icon: Icon(Icons.shield_outlined),
              label: Text('Protection'),
            ),
            ButtonSegment<int>(
              value: 1,
              icon: Icon(Icons.history_outlined),
              label: Text('Activity'),
            ),
          ],
          selected: {_selectedSecondaryPanel},
          showSelectedIcon: false,
          onSelectionChanged: (selection) {
            setState(() => _selectedSecondaryPanel = selection.first);
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 160),
          child: _selectedSecondaryPanel == 0
              ? _protectionPanel(compact: true, key: const ValueKey('protect'))
              : _activityPanel(compact: true, key: const ValueKey('activity')),
        ),
      ],
    );
  }

  Widget _protectionPanel({required bool compact, Key? key}) {
    final definitions = _definitions;
    return ConsolePanel(
      key: key,
      title: 'Protection',
      subtitle: definitions.isEmpty
          ? 'Create an agent in the Agents tab to arm this camera'
          : '$_armedHere of ${definitions.length} armed on this camera',
      icon: Icons.shield_outlined,
      child: definitions.isEmpty
          ? const _CompactEmptyRow(
              icon: Icons.radar_outlined,
              title: 'No detection rules yet',
              message:
                  'Create a detection rule, then toggle it on here to arm this camera.',
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

  Widget _activityPanel({required bool compact, Key? key}) {
    return ConsolePanel(
      key: key,
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
          ? const _CompactEmptyRow(
              icon: Icons.event_busy_outlined,
              title: 'No activity yet',
              message:
                  'Detections from armed agents on this camera show up here.',
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


class _CameraActionBar extends StatelessWidget {
  const _CameraActionBar({
    required this.isSnapshotting,
    required this.onSnapshot,
  });

  final bool isSnapshotting;
  final VoidCallback onSnapshot;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: _CameraActionChip(
              icon: isSnapshotting
                  ? Icons.hourglass_top_outlined
                  : Icons.camera_alt_outlined,
              label: isSnapshotting ? 'Capturing' : 'Snapshot',
              onTap: isSnapshotting ? null : onSnapshot,
              active: true,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          const Expanded(
            child: _CameraActionChip(
              icon: Icons.videocam_outlined,
              label: 'Record',
              disabledReason: 'Recording is not connected yet',
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          const Expanded(
            child: _CameraActionChip(
              icon: Icons.volume_off_outlined,
              label: 'Mute',
              disabledReason: 'Audio streaming is not connected yet',
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          const Expanded(
            child: _CameraActionChip(
              icon: Icons.hd_outlined,
              label: 'Auto',
              disabledReason: 'Resolution switching is not connected yet',
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          const Expanded(
            child: _CameraActionChip(
              icon: Icons.fullscreen_outlined,
              label: 'Full',
              disabledReason: 'Fullscreen live video is not connected yet',
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraActionChip extends StatelessWidget {
  const _CameraActionChip({
    required this.icon,
    required this.label,
    this.onTap,
    this.disabledReason,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final String? disabledReason;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final enabled = onTap != null;
    final fg = enabled
        ? (active ? scheme.onPrimary : scheme.onSurface)
        : scheme.onSurfaceVariant;
    final bg = enabled
        ? (active ? scheme.primary : scheme.surfaceContainerLow)
        : scheme.surfaceContainerHighest;

    return Tooltip(
      message: enabled ? label : (disabledReason ?? '$label unavailable'),
      child: InkWell(
        borderRadius: AppRadius.mdAll,
        onTap: onTap,
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: AppRadius.mdAll,
            border: Border.all(
              color: enabled && active ? scheme.primary : scheme.outlineVariant,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: fg),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: fg,
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
    required this.liveStreamUrl,
    required this.isSnapshotting,
    required this.onSnapshot,
  });

  final EdgeDevice device;
  final int panAngle;
  final int tiltAngle;
  final DeviceCommandResult? snapshot;
  final DateTime? snapshotAt;
  final String? liveStreamUrl;
  final bool isSnapshotting;
  final VoidCallback onSnapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final online = device.healthStatus == 'online';
    final snapshotPath = snapshot?.payload['snapshot_path']?.toString();
    final streamUrl = liveStreamUrl;
    final fps = device.fps != null
        ? '${device.fps!.toStringAsFixed(device.fps! % 1 == 0 ? 0 : 1)} fps'
        : 'fps --';
    final signal = device.rssi != null
        ? '${device.rssi!.toStringAsFixed(0)} dBm'
        : 'signal --';
    final streamLabel = 'MJPEG \u00B7 $fps \u00B7 $signal';

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
            if (streamUrl != null)
              LiveStreamView(url: streamUrl),
            if (streamUrl == null)
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
                        ? 'Live view unavailable - capture a snapshot'
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
            Positioned(
              bottom: AppSpacing.md,
              left: AppSpacing.md,
              right: 148,
              child: Align(
                alignment: Alignment.centerLeft,
                child: _GlassChip(
                  icon: Icons.sensors_outlined,
                  label: streamLabel,
                ),
              ),
            ),
            // Top-left: pan indicator.
            Positioned(
              top: AppSpacing.sm,
              left: AppSpacing.md,
              child: _GlassChip(
                icon: Icons.control_camera_outlined,
                label: 'P $panAngle\u00B0 \u00B7 T $tiltAngle\u00B0',
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
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
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

/// Compact PTZ pad. Horizontal buttons drive pan, vertical buttons drive tilt,
/// and the center button recenters both to 90 degrees.
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
    this.size = 190,
    this.buttonSize = 50,
    this.iconSize = 26,
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
  final double size;
  final double buttonSize;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: scheme.surfaceContainerLow,
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              top: AppSpacing.sm,
              child: _PadButton(
                icon: Icons.keyboard_arrow_up,
                tooltip: 'Tilt up',
                onPressed: busy || !canTiltUp ? null : onTiltUp,
                buttonSize: buttonSize,
                iconSize: iconSize,
              ),
            ),
            Positioned(
              left: AppSpacing.sm,
              child: _PadButton(
                icon: Icons.keyboard_arrow_left,
                tooltip: 'Pan left',
                onPressed: busy || !canPanLeft ? null : onPanLeft,
                buttonSize: buttonSize,
                iconSize: iconSize,
              ),
            ),
            _PadButton(
              icon: Icons.center_focus_strong_outlined,
              tooltip: 'Center camera',
              onPressed: busy ? null : onCenter,
              filled: true,
              buttonSize: buttonSize,
              iconSize: iconSize,
            ),
            Positioned(
              right: AppSpacing.sm,
              child: _PadButton(
                icon: Icons.keyboard_arrow_right,
                tooltip: 'Pan right',
                onPressed: busy || !canPanRight ? null : onPanRight,
                buttonSize: buttonSize,
                iconSize: iconSize,
              ),
            ),
            Positioned(
              bottom: AppSpacing.sm,
              child: _PadButton(
                icon: Icons.keyboard_arrow_down,
                tooltip: 'Tilt down',
                onPressed: busy || !canTiltDown ? null : onTiltDown,
                buttonSize: buttonSize,
                iconSize: iconSize,
              ),
            ),
          ],
        ),
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
    this.buttonSize = 50,
    this.iconSize = 26,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool filled;
  final double buttonSize;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final button = filled
        ? IconButton.filled(
            tooltip: tooltip,
            onPressed: onPressed,
            iconSize: iconSize,
            icon: Icon(icon),
          )
        : IconButton.filledTonal(
            tooltip: tooltip,
            onPressed: onPressed,
            iconSize: iconSize,
            icon: Icon(icon),
          );
    return Padding(
      padding: const EdgeInsets.all(2),
      child: SizedBox(width: buttonSize, height: buttonSize, child: button),
    );
  }
}

class _CompactEmptyRow extends StatelessWidget {
  const _CompactEmptyRow({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          IconChip(icon: icon, size: 34),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  message,
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
        ? '${agent.rule} - also on $elsewhere other ${elsewhere == 1 ? 'camera' : 'cameras'}'
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
