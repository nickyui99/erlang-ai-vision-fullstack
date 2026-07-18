import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design/app_colors.dart';
import '../../design/app_spacing.dart';
import '../../design/app_typography.dart';
import '../../services/backend_auth_client.dart';
import '../../services/playback/playback_url_launcher.dart';
import '../../services/realtime/realtime_client.dart';
import '../../shared/console_widgets.dart';
import '../../shared/event_alert.dart';
import 'live_stream_view.dart';
import 'playback/playback_video_view.dart';

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
  final ErlangVisionApiClient apiClient;

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
  List<MediaClip> _playbackClips = const [];
  List<MediaRecording> _recordings = const [];
  DeviceCommandResult? _snapshot;
  DateTime? _snapshotAt;
  String? _streamUrl;
  String? _error;
  String? _playbackError;

  bool _isMoving = false;
  bool _isSnapshotting = false;
  bool _isRecording = false;
  bool _isMuted = false;
  String _resolution = 'Auto';
  String? _cameraControlBusy;
  bool _isDeleting = false;
  bool _isLoadingEvents = false;
  bool _isLoadingPlayback = false;
  bool _isSettingMode = false;
  int _selectedSecondaryPanel = 0;
  String? _assigningAgentId;
  String? _playingClipId;
  String? _playingRecordingId;
  RealtimeConnection? _realtime;

  @override
  void initState() {
    super.initState();
    _device = widget.device;
    _agents = widget.agents;
    _panAngle = widget.device.currentPan;
    _tiltAngle = widget.device.currentTilt;
    _loadEvents();
    _loadPlaybackClips();
    _resolveStreamUrl();
    // Live updates while a camera is open: new detections refresh the activity
    // panel and raise an in-app alert (web SSE; no-op on mobile).
    _realtime = connectRealtime(
      onMessage: _handleRealtimeMessage,
      onStatus: (_) {},
    );
  }

  void _handleRealtimeMessage(RealtimeMessage message) {
    if (!mounted) return;
    final deviceId = message.data['device_id']?.toString();
    if (deviceId != _device.deviceId) return; // only this camera
    switch (message.type) {
      case 'event.created':
        _loadEvents();
        if (ModalRoute.of(context)?.isCurrent ?? true) {
          final severity = message.data['severity']?.toString();
          showEventAlert(
            ScaffoldMessenger.maybeOf(context),
            title: 'New ${(severity ?? 'event').toLowerCase()} detection',
            body: message.data['summary']?.toString() ??
                'A camera event needs review.',
            tone: toneForSeverity(severity),
            dedupeKey: message.data['event_id']?.toString(),
          );
        }
        break;
      case 'event.verified':
        _loadEvents();
        if ((message.data['verified'] == true ||
                message.data['verified']?.toString() == 'true') &&
            (ModalRoute.of(context)?.isCurrent ?? true)) {
          final severity = message.data['severity']?.toString();
          final eventId = message.data['event_id']?.toString();
          showEventAlert(
            ScaffoldMessenger.maybeOf(context),
            title: 'Verified ${(severity ?? 'event').toLowerCase()} alert',
            body:
                message.data['summary']?.toString() ??
                'Qwen verified a camera event that needs review.',
            tone: toneForSeverity(severity),
            dedupeKey: eventId == null ? null : 'verified:$eventId',
          );
        }
        break;
      case 'clip.available':
        _loadPlaybackClips();
        break;
    }
  }

  @override
  void dispose() {
    _realtime?.dispose();
    super.dispose();
  }

  List<SurveillanceAgent> get _definitions =>
      _agents.where((agent) => agent.isDefinition).toList();

  // Unassigning disarms the sub-agent but keeps its row (so event history survives),
  // so "assigned" means an ARMED sub-agent -- a disarmed leftover must read as off.
  Iterable<SurveillanceAgent> _subsForDefinition(String definitionId) => _agents.where(
    (agent) => agent.parentAgentId == definitionId && agent.state == 'armed',
  );

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
        _error = null; // clear any stale banner from a prior failed load
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

  Future<void> _loadPlaybackClips() async {
    setState(() {
      _isLoadingPlayback = true;
      _playbackError = null;
    });
    try {
      final clips = await widget.apiClient.listDeviceClips(
        _device.deviceId,
        limit: 8,
        clipType: 'event',
      );
      if (!mounted) return;
      final recordings = await widget.apiClient.listDeviceRecordings(
        _device.deviceId,
        limit: 6,
      );
      if (!mounted) return;
      setState(() {
        _playbackClips = clips;
        _recordings = recordings;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _playbackError = error.toString());
    } finally {
      if (mounted) setState(() => _isLoadingPlayback = false);
    }
  }

  Future<void> _playClip(MediaClip clip) async {
    setState(() {
      _playingClipId = clip.clipId;
      _playbackError = null;
    });
    try {
      final playback = await widget.apiClient.signedClipPlaybackUrl(
        clip.clipId,
      );
      if (!mounted) return;
      await _showPlaybackSheet(clip, playback);
    } catch (error) {
      if (!mounted) return;
      setState(() => _playbackError = error.toString());
      _toast(error.toString());
    } finally {
      if (mounted) setState(() => _playingClipId = null);
    }
  }

  Future<void> _playRecording(MediaRecording recording) async {
    setState(() {
      _playingRecordingId = recording.recordingId;
      _playbackError = null;
    });
    try {
      final playback = await widget.apiClient.signedRecordingPlaybackUrl(
        recording.recordingId,
      );
      if (!mounted) return;
      await _showRecordingPlaybackSheet(recording, playback);
    } catch (error) {
      if (!mounted) return;
      setState(() => _playbackError = error.toString());
      _toast(error.toString());
    } finally {
      if (mounted) setState(() => _playingRecordingId = null);
    }
  }

  Future<void> _showRecordingPlaybackSheet(
    MediaRecording recording,
    RecordingPlaybackUrl playback,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: 0.92,
        child: _RecordingPlaybackSheet(
          recording: recording,
          playback: playback,
          onOpen: () => _openPlaybackUrl(playback.playbackUrl),
        ),
      ),
    );
  }
  Future<void> _showPlaybackSheet(
    MediaClip clip,
    ClipPlaybackUrl playback,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: 0.92,
        child: _PlaybackSheet(
          clip: clip,
          playback: playback,
          onOpen: () => _openPlaybackUrl(playback.playbackUrl),
          onDownload: () => _downloadClip(clip),
        ),
      ),
    );
  }

  Future<void> _openPlaybackUrl(String url, {bool download = false}) async {
    final opened = await openPlaybackUrl(url, download: download);
    if (!opened) {
      await Clipboard.setData(ClipboardData(text: url));
      if (!mounted) return;
      _toast('Playback link copied');
    }
  }

  Future<void> _downloadClip(MediaClip clip) async {
    try {
      final download = await widget.apiClient.signedClipDownloadUrl(
        clip.clipId,
      );
      final opened = await openPlaybackUrl(download.downloadUrl, download: true);
      if (!opened) {
        await Clipboard.setData(ClipboardData(text: download.downloadUrl));
        if (!mounted) return;
        _toast('Download link copied');
        return;
      }
      if (!mounted) return;
      _toast('Download started');
    } catch (error) {
      if (!mounted) return;
      _toast(error.toString());
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
    await _loadPlaybackClips();
  }


  Future<void> _saveDevicePreferences({
    bool? isFavorite,
    List<CameraPreset>? presets,
    int? ptzCorrectionPan,
    int? ptzCorrectionTilt,
  }) async {
    final nextFavorite = isFavorite ?? _device.isFavorite;
    final nextPresets = presets ?? _device.presets;
    final nextPanCorrection = ptzCorrectionPan ?? _device.ptzCorrectionPan;
    final nextTiltCorrection = ptzCorrectionTilt ?? _device.ptzCorrectionTilt;
    try {
      final updated = await widget.apiClient.updateDevice(
        deviceId: _device.deviceId,
        name: _device.name,
        location: _device.location,
        isFavorite: nextFavorite,
        presets: nextPresets,
        ptzCorrectionPan: nextPanCorrection,
        ptzCorrectionTilt: nextTiltCorrection,
      );
      if (!mounted) return;
      setState(() => _device = updated);
      await widget.onChanged();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
      _toast(error.toString());
    }
  }

  Future<void> _toggleFavorite() async {
    await _saveDevicePreferences(isFavorite: !_device.isFavorite);
    if (!mounted) return;
    _toast(_device.isFavorite ? 'Camera favorited' : 'Favorite removed');
  }

  Future<void> _sendPan(int angle) async {
    final target = angle.clamp(_panMinDeg, _panMaxDeg);
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

  // Servo travel is limited to a safe range on the rig so the servos never
  // stall against their mechanical hard stops (firmware SERVO_PAN/TILT_MIN/MAX_DEG;
  // backend rejects out-of-range). Pan: 15..165, tilt: 60..140.
  static const int _panMinDeg = 15;
  static const int _panMaxDeg = 165;
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


  Future<void> _sendCameraControl({
    required String busyKey,
    required String action,
    bool? enabled,
    String? resolution,
    required VoidCallback applyLocalState,
    required String successLabel,
  }) async {
    setState(() {
      _cameraControlBusy = busyKey;
      _error = null;
    });
    try {
      final result = await widget.apiClient.controlDevice(
        _device.deviceId,
        action: action,
        enabled: enabled,
        resolution: resolution,
      );
      if (!mounted) return;
      setState(applyLocalState);
      _toast('$successLabel - ${result.status}');
      await widget.onChanged();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
      _toast(error.toString());
    } finally {
      if (mounted) setState(() => _cameraControlBusy = null);
    }
  }

  Future<void> _toggleRecording() async {
    final next = !_isRecording;
    await _sendCameraControl(
      busyKey: 'recording',
      action: 'recording',
      enabled: next,
      applyLocalState: () => _isRecording = next,
      successLabel: next ? 'Recording started' : 'Recording stopped',
    );
  }

  Future<void> _toggleMute() async {
    final next = !_isMuted;
    await _sendCameraControl(
      busyKey: 'audio_mute',
      action: 'audio_mute',
      enabled: next,
      applyLocalState: () => _isMuted = next,
      successLabel: next ? 'Audio muted' : 'Audio unmuted',
    );
  }

  Future<void> _cycleResolution() async {
    const values = ['Auto', '720p', '1080p'];
    final next = values[(values.indexOf(_resolution) + 1) % values.length];
    await _sendCameraControl(
      busyKey: 'resolution',
      action: 'resolution',
      resolution: next.toLowerCase(),
      applyLocalState: () => _resolution = next,
      successLabel: 'Resolution $next',
    );
  }

  Future<void> _openFullscreenLiveView() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog.fullscreen(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _device.name,
                        style: Theme.of(context).textTheme.titleMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close fullscreen',
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: _LiveView(
                    device: _device,
                    panAngle: _panAngle,
                    tiltAngle: _tiltAngle,
                    snapshot: _snapshot,
                    snapshotAt: _snapshotAt,
                    liveStreamUrl: _device.healthStatus == 'online'
                        ? _streamUrl
                        : null,
                    isSnapshotting: _isSnapshotting,
                    onSnapshot: _takeSnapshot,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
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
            tooltip: _device.isFavorite ? 'Remove favorite' : 'Favorite camera',
            onPressed: _isDeleting ? null : _toggleFavorite,
            icon: Icon(
              _device.isFavorite ? Icons.favorite : Icons.favorite_border,
              color: _device.isFavorite ? AppColors.danger : null,
            ),
          ),
          // Mobile refreshes by pulling down the page instead of a button.
          if (!compact)
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
            child: RefreshIndicator(
              // On mobile this is the sole refresh affordance; _refreshDevice
              // reloads the device, stream, events and clips. Harmless on web
              // (still has the app-bar button + wheel).
              onRefresh: _refreshDevice,
              notificationPredicate: (_) => compact,
              child: ListView(
                physics: compact
                    ? const AlwaysScrollableScrollPhysics()
                    : null,
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
          isRecording: _isRecording,
          isMuted: _isMuted,
          resolution: _resolution,
          busyKey: _cameraControlBusy,
          onRecord: _toggleRecording,
          onMute: _toggleMute,
          onResolution: _cycleResolution,
          onFullscreen: _openFullscreenLiveView,
        ),
        const SizedBox(height: AppSpacing.sm),
        _compactPtzSurface(compact: compact),
        const SizedBox(height: AppSpacing.sm),
        _controlModeCard(compact: compact),
        const SizedBox(height: AppSpacing.sm),
        _PlaybackDownloadPanel(
          clips: _playbackClips,
          recordings: _recordings,
          events: _events,
          isLoading: _isLoadingPlayback,
          error: _playbackError,
          playingClipId: _playingClipId,
          playingRecordingId: _playingRecordingId,
          onRefresh: _loadPlaybackClips,
          onPlayClip: _playClip,
          onPlayRecording: _playRecording,
          showRefresh: !compact,
        ),
      ],
    );
  }

  // Per-camera autonomous control mode: off / auto_track / agent. Mutually exclusive --
  // exactly one controller (none / the deterministic tracker / the LLM agent) owns the servo.
  static const List<String> _controlModes = ['off', 'auto_track', 'agent'];

  Future<void> _setControlMode(String mode) async {
    if (_isSettingMode || mode == _device.controlMode) return;
    setState(() {
      _isSettingMode = true;
      _error = null;
    });
    try {
      final updated = await widget.apiClient.setControlMode(
        _device.deviceId,
        mode,
      );
      if (!mounted) return;
      setState(() => _device = updated);
      const labels = {
        'off': 'Auto control off',
        'auto_track': 'Auto-tracking on',
        'agent': 'Agent control on',
      };
      _toast(labels[mode] ?? 'Control mode: $mode');
      await widget.onChanged();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
      _toast(error.toString());
    } finally {
      if (mounted) setState(() => _isSettingMode = false);
    }
  }

  Widget _controlModeCard({required bool compact}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Normalize any unexpected server value so the SegmentedButton selection is always valid.
    final mode = _controlModes.contains(_device.controlMode)
        ? _device.controlMode
        : 'off';
    final subtitle = switch (mode) {
      'auto_track' => 'The camera automatically follows a detected person.',
      'agent' => _armedHere > 0
          ? 'The armed agent decides how the camera pans and tilts.'
          : 'Arm an agent under Protection so it can drive the camera.',
      _ => 'Manual control only - the camera stays put until you move it.',
    };
    return AppCard(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? AppSpacing.md : AppSpacing.lg,
        vertical: compact ? AppSpacing.sm : AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.control_camera_outlined,
                  size: 20, color: scheme.onSurfaceVariant),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text('Camera control',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ),
              if (_isSettingMode)
                const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment<String>(
                value: 'off',
                icon: Icon(Icons.block_outlined),
                label: Text('Off'),
              ),
              ButtonSegment<String>(
                value: 'auto_track',
                icon: Icon(Icons.center_focus_strong_outlined),
                label: Text('Auto-track'),
              ),
              ButtonSegment<String>(
                value: 'agent',
                icon: Icon(Icons.smart_toy_outlined),
                label: Text('Agent'),
              ),
            ],
            selected: {mode},
            showSelectedIcon: false,
            onSelectionChanged: _isSettingMode
                ? null
                : (selection) => _setControlMode(selection.first),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(subtitle,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant)),
        ],
      ),
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
            canPanLeft: _panAngle > _panMinDeg,
            canPanRight: _panAngle < _panMaxDeg,
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
              icon: Icons.smart_toy_outlined,
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
      // Mobile refreshes via pull-to-refresh, so hide the per-panel button.
      action: compact
          ? null
          : IconButton.filledTonal(
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
                  .map((event) => _ActivityTile(event: event))
                  .toList(),
            ),
    );
  }
}

