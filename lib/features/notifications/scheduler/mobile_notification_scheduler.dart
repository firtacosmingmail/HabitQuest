import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../reminder_request.dart';
import 'notification_scheduler.dart';

/// Android / iOS reminders via flutter_local_notifications.
///
/// * Daily / weekly reminders use `matchDateTimeComponents` so the OS repeats
///   them; one-shots (every-N-days) are plain zoned schedules.
/// * Android: inexact (`inexactAllowWhileIdle`) unless the user granted the
///   exact-alarm permission; an exact-alarm failure falls back to inexact.
class MobileNotificationScheduler implements NotificationScheduler {
  static const channelId = 'habit_reminders';
  static const channelName = 'Habit reminders';
  static const channelDescription = 'Reminders to check in on your habits';
  static const androidIcon = 'ic_stat_habit_quest';

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;
  bool _exactAllowed = false;

  MobileNotificationScheduler({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      icon: androidIcon,
      category: AndroidNotificationCategory.reminder,
    ),
    iOS: DarwinNotificationDetails(),
  );

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  IOSFlutterLocalNotificationsPlugin? get _ios => _plugin
      .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    await _initTimeZone();
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings(androidIcon),
          // Permission is requested explicitly (see requestPermission) only
          // once a habit with a reminder exists.
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
      );
      _exactAllowed = await _android?.canScheduleExactNotifications() ?? false;
    } catch (e) {
      debugPrint('Notifications: plugin init failed: $e');
    }
  }

  Future<void> _initTimeZone() async {
    tzdata.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (e) {
      // Unknown identifier / plugin unavailable: pick any zone whose current
      // offset matches the device so reminders still fire at the right time.
      debugPrint('Notifications: local time zone lookup failed: $e');
      final offset = DateTime.now().timeZoneOffset;
      final match = tz.timeZoneDatabase.locations.values.where(
        (l) => l.currentTimeZone.offset == offset,
      );
      if (match.isNotEmpty) tz.setLocalLocation(match.first);
    }
  }

  @override
  Future<bool> requestPermission() async {
    try {
      final android = _android;
      if (android != null) {
        final granted = await android.requestNotificationsPermission() ?? true;
        _exactAllowed = await android.canScheduleExactNotifications() ?? false;
        return granted;
      }
      final ios = _ios;
      if (ios != null) {
        return await ios.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            ) ??
            false;
      }
    } catch (e) {
      debugPrint('Notifications: permission request failed: $e');
    }
    return false;
  }

  @override
  Future<void> schedule(List<ReminderRequest> requests) async {
    for (final r in requests) {
      final mode = _exactAllowed
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle;
      try {
        await _zonedSchedule(r, mode);
      } on PlatformException catch (e) {
        if (mode == AndroidScheduleMode.exactAllowWhileIdle) {
          // Permission revoked since we checked: fall back to inexact.
          _exactAllowed = false;
          await _tryZonedSchedule(r, AndroidScheduleMode.inexactAllowWhileIdle);
        } else {
          debugPrint('Notifications: scheduling #${r.id} failed: $e');
        }
      } catch (e) {
        debugPrint('Notifications: scheduling #${r.id} failed: $e');
      }
    }
  }

  Future<void> _tryZonedSchedule(
    ReminderRequest r,
    AndroidScheduleMode mode,
  ) async {
    try {
      await _zonedSchedule(r, mode);
    } catch (e) {
      debugPrint('Notifications: scheduling #${r.id} failed: $e');
    }
  }

  Future<void> _zonedSchedule(ReminderRequest r, AndroidScheduleMode mode) {
    final f = r.firstFire;
    return _plugin.zonedSchedule(
      id: r.id,
      scheduledDate:
          tz.TZDateTime(tz.local, f.year, f.month, f.day, f.hour, f.minute),
      notificationDetails: _details,
      androidScheduleMode: mode,
      title: r.title,
      body: r.body,
      payload: r.habitId,
      matchDateTimeComponents: switch (r.repeat) {
        ReminderRepeat.daily => DateTimeComponents.time,
        ReminderRepeat.weekly => DateTimeComponents.dayOfWeekAndTime,
        ReminderRepeat.once => null,
      },
    );
  }

  @override
  Future<void> cancel(Iterable<int> ids) async {
    for (final id in ids) {
      try {
        await _plugin.cancel(id: id);
      } catch (e) {
        debugPrint('Notifications: cancel #$id failed: $e');
      }
    }
  }

  @override
  Future<Set<int>> pendingIds() async {
    try {
      final pending = await _plugin.pendingNotificationRequests();
      return pending.map((p) => p.id).toSet();
    } catch (e) {
      debugPrint('Notifications: pending lookup failed: $e');
      return const {};
    }
  }

  @override
  void dispose() {}
}
