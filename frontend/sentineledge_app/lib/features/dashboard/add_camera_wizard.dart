import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../design/app_colors.dart';
import '../../design/app_spacing.dart';
import '../../services/backend_auth_client.dart';
import '../../shared/console_widgets.dart';

/// Market-style camera onboarding: name the camera, enter Wi-Fi, then show a
/// pairing QR that the ESP32-CAM reads with its own lens to provision itself.
///
/// Pops `true` when a camera was registered (so the workspace refreshes).
class AddCameraWizard extends StatefulWidget {
  const AddCameraWizard({required this.apiClient, super.key});

  final ErlangVisionApiClient apiClient;

  @override
  State<AddCameraWizard> createState() => _AddCameraWizardState();
}

class _AddCameraWizardState extends State<AddCameraWizard> {
  final _nameController = TextEditingController();
  final _locationController = TextEditingController();
  final _ssidController = TextEditingController();
  final _passwordController = TextEditingController();
  final _hostController = TextEditingController();
  // The camera dials the laptop running edge_bridge.py (the receiver), default
  // port 8765 ??? not the backend's 8000.
  final _portController = TextEditingController(text: '8765');

  // Common places offered as presets, plus a "Custom" option that reveals a
  // free-text field.
  static const List<String> _locationPresets = [
    'Front Door',
    'Backyard',
    'Living Room',
    'Kitchen',
    'Bedroom',
    'Garage',
    'Driveway',
    'Office',
    'Nursery',
    'Hallway',
    'Street',
  ];
  static const String _customLocation = 'Custom location…';
  String _locationChoice = _locationPresets.first;
  bool get _isCustomLocation => _locationChoice == _customLocation;
  String _locationValue() =>
      _isCustomLocation ? _locationController.text.trim() : _locationChoice;

  int _step = 0; // 0 details, 1 wifi, 2 pair
  bool _busy = false;
  bool _passwordObscured = true;
  bool _registered = false;
  bool _online = false;
  String? _error;

  DeviceRegistration? _registration;
  Timer? _pollTimer;

  @override
  void dispose() {
    _pollTimer?.cancel();
    _nameController.dispose();
    _locationController.dispose();
    _ssidController.dispose();
    _passwordController.dispose();
    _hostController.dispose();
    _portController.dispose();
    super.dispose();
  }

  // --- step transitions ------------------------------------------------------

  Future<void> _createDeviceAndContinue() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Camera name is required.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final registration = await widget.apiClient.registerDevice(
        name: name,
        location: _locationValue(),
      );
      // Pre-fill the laptop IP the camera should dial. The receiver/bridge
      // normally runs on the same machine as the backend, so the backend's LAN
      // IP is the right host; the port stays 8765 (the bridge's device port).
      try {
        final net = await widget.apiClient.networkInfo();
        if (net.lanIp != null && net.lanIp!.isNotEmpty) {
          _hostController.text = net.lanIp!;
        }
      } catch (_) {
        // Non-fatal: user can type the host manually.
      }
      if (!mounted) return;
      setState(() {
        _registration = registration;
        _registered = true;
        _step = 1;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _continueToPairing() {
    if (_ssidController.text.trim().isEmpty) {
      setState(() => _error = 'Wi-Fi network name (SSID) is required.');
      return;
    }
    if (_hostController.text.trim().isEmpty) {
      setState(() => _error = 'Backend address is required so the camera can connect.');
      return;
    }
    setState(() {
      _error = null;
      _step = 2;
    });
    _startPolling();
  }

  /// The compact JSON the firmware decodes. Short keys keep the QR small.
  /// Carries Wi-Fi, the receiver (laptop) address, and the one-time edge token
  /// so the bridge can adopt the backend credential when the camera connects.
  ///
  /// Every byte here raises the QR version (denser modules), which the ESP32's
  /// OV2640 struggles to decode. So we emit only what the firmware actually
  /// reads, and drop fields it already defaults: `path` (defaults to '/') and
  /// the port when it's the standard 8765. The firmware ignores any field it
  /// doesn't recognise, so omitting defaults is safe.
  String _pairingPayload() {
    final port = int.tryParse(_portController.text.trim()) ?? 8765;
    final payload = <String, dynamic>{
      's': _ssidController.text.trim(),
      'p': _passwordController.text,
      'h': _hostController.text.trim(),
      'v': 2,
      'path': '/',
      if (_registration != null) 'k': _registration!.deviceLinkSecret,
    };
    payload['o'] = port;
    return jsonEncode(payload);
  }

  void _startPolling() {
    _pollTimer?.cancel();
    final deviceId = _registration?.device.deviceId;
    if (deviceId == null) return;
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      try {
        final device = await widget.apiClient.getDevice(deviceId);
        if (!mounted) return;
        if (device.healthStatus == 'online') {
          setState(() => _online = true);
          _pollTimer?.cancel();
        }
      } catch (_) {
        // Keep polling; transient errors are expected during pairing.
      }
    });
  }

  void _finish() => Navigator.of(context).pop(_registered);