String _formatTimestamp(DateTime? value) {
  if (value == null) return 'unknown time';
  return value.toLocal().toString().split('.').first;
}

// Severity -> tone (high/critical=red, medium=amber, low=blue). fromStatus only
// knows 'critical', so high/medium/low would otherwise all read as neutral gray.
StatusTone _severityTone(String severity) {
  switch (severity.toLowerCase().trim()) {
    case 'critical':
    case 'high':
      return StatusTone.danger;
    case 'medium':
      return StatusTone.warning;
    case 'low':
      return StatusTone.info;
    default:
      return StatusTone.neutral;
  }
}

/// A human label + tone for an event's verification status.
(String, StatusTone) _statusMeta(String status, bool degraded) {
  if (degraded) return ('Unverified', StatusTone.warning);
  switch (status.toLowerCase().trim()) {
    case 'verified':
      return ('Verified', StatusTone.success);
    case 'false_positive':
      return ('False positive', StatusTone.neutral);
    case 'dismissed':
      return ('Dismissed', StatusTone.neutral);
    case 'candidate':
      return ('Reviewing', StatusTone.warning);
    default:
      return (_titleCase(status), StatusTone.neutral);
  }
}

IconData _activityIcon(String eventType) {
  switch (eventType.toLowerCase()) {
    case 'person_detected':
      return Icons.person_outline;
    case 'vehicle_detected':
      return Icons.directions_car_outlined;
    case 'pet_detected':
      return Icons.pets_outlined;
    case 'object_detected':
      return Icons.inventory_2_outlined;
    case 'baby_crying':
      return Icons.child_care_outlined;
    case 'audio_threat':
      return Icons.graphic_eq;
    default:
      return Icons.sensors_outlined;
  }
}

