import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'package:nousmind/models/app_settings.dart';
import 'package:nousmind/models/reminder.dart';

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

  /// Identifier of the snooze action button attached to every reminder
  /// notification. The label is templated with the user's current
  /// snooze duration at schedule time (see [snoozeActionLabel]).
  static const String kSnoozeActionId = 'snooze';

  /// Identifier of the "complete" action button — fires
  /// [NotificationAction.complete] when pressed, which the host wires
  /// to a delete-on-complete semantics (matching the existing 24h
  /// auto-delete behaviour).
  static const String kCompleteActionId = 'complete';

  /// Used by [showImmediate] so repeated taps overwrite the previous test
  /// notification instead of stacking up in the tray.
  static const int _immediateNotificationId = 0;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// Body-tap callback. Set by [init]. The cold-start path stores
  /// the same handler so taps from a freshly-launched app still reach
  /// the router.
  void Function()? _onTapBody;

  /// Action-button callback. Set by [init]. The action ID and payload
  /// are forwarded verbatim; the host looks up the [Reminder] from
  /// `response.payload` and dispatches to the right view-model call.
  void Function(NotificationResponse response)? _onAction;

  /// Boots the plugin and the timezone database.
  ///
  /// [onTapBody] fires whenever the user activates the body of a
  /// notification — either while the app is running or as a
  /// cold-start launch from a tap. Callers typically wire this to
  /// `router.go('/')` to surface the reminders tab.
  ///
  /// [onAction] is called when the user presses a snooze / complete
  /// action button on the notification while the app is in the
  /// foreground or as a cold-start launch. The action ID and payload
  /// are forwarded verbatim; the host is expected to look up the
  /// [Reminder] from `response.payload` and dispatch to the right
  /// view-model call. The background isolate path is handled by
  /// [_handleBackgroundResponse] which only logs.
  Future<void> init({
    required void Function() onTapBody,
    void Function(NotificationResponse response)? onAction,
  }) async {
    if (_initialized) {
      return;
    }
    _initialized = true;
    _onTapBody = onTapBody;
    _onAction = onAction;

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
    final darwinInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
      notificationCategories: <DarwinNotificationCategory>[
        DarwinNotificationCategory(
          'reminder_action',
          actions: <DarwinNotificationAction>[
            DarwinNotificationAction.plain(
              kSnoozeActionId,
              '稍后提醒',
              options: <DarwinNotificationActionOption>{
                DarwinNotificationActionOption.foreground,
              },
            ),
            DarwinNotificationAction.plain(
              kCompleteActionId,
              '完成',
              options: <DarwinNotificationActionOption>{
                DarwinNotificationActionOption.destructive,
                DarwinNotificationActionOption.foreground,
              },
            ),
          ],
        ),
      ],
    );
    await _plugin.initialize(
      settings: InitializationSettings(android: androidInit, iOS: darwinInit),
      onDidReceiveNotificationResponse: _handleForegroundResponse,
      onDidReceiveBackgroundNotificationResponse: _handleBackgroundResponse,
    );

    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp ?? false) {
      final response = launchDetails!.notificationResponse;
      if (response?.actionId == null) {
        _onTapBody?.call();
      } else {
        _onAction?.call(response!);
      }
    }
  }

  void _handleForegroundResponse(NotificationResponse response) {
    final action = response.actionId;
    if (action == null) {
      _onTapBody?.call();
      return;
    }
    _onAction?.call(response);
  }

  /// Top-level entry point used by `flutter_local_notifications` when a
  /// background notification action arrives. Required to be a static /
  /// top-level function (no closures) and runs in a separate isolate
  /// where the widget tree and view models are unavailable. The
  /// real work is forwarded to the foreground handler on the next
  /// launch; for now we just log so the user can see the action was
  /// received if they inspect the OS notification log.
  @pragma('vm:entry-point')
  static void _handleBackgroundResponse(NotificationResponse response) {
    developer.log(
      'Background notification action: '
      'actionId=${response.actionId}, payload=${response.payload}',
    );
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
  /// * [snoozeActionLabel] — text shown on the snooze action button
  ///   (e.g. "稍后提醒（10 分钟）"). The caller computes this from
  ///   `AppSettings.snoozeDuration` so the service stays free of any
  ///   settings coupling. Defaults to a generic "稍后提醒" if omitted.
  ///
  /// Silently no-ops when the final trigger time is still in the past —
  /// the reminder is still saved, but no notification will fire.
  Future<void> scheduleReminder(
    Reminder reminder, {
    bool vibrationEnabled = true,
    QuietHoursWindow? quietHours,
    String snoozeActionLabel = '稍后提醒',
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
    final body = _composeBody(reminder);
    await _plugin.zonedSchedule(
      id: _idFromReminderId(reminder.id),
      title: reminder.title,
      body: body,
      scheduledDate: tzTarget,
      payload: reminder.id,
      notificationDetails: _details(
        vibrationEnabled: vibrationEnabled,
        body: body,
        snoozeActionLabel: snoozeActionLabel,
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  /// Body text for a scheduled reminder. Prefers the user-supplied
  /// description (rendered as expandable BigText on Android) and
  /// falls back to a generic suffix when none is set.
  String _composeBody(Reminder reminder) {
    final description = reminder.description?.trim();
    if (description != null && description.isNotEmpty) {
      return description;
    }
    return _bodySuffix;
  }

  /// Cancels the scheduled notification for [reminderId] (if any).
  Future<void> cancelReminder(String reminderId) async {
    await _plugin.cancel(id: _idFromReminderId(reminderId));
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
      id: _immediateNotificationId,
      title: title,
      body: body,
      notificationDetails: _details(
        vibrationEnabled: vibrationEnabled,
        body: body,
      ),
    );
  }

  NotificationDetails _details({
    required bool vibrationEnabled,
    String? body,
    String snoozeActionLabel = '稍后提醒',
  }) {
    final hasBody = body != null && body.isNotEmpty;
    return NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.max,
        priority: Priority.high,
        ticker: '提醒',
        enableVibration: vibrationEnabled,
        styleInformation: hasBody
            ? BigTextStyleInformation(
                body,
                contentTitle: null,
                summaryText: null,
              )
            : null,
        actions: <AndroidNotificationAction>[
          AndroidNotificationAction(
            kSnoozeActionId,
            snoozeActionLabel,
            showsUserInterface: false,
            cancelNotification: true,
          ),
          AndroidNotificationAction(
            kCompleteActionId,
            '完成',
            showsUserInterface: false,
            cancelNotification: true,
          ),
        ],
        category: AndroidNotificationCategory.reminder,
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        categoryIdentifier: 'reminder_action',
      ),
    );
  }

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