  // --- build -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Return whether a camera was registered, even on back gesture.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_registered);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Add camera'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: _finish,
          ),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  _StepHeader(step: _step),
                  const SizedBox(height: AppSpacing.lg),
                  if (_error != null) ...[
                    AppBanner(text: _error!),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                  switch (_step) {
                    0 => _detailsStep(),
                    1 => _wifiStep(),
                    _ => _pairStep(),
                  },
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _detailsStep() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Name your camera', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _nameController,
            autofocus: true,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Camera name',
              prefixIcon: Icon(Icons.videocam_outlined),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          DropdownButtonFormField<String>(
            initialValue: _locationChoice,
            decoration: const InputDecoration(
              labelText: 'Location',
              prefixIcon: Icon(Icons.place_outlined),
            ),
            items: [
              for (final place in _locationPresets)
                DropdownMenuItem(value: place, child: Text(place)),
              const DropdownMenuItem(
                value: _customLocation,
                child: Text('Custom location…'),
              ),
            ],
            onChanged: (value) => setState(
              () => _locationChoice = value ?? _locationPresets.first,
            ),
          ),
          if (_isCustomLocation) ...[
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _locationController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Custom location',
                hintText: 'e.g. Rooftop, Warehouse Bay 3, Reception',
                prefixIcon: Icon(Icons.edit_location_alt_outlined),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          FilledButton(
            onPressed: _busy ? null : _createDeviceAndContinue,
            child: _busy
                ? const _ButtonSpinner(label: 'Registering')
                : const Text('Next'),
          ),
        ],
      ),
    );
  }

  Widget _wifiStep() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Wi-Fi for the camera', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'The camera will join this network. Use a 2.4 GHz network ??? ESP32-CAM does not support 5 GHz.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _ssidController,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Wi-Fi name (SSID)',
              prefixIcon: Icon(Icons.wifi),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _passwordController,
            obscureText: _passwordObscured,
            decoration: InputDecoration(
              labelText: 'Wi-Fi password',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(_passwordObscured ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _passwordObscured = !_passwordObscured),
              ),
            ),
          ),
          const Divider(height: AppSpacing.xl),
          Text('Receiver (laptop) address', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          Text(
            'The camera connects to the laptop running the bridge (edge_bridge.py). '
            'Pre-filled with your LAN IP; port is 8765 by default.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _hostController,
                  decoration: const InputDecoration(
                    labelText: 'Host / IP',
                    prefixIcon: Icon(Icons.dns_outlined),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: TextField(
                  controller: _portController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Port'),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              TextButton(
                onPressed: () => setState(() => _step = 0),
                child: const Text('Back'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _continueToPairing,
                child: const Text('Show pairing code'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pairStep() {
    final theme = Theme.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _online ? 'Camera connected' : 'Scan with your camera',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            _online
                ? 'Your camera is online and streaming. You can finish now.'
                : 'Put the camera in pairing mode, then hold this code in front '
                      'of its lens until the camera reports it is connected.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.lg),
          Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: _online ? _onlineBadge() : _qrCard(),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (!_online)
            Row(
              children: [
                const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Waiting for the camera to come online???',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              TextButton(
                onPressed: () => setState(() => _step = 1),
                child: const Text('Back'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _finish,
                child: Text(_online ? 'Done' : 'Finish later'),
              ),
            ],
          ),
          const Divider(height: AppSpacing.xl),
          Text('Start the bridge on your laptop', style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          Text(
            'Run edge_bridge.py on the laptop. After the camera scans this QR, '
            'the bridge receives the camera token automatically.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          if (_registration != null) TokenBox(token: _registration!.edgeToken),
          const SizedBox(height: AppSpacing.md),
          Text(
            'The pairing code contains your Wi-Fi password and camera token ??? only show it to your camera.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _qrCard() {
    return Container(
      key: const ValueKey('qr'),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.lgAll,
      ),
      child: QrImageView(
        data: _pairingPayload(),
        version: QrVersions.auto,
        size: 300,
        backgroundColor: Colors.white,
        errorCorrectionLevel: QrErrorCorrectLevel.L,
      ),
    );
  }

  Widget _onlineBadge() {
    return Column(
      key: const ValueKey('online'),
      children: [
        Icon(Icons.check_circle, color: AppColors.success, size: 64),
        const SizedBox(height: AppSpacing.sm),
        StatusPill.fromStatus('online'),
      ],
    );
  }
}

class _StepHeader extends StatelessWidget {
  const _StepHeader({required this.step});

  final int step;

  static const _labels = ['Details', 'Wi-Fi', 'Pair'];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: List.generate(_labels.length, (i) {
        final active = i <= step;
        return Expanded(
          child: Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: active ? scheme.primary : scheme.surfaceContainerHighest,
                child: Text(
                  '${i + 1}',
                  style: TextStyle(
                    color: active ? scheme.onPrimary : scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  _labels[i],
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: active ? scheme.onSurface : scheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (i < _labels.length - 1)
                Expanded(
                  child: Divider(
                    color: i < step ? scheme.primary : scheme.outlineVariant,
                    thickness: 2,
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }
}

class _ButtonSpinner extends StatelessWidget {
  const _ButtonSpinner({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox.square(
          dimension: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(label),
      ],
    );
  }
}