String _titleCase(String value) => value
    .split(RegExp(r'[_\s]+'))
    .where((word) => word.isNotEmpty)
    .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
    .join(' ');

String _relativeTime(DateTime? value) {
  if (value == null) return '';
  final delta = DateTime.now().difference(value.toLocal());
  if (delta.isNegative || delta.inSeconds < 45) return 'just now';
  if (delta.inMinutes < 60) return '${delta.inMinutes}m ago';
  if (delta.inHours < 24) return '${delta.inHours}h ago';
  if (delta.inDays < 7) return '${delta.inDays}d ago';
  return value.toLocal().toString().split(' ').first;
}

/// Recent-activity row: event-typed icon tinted by severity, the summary, and a
/// colored chip row (severity / verification status / confidence) plus a
/// relative timestamp — more context than the old single-line tile.
class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.event});

  final SecurityEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final severityTone = _severityTone(event.severity);
    final (statusLabel, statusTone) = _statusMeta(event.status, event.degraded);
    final title = event.summary?.isNotEmpty == true
        ? event.summary!
        : _titleCase(event.eventType);

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconChip(
            icon: _activityIcon(event.eventType),
            size: 38,
            color: severityTone.base,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _MetaChip(label: _titleCase(event.severity), tone: severityTone),
                    _MetaChip(label: statusLabel, tone: statusTone),
                    if (event.confidence != null)
                      _MetaChip(
                        label: '${(event.confidence! * 100).round()}% sure',
                        tone: StatusTone.neutral,
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${_titleCase(event.eventType)} · ${_relativeTime(event.timestamp)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
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

/// Compact colored pill for event metadata.
class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label, required this.tone});

  final String label;
  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = tone.base;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppRadius.pillAll,
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Playback & download
// ---------------------------------------------------------------------------

class _PlaybackScrollBehavior extends MaterialScrollBehavior {
  const _PlaybackScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.stylus,
    PointerDeviceKind.trackpad,
  };
}

