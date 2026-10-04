import 'package:flutter/material.dart';

import 'reminder_request.dart';

/// App-wide [ScaffoldMessenger] key, wired into `MaterialApp` in `app.dart`.
/// Used for in-app reminder banners on web; other features may reuse it to
/// show snackbars from outside the widget tree.
final GlobalKey<ScaffoldMessengerState> appScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>(debugLabel: 'appScaffoldMessenger');

/// Shows [request] as a floating snackbar via [messengerKey]. Silently does
/// nothing when no messenger is mounted yet.
void showInAppReminder(
  ReminderRequest request, {
  GlobalKey<ScaffoldMessengerState>? messengerKey,
}) {
  final messenger = (messengerKey ?? appScaffoldMessengerKey).currentState;
  if (messenger == null) return;
  messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 8),
      content: Row(
        children: [
          const Text('⏰', style: TextStyle(fontSize: 24)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  request.title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(request.body),
              ],
            ),
          ),
        ],
      ),
      action: SnackBarAction(label: 'OK', onPressed: () {}),
    ),
  );
}
