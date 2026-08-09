import 'package:flutter/material.dart';

/// App-wide navigator, reachable from code with no BuildContext — needed so
/// a notification tap (e.g. the attendance reminder's QR-scan action) can
/// push a screen even at cold start, before any widget has built. Kept in
/// its own file (not main.dart) so services like ReminderService can import
/// it without a circular dependency on main.dart.
final navigatorKey = GlobalKey<NavigatorState>();