class _PlaybackDownloadPanel extends StatelessWidget {
  const _PlaybackDownloadPanel({
    required this.clips,
    required this.recordings,
    required this.events,
    required this.isLoading,
    required this.playingClipId,
    required this.playingRecordingId,
    required this.onRefresh,
    required this.onPlayClip,
    required this.onPlayRecording,
    this.error,
    this.showRefresh = true,
  });

  final List<MediaClip> clips;
  final List<MediaRecording> recordings;
  final List<SecurityEvent> events;
  final bool isLoading;
  final String? error;
  final String? playingClipId;
  final String? playingRecordingId;
  final VoidCallback onRefresh;
  final Future<void> Function(MediaClip clip) onPlayClip;
  final Future<void> Function(MediaRecording recording) onPlayRecording;

  /// Hidden on mobile, where the page is refreshed by pulling down.
  final bool showRefresh;

  @override
  Widget build(BuildContext context) {
    return ConsolePanel(
      title: 'Playback & Download',
      subtitle: 'Check saved and downloaded videos',
      icon: Icons.history_outlined,
      action: showRefresh
          ? IconButton.filledTonal(
              onPressed: isLoading ? null : onRefresh,
              tooltip: 'Refresh playback clips',
              icon: isLoading
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
            )
          : null,
      child: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (isLoading && clips.isEmpty) {
      return const SkeletonList(rows: 2);
    }

    if (error != null && clips.isEmpty) {
      return _CompactEmptyRow(
        icon: Icons.cloud_off_outlined,
        title: 'Playback unavailable',
        message: error!,
      );
    }

    if (clips.isEmpty) {
      return const _CompactEmptyRow(
        icon: Icons.video_library_outlined,
        title: 'No saved clips yet',
        message: 'Recorded detection clips will appear here.',
      );
    }

    final eventById = {for (final event in events) event.eventId: event};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RecordingBlockList(
          recordings: recordings,
          events: events,
          clips: clips,
          playingClipId: playingClipId,
          playingRecordingId: playingRecordingId,
          onPlayClip: onPlayClip,
          onPlayRecording: onPlayRecording,
        ),
        const SizedBox(height: AppSpacing.md),
        _PlaybackTimelineBlock(
          events: events,
          clips: clips,
          playingClipId: playingClipId,
          onPlayClip: onPlayClip,
        ),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          height: 106,
          child: ScrollConfiguration(
            behavior: const _PlaybackScrollBehavior(),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              itemCount: clips.length,
              separatorBuilder: (context, index) =>
                  const SizedBox(width: AppSpacing.sm),
              itemBuilder: (context, index) {
                final clip = clips[index];
                return _PlaybackClipTile(
                  clip: clip,
                  event: eventById[clip.eventId],
                  busy: playingClipId == clip.clipId,
                  onTap: () => onPlayClip(clip),
                );
              },
            ),
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            error!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }
}

class _RecordingBlockList extends StatelessWidget {
  const _RecordingBlockList({
    required this.recordings,
    required this.events,
    required this.clips,
    required this.playingClipId,
    required this.playingRecordingId,
    required this.onPlayClip,
    required this.onPlayRecording,
  });

