import 'package:flutter/material.dart';

/// The root messenger shared by route-local and background event handlers.
///
/// Realtime callbacks can outlive or sit below a deferred route, so they must
/// not depend on a local [BuildContext] to present a notification.
final appScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
