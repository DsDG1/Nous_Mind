import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/app_settings.dart';
import '../models/reminder.dart';

/// Wraps [FlutterLocalNotificationsPlugin] with reminder-specific helpers.
///
/// Initialised once from `main()` before `runApp`. The plugin instance is a
/// singleton; this service is exposed app-wide via `Provider.value`.
class NotificationService {
  NotificationService();

  static const String _channelId = 'reminders';
  static const String _channelName = '提醒事项';
  static const String _channelDescription = '到时间后的提醒通知';
  static const String _bodySuffix = '提醒时间到啦';

  /// Used by [showImmediate] so repeated taps overwrite the previous test
  /// notification instead of stacking up in the tray.
  static const int _immediateNotificationId = 0;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// Boots the plugin and the timezone database.
  ///
  /// [onTapNotification] fires whenever the user activates a notification —
  /// either while the app is running or as a cold-start launch from a tap.
  /// Callers typically wire this to `router.go('/')` to surface the
  /// reminders tab.
  Future<void> init({required void Function() onTapNotification}) async {
    if (_initialized) {
      return;
    }
    _initialized = true;

    tz_data.initializeTimeZones();
    try {
      final timezoneInfo = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timezoneInfo.identifier));
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Failed to resolve local timezone; falling back to UTC',
        error: error,
        stackTrace: stackTrace,
      );
      tz.setLocalLocation(tz.UTC);
    }

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      const InitializationSettings(android: androidInit, iOS: darwinInit),
      onDidReceiveNotificationResponse: (response) {
        onTapNotification();
      },
    );

    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp ?? false) {
      onTapNotification();
    }
  }

  /// Asks the OS for the runtime permissions needed to post local
  /// notifications. Returns `true` only when every platform-specific
  /// sub-request reports success.
  Future<bool> requestPermissions() async {
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    final iosGranted =
        await ios?.requestPermissions(alert: true, badge: true, sound: true) ??
        true;

    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final notificationsGranted =
        await android?.requestNotificationsPermission() ?? true;
    final exactAlarmsGranted =
        await android?.requestExactAlarmsPermission() ?? true;

    return iosGranted && notificationsGranted && exactAlarmsGranted;
  }

  /// Schedules a notification for [reminder.reminderTime], adjusted by
  /// the user's notification preferences:
  ///
  /// * [quietHours] — when supplied and the time falls inside
  ///   the window, the trigger is pushed past the window's end. Pass null
  ///   to disable.
  /// * [vibrationEnabled] — propagated to [AndroidNotificationDetails].
  ///
  /// Silently no-ops when the final trigger time is still in the past —
  /// the reminder is still saved, but no notification will fire.
  Future<void> scheduleReminder(
    Reminder reminder, {
    bool vibrationEnabled = true,
    QuietHoursWindow? quietHours,
  }) async {
    if (reminder.reminderTime.isBefore(DateTime.now())) {
      return;
    }
    final base = reminder.reminderTime;
    final tzNow = tz.TZDateTime.now(tz.local);
    final tzBase = tz.TZDateTime.from(base, tz.local);
    final tzTarget =
        quietHours != null && quietHours.contains(TimeOfDay.fromDateTime(base))
        ? tz.TZDateTime.from(quietHours.pushPast(base), tz.local)
        : tzBase;
    if (tzTarget.isBefore(tzNow)) {
      return;
    }
    final body = _composeBody(reminder.title);
    await _plugin.zonedSchedule(
      _idFromReminderId(reminder.id),
      reminder.title,
      body,
      tzTarget,
      _details(vibrationEnabled: vibrationEnabled),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  /// Body text for a scheduled reminder.
  String _composeBody(String title) {
    return _bodySuffix;
  }

  /// Cancels the scheduled notification for [reminderId] (if any).
  Future<void> cancelReminder(String reminderId) async {
    await _plugin.cancel(_idFromReminderId(reminderId));
  }

  /// Fires a notification immediately. Used by the Settings → experience
  /// button so users can verify the notification setup without waiting
  /// for a real reminder.
  Future<void> showImmediate({
    required String title,
    required String body,
    bool vibrationEnabled = true,
  }) async {
    await _plugin.show(
      _immediateNotificationId,
      title,
      body,
      _details(vibrationEnabled: vibrationEnabled),
    );
  }

  NotificationDetails _details({required bool vibrationEnabled}) =>
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.max,
          priority: Priority.high,
          ticker: '提醒',
          enableVibration: vibrationEnabled,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      );

  /// Maps the reminder's microseconds-since-epoch id (a string) onto a
  /// stable positive 32-bit integer that the plugin accepts as its
  /// notification id. We mask to 31 bits to stay within int32 range and
  /// ensure the result is non-negative.
  static int _idFromReminderId(String reminderId) {
    final parsed = int.tryParse(reminderId);
    final raw = parsed ?? reminderId.hashCode;
    return raw & 0x7FFFFFFF;
  }
}