  final List<MediaRecording> recordings;
  final List<SecurityEvent> events;
  final List<MediaClip> clips;
  final String? playingClipId;
  final String? playingRecordingId;
  final Future<void> Function(MediaClip clip) onPlayClip;
  final Future<void> Function(MediaRecording recording) onPlayRecording;

  @override
  Widget build(BuildContext context) {
    if (recordings.isEmpty) return const SizedBox.shrink();

    final sorted = [...recordings]
      ..sort((a, b) {
        final aStart = a.startTime ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bStart = b.startTime ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bStart.compareTo(aStart);
      });

    return SizedBox(
      height: 106,
      child: ScrollConfiguration(
        behavior: const _PlaybackScrollBehavior(),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const ClampingScrollPhysics(),
          itemCount: sorted.length,
          separatorBuilder: (context, index) =>
              const SizedBox(width: AppSpacing.sm),
          itemBuilder: (context, index) {
            return _RecordingBlockTile(
              recording: sorted[index],
              events: events,
              clips: clips,
              playingClipId: playingClipId,
              playingRecordingId: playingRecordingId,
              onPlayClip: onPlayClip,
              onPlayRecording: onPlayRecording,
            );
          },
        ),
      ),
    );
  }
}

class _RecordingBlockTile extends StatelessWidget {
  const _RecordingBlockTile({
    required this.recording,
    required this.events,
    required this.clips,
    required this.playingClipId,
    required this.playingRecordingId,
    required this.onPlayClip,
    required this.onPlayRecording,
  });

  final MediaRecording recording;
  final List<SecurityEvent> events;
  final List<MediaClip> clips;
  final String? playingClipId;
  final String? playingRecordingId;
  final Future<void> Function(MediaClip clip) onPlayClip;
  final Future<void> Function(MediaRecording recording) onPlayRecording;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final start = recording.startTime?.toLocal();
    final end = recording.endTime?.toLocal();
    final entries = _timelineEntries(events: events, clips: clips).where((entry) {
      if (start == null || end == null) return false;
      final timestamp = entry.timestamp.toLocal();
      return !timestamp.isBefore(start) && timestamp.isBefore(end);
    }).toList();
    final playableEntries = entries.where((entry) => entry.clip != null).toList();
    final isBusy = playingRecordingId == recording.recordingId;

    return SizedBox(
      width: 220,
      child: InkWell(
        borderRadius: AppRadius.mdAll,
        onTap: () => onPlayRecording(recording),
        child: Container(
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
                    start == null || end == null
                        ? 'Recording block'
                        : '${_formatTimelineTime(start)} - ${_formatTimelineTime(end)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.mono(
                      color: scheme.onSurface,
                    ).copyWith(fontWeight: FontWeight.w700, fontSize: 12),
                  ),
                ),
                if (isBusy)
                  const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  _PlaybackBadge(text: _formatDuration(recording.durationSeconds)),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const markerSize = 16.0;
                  final width = constraints.maxWidth;
                  final durationMs = start == null || end == null
                      ? 1.0
                      : end.difference(start).inMilliseconds.toDouble();
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        left: 0,
                        right: 0,
                        top: 18,
                        child: Container(
                          height: 8,
                          decoration: BoxDecoration(
                            color: scheme.primary.withValues(alpha: 0.18),
                            borderRadius: AppRadius.pillAll,
                          ),
                        ),
                      ),
                      for (final entry in entries)
                        _TimelineMarker(
                          entry: entry,
                          playingClipId: playingClipId,
                          left: start == null
                              ? 0
                              : (((entry.timestamp.toLocal()
                                              .difference(start)
                                              .inMilliseconds /
                                          durationMs) *
                                      (width - markerSize))
                                  .clamp(0.0, width - markerSize)),
                          size: markerSize,
                          onPlayClip: onPlayClip,
                        ),
                    ],
                  );
                },
              ),
            ),
            Text(
              playableEntries.isEmpty
                  ? recording.status
                  : '${playableEntries.length} event clips',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          ),
        ),
      ),
    );
  }
}

