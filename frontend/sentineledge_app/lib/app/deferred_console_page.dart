import 'package:flutter/material.dart';

import '../features/dashboard/console_page.dart' deferred as console;
import '../features/dashboard/workspace_section.dart';

class DeferredConsolePage extends StatefulWidget {
  const DeferredConsolePage({
    required this.section,
    this.selectedEventId,
    super.key,
  });

  final WorkspaceSection section;
  final String? selectedEventId;

  @override
  State<DeferredConsolePage> createState() => _DeferredConsolePageState();
}

class _DeferredConsolePageState extends State<DeferredConsolePage> {
  late final Future<void> _library = console.loadLibrary();

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: _library,
    builder: (context, snapshot) {
      if (snapshot.hasError) return const _ConsoleLoadError();
      if (snapshot.connectionState != ConnectionState.done) {
        return const _ConsoleLoading();
      }
      return console.ConsolePage(
        section: widget.section,
        selectedEventId: widget.selectedEventId,
      );
    },
  );
}

class DeferredDeviceControlPage extends StatefulWidget {
  const DeferredDeviceControlPage({required this.deviceId, super.key});

  final String deviceId;

  @override
  State<DeferredDeviceControlPage> createState() =>
      _DeferredDeviceControlPageState();
}

class _DeferredDeviceControlPageState extends State<DeferredDeviceControlPage> {
  late final Future<void> _library = console.loadLibrary();

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: _library,
    builder: (context, snapshot) {
      if (snapshot.hasError) return const _ConsoleLoadError();
      if (snapshot.connectionState != ConnectionState.done) {
        return const _ConsoleLoading();
      }
      return console.DeviceControlPage(deviceId: widget.deviceId);
    },
  );
}

class _ConsoleLoading extends StatelessWidget {
  const _ConsoleLoading();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

class _ConsoleLoadError extends StatelessWidget {
  const _ConsoleLoadError();

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(child: Text('Console could not be loaded. Please retry.')),
  );
}