class _PlaybackTimelineBlock extends StatelessWidget {
  const _PlaybackTimelineBlock({
    required this.events,
    required this.clips,
    required this.playingClipId,
    required this.onPlayClip,
  });

  final List<SecurityEvent> events;
  final List<MediaClip> clips;
  final String? playingClipId;
  final Future<void> Function(MediaClip clip) onPlayClip;

  @override
  Widget build(BuildContext context) {
    final entries = _timelineEntries(events: events, clips: clips);
    if (entries.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final latest = entries.last.timestamp.toLocal();
    final windowStart = DateTime(
      latest.year,
      latest.month,
      latest.day,
      latest.hour,
      (latest.minute ~/ 30) * 30,
    );
    final windowEnd = windowStart.add(const Duration(minutes: 30));
    final visibleEntries = entries.where((entry) {
      final timestamp = entry.timestamp.toLocal();
      return !timestamp.isBefore(windowStart) && timestamp.isBefore(windowEnd);
    }).toList();
    final playableCount = visibleEntries.where((entry) => entry.clip != null).length;

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
              Expanded(
                child: Text(
                  '${_formatTimelineTime(windowStart)} - ${_formatTimelineTime(windowEnd)}',
                  style: AppTypography.mono(
                    color: scheme.onSurface,
                  ).copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                '$playableCount clips',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 38,
            child: LayoutBuilder(
              builder: (context, constraints) {
                const markerSize = 20.0;
                final width = constraints.maxWidth;
                final windowMs = windowEnd
                    .difference(windowStart)
                    .inMilliseconds
                    .toDouble();

                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 17,
                      child: Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: scheme.outlineVariant,
                          borderRadius: AppRadius.pillAll,
                        ),
                      ),
                    ),
                    for (final entry in visibleEntries)
                      _TimelineMarker(
                        entry: entry,
                        playingClipId: playingClipId,
                        left: (((entry.timestamp.toLocal()
                                        .difference(windowStart)
                                        .inMilliseconds /
                                    windowMs) *
                                (width - markerSize))
                            .clamp(0.0, width - markerSize)),
                        size: markerSize,
                        onPlayClip: onPlayClip,
                      ),
                  ],
                );
              },
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatTimelineTime(windowStart),
                style: theme.textTheme.labelSmall,
              ),
              Text(
                _formatTimelineTime(windowEnd),
                style: theme.textTheme.labelSmall,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TimelineEntry {
  const _TimelineEntry({
    required this.timestamp,
    this.event,
    this.clip,
  });

  final DateTime timestamp;
  final SecurityEvent? event;
  final MediaClip? clip;

  String get label => event?.eventType ?? 'Recorded clip';
  String get severity => event?.severity ?? 'medium';
}

List<_TimelineEntry> _timelineEntries({
  required List<SecurityEvent> events,
  required List<MediaClip> clips,
}) {
  final eventById = {for (final event in events) event.eventId: event};
  final entries = <_TimelineEntry>[];
  final clipEventIds = <String>{};

  for (final clip in clips) {
    final event = eventById[clip.eventId];
    final timestamp = event?.timestamp ?? clip.uploadCompletedAt;
    if (timestamp == null) continue;
    clipEventIds.add(clip.eventId);
    entries.add(_TimelineEntry(timestamp: timestamp, event: event, clip: clip));
  }

  for (final event in events) {
    if (event.timestamp == null || clipEventIds.contains(event.eventId)) {
      continue;
    }
    entries.add(_TimelineEntry(timestamp: event.timestamp!, event: event));
  }

  entries.sort((a, b) => a.timestamp.compareTo(b.timestamp));
  return entries;
}

class _TimelineMarker extends StatelessWidget {
  const _TimelineMarker({
    required this.entry,
    required this.left,
    required this.size,
    required this.onPlayClip,
    this.playingClipId,
  });

  final _TimelineEntry entry;
  final String? playingClipId;
  final double left;
  final double size;
  final Future<void> Function(MediaClip clip) onPlayClip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tone = StatusToneColor.fromStatus(entry.severity).base;
    final clip = entry.clip;
    final isBusy = clip != null && playingClipId == clip.clipId;

    return Positioned(
      left: left,
      top: 8,
      child: Tooltip(
        message: '${entry.label} - ${_formatTimelineTime(entry.timestamp.toLocal())}',
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: clip == null || isBusy ? null : () => onPlayClip(clip),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: clip == null ? scheme.surfaceContainerHighest : tone,
              shape: BoxShape.circle,
              border: Border.all(
                color: clip == null ? scheme.outline : Colors.white,
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: tone.withValues(alpha: 0.24),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: isBusy
                ? Padding(
                    padding: const EdgeInsets.all(3),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: scheme.onPrimary,
                    ),
                  )
                : Icon(
                    _eventIcon(entry.event?.eventType, clip?.clipType),
                    size: 12,
                    color: clip == null ? scheme.onSurfaceVariant : Colors.white,
                  ),
          ),
        ),
      ),
    );
  }
}
IconData _eventIcon(String? eventType, String? clipType) {
  final value = (eventType ?? clipType ?? '').toLowerCase();
  if (value.contains('person') || value.contains('human')) {
    return Icons.person_search_outlined;
  }
  if (value.contains('motion') || value.contains('movement')) {
    return Icons.directions_run_outlined;
  }
  if (value.contains('vehicle') || value.contains('car')) {
    return Icons.directions_car_outlined;
  }
  if (value.contains('animal')) {
    return Icons.pets_outlined;
  }
  if (value.contains('package') || value.contains('object')) {
    return Icons.inventory_2_outlined;
  }
  return Icons.crisis_alert_outlined;
}

String _eventLabel(String? eventType, String clipType) {
  final raw = eventType ?? (clipType == 'event' ? 'activity_detected' : clipType);
  return raw
      .replaceAll('_', ' ')
      .split(' ')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}
class _PlaybackClipTile extends StatelessWidget {
  const _PlaybackClipTile({
    required this.clip,
    required this.event,
    required this.busy,
    required this.onTap,
  });

  final MediaClip clip;
  final SecurityEvent? event;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final clipTime = _formatClipClock(clip.uploadCompletedAt);
    final duration = _formatDuration(clip.durationSeconds);
    final eventIcon = _eventIcon(event?.eventType, clip.clipType);
    final eventLabel = _eventLabel(event?.eventType, clip.clipType);

    return SizedBox(
      width: 138,
      child: InkWell(
        borderRadius: AppRadius.mdAll,
        onTap: busy ? null : onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF17211E),
                  borderRadius: AppRadius.mdAll,
                  border: Border.all(color: scheme.outlineVariant),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF22332D), Color(0xFF0A1412)],
                        ),
                      ),
                    ),
                    Positioned(
                      top: 6,
                      left: 6,
                      child: _PlaybackBadge(text: duration),
                    ),
                    Center(
                      child: busy
                          ? const SizedBox.square(
                              dimension: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.42),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.2),
                                ),
                              ),
                              child: Icon(
                                eventIcon,
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                    ),
                    Positioned(
                      right: 6,
                      bottom: 5,
                      child: Text(
                        clipTime,
                        style: AppTypography.mono(
                          color: Colors.white.withValues(alpha: 0.9),
                        ).copyWith(fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              eventLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaybackBadge extends StatelessWidget {
  const _PlaybackBadge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: AppRadius.smAll,
      ),
      child: Text(
        text,
        style: AppTypography.mono(
          color: Colors.white,
        ).copyWith(fontSize: 10, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _RecordingPlaybackSheet extends StatelessWidget {
  const _RecordingPlaybackSheet({
    required this.recording,
    required this.playback,
    required this.onOpen,
  });

  final MediaRecording recording;
  final RecordingPlaybackUrl playback;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final expires = playback.expiresAt == null
        ? 'Short-lived signed link'
        : 'Expires ${_formatTimestamp(playback.expiresAt)}';
    final title = recording.startTime == null || recording.endTime == null
        ? 'Recording block'
        : '${_formatTimelineTime(recording.startTime!)} - ${_formatTimelineTime(recording.endTime!)}';

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.of(context).viewInsets.bottom +
                          AppSpacing.lg,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const IconChip(icon: Icons.video_library_outlined),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(title, style: theme.textTheme.titleMedium),
                                  Text(expires, style: theme.textTheme.bodySmall),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        ClipRRect(
                          borderRadius: AppRadius.mdAll,
                          child: AspectRatio(
                            aspectRatio: 16 / 9,
                            child: PlaybackVideoView(url: playback.playbackUrl),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        Container(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerLow,
                            borderRadius: AppRadius.mdAll,
                            border: Border.all(
                              color: theme.colorScheme.outlineVariant,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _PlaybackMetaRow(
                                label: 'Duration',
                                value: _formatDuration(recording.durationSeconds),
                              ),
                              _PlaybackMetaRow(
                                label: 'Start',
                                value: _formatTimestamp(recording.startTime),
                              ),
                              _PlaybackMetaRow(
                                label: 'End',
                                value: _formatTimestamp(recording.endTime),
                              ),
                              _PlaybackMetaRow(
                                label: 'Status',
                                value: recording.status,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                FilledButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.open_in_new_outlined),
                  label: const Text('Open recording'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
class _PlaybackSheet extends StatelessWidget {
  const _PlaybackSheet({
    required this.clip,
    required this.playback,
    required this.onOpen,
    required this.onDownload,
  });

  final MediaClip clip;
  final ClipPlaybackUrl playback;
  final VoidCallback onOpen;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final expires = playback.expiresAt == null
        ? 'Short-lived signed link'
        : 'Expires ${_formatTimestamp(playback.expiresAt)}';

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.of(context).viewInsets.bottom +
                          AppSpacing.lg,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const IconChip(icon: Icons.play_circle_outline),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Playback clip',
                                    style: theme.textTheme.titleMedium,
                                  ),
                                  Text(expires, style: theme.textTheme.bodySmall),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        ClipRRect(
                          borderRadius: AppRadius.mdAll,
                          child: AspectRatio(
                            aspectRatio: 16 / 9,
                            child: PlaybackVideoView(url: playback.playbackUrl),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        Container(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerLow,
                            borderRadius: AppRadius.mdAll,
                            border: Border.all(
                              color: theme.colorScheme.outlineVariant,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _PlaybackMetaRow(
                                label: 'Duration',
                                value: _formatDuration(clip.durationSeconds),
                              ),
                              _PlaybackMetaRow(
                                label: 'Captured',
                                value: _formatTimestamp(clip.uploadCompletedAt),
                              ),
                              _PlaybackMetaRow(
                                label: 'Status',
                                value: clip.status,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: onOpen,
                        icon: const Icon(Icons.open_in_new_outlined),
                        label: const Text('Open'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onDownload,
                        icon: const Icon(Icons.download_outlined),
                        label: const Text('Download'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
class _PlaybackMetaRow extends StatelessWidget {
  const _PlaybackMetaRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 82,
            child: Text(label, style: theme.textTheme.bodySmall),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatTimelineTime(DateTime value) {
  final local = value.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}
String _formatDuration(int? seconds) {
  if (seconds == null || seconds <= 0) return '--:--';
  final minutes = seconds ~/ 60;
  final remaining = seconds % 60;
  return '${minutes.toString().padLeft(2, '0')}:${remaining.toString().padLeft(2, '0')}';
}

String _formatClipClock(DateTime? value) {
  if (value == null) return '--:--';
  final local = value.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

class _CameraActionBar extends StatelessWidget {
  const _CameraActionBar({
    required this.isRecording,
    required this.isMuted,
    required this.resolution,
    required this.busyKey,
    required this.onRecord,
    required this.onMute,
    required this.onResolution,
    required this.onFullscreen,
  });

  final bool isRecording;
  final bool isMuted;
  final String resolution;
  final String? busyKey;
  final VoidCallback onRecord;
  final VoidCallback onMute;
  final VoidCallback onResolution;
  final VoidCallback onFullscreen;

  @override
  Widget build(BuildContext context) {
    final actions = <_CameraAction>[
      _CameraAction(
        icon: isRecording ? Icons.stop_circle_outlined : Icons.videocam_outlined,
        label: isRecording ? 'Stop' : 'Record',
        onTap: busyKey == 'recording' ? null : onRecord,
        active: isRecording,
        busy: busyKey == 'recording',
      ),
      _CameraAction(
        icon: isMuted ? Icons.volume_off_outlined : Icons.volume_up_outlined,
        label: isMuted ? 'Muted' : 'Mute',
        onTap: busyKey == 'audio_mute' ? null : onMute,
        active: isMuted,
        busy: busyKey == 'audio_mute',
      ),
      _CameraAction(
        icon: Icons.hd_outlined,
        label: resolution,
        onTap: busyKey == 'resolution' ? null : onResolution,
        busy: busyKey == 'resolution',
      ),
      _CameraAction(
        icon: Icons.fullscreen_outlined,
        label: 'Full',
        onTap: onFullscreen,
      ),
    ];

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 4 icons per row on phones; a single row on wider surfaces.
          final perRow = constraints.maxWidth < 520 ? 4 : actions.length;
          const spacing = AppSpacing.sm;
          final itemWidth =
              (constraints.maxWidth - spacing * (perRow - 1)) / perRow;
          return Wrap(
            spacing: spacing,
            runSpacing: AppSpacing.md,
            children: [
              for (final action in actions)
                SizedBox(
                  width: itemWidth,
                  child: _CameraActionButton(
                    icon: action.icon,
                    label: action.label,
                    onTap: action.onTap,
                    active: action.active,
                    busy: action.busy,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Immutable descriptor for one camera control, resolved from the current
/// device state before layout.
class _CameraAction {
  const _CameraAction({
    required this.icon,
    required this.label,
    this.onTap,
    this.active = false,
    this.busy = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;
  final bool busy;
}

/// Circular icon button with a caption underneath, matching the PTZ pad style.
/// Neutral by default; filled with the accent colour only while [active].
class _CameraActionButton extends StatelessWidget {
  const _CameraActionButton({
    required this.icon,
    required this.label,
    this.onTap,
    this.active = false,
    this.busy = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;
  final bool busy;

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
      message: enabled ? label : '$label unavailable',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              customBorder: const CircleBorder(),
              child: Ink(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: bg,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: enabled && active
                        ? scheme.primary
                        : scheme.outlineVariant,
                  ),
                ),
                child: Center(
                  child: busy
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: fg,
                          ),
                        )
                      : Icon(icon, size: 22, color: fg),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: enabled ? scheme.onSurface : scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
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
            if (streamUrl != null) LiveStreamView(url: streamUrl),
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
            icon: Icons.smart_toy_outlined,
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

