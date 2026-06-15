import 'package:device_calendar/device_calendar.dart' as dc;
import 'package:timezone/timezone.dart' as tz;

import '../models/reminder.dart';

/// Thin wrapper around the `device_calendar` plugin so the rest of the
/// app talks to a single [CalendarService] surface, mirroring how
/// [NotificationService] wraps `flutter_local_notifications`.
class CalendarService {
  final dc.DeviceCalendarPlugin _plugin = dc.DeviceCalendarPlugin();

  /// Default duration applied to events that don't carry an explicit
  /// end time. The user can adjust in the system calendar after
  /// creation.
  static const Duration _defaultDuration = Duration(minutes: 30);

  /// Default pre-event alert on iOS. Lets the user get a system-level
  /// notification even if our app's own reminder hasn't fired yet.
  static const Duration _iosReminder = Duration(minutes: 10);

  /// Asks the OS for READ + WRITE calendar permissions. Returns `true`
  /// when granted. Mirrors [NotificationService.requestPermissions]'s
  /// `Future<bool>` shape so the UI layer can branch identically.
  Future<bool> requestPermissions() async {
    final has = await _plugin.hasPermissions();
    if (has.isSuccess && has.data == true) return true;
    final req = await _plugin.requestPermissions();
    return req.isSuccess && req.data == true;
  }

  /// Writes [reminder] to the user's first writable system calendar.
  ///
  /// Returns `true` if the OS confirmed the event was created, `false`
  /// on permission denial, no-calendar-found, or a write error.
  Future<bool> addReminder(Reminder reminder) async {
    final calResult = await _plugin.retrieveCalendars();
    if (!calResult.isSuccess || calResult.data == null) return false;
    final calendars = calResult.data!;
    if (calendars.isEmpty) return false;

    // Prefer the user's default writable calendar; fall back to any
    // writable one; last resort: first calendar (the write call will
    // surface a clean error if it is read-only).
    final cal = calendars.firstWhere(
      (c) => c.isReadOnly == false && c.isDefault == true,
      orElse: () => calendars.firstWhere(
        (c) => c.isReadOnly == false,
        orElse: () => calendars.first,
      ),
    );

    final location = tz.local;
    final start = tz.TZDateTime.from(reminder.reminderTime, location);
    final end = start.add(_defaultDuration);
    final event = dc.Event(
      cal.id,
      title: reminder.title,
      description: reminder.description,
      start: start,
      end: end,
      reminders: [dc.Reminder(minutes: _iosReminder.inMinutes)],
    );
    final createResult = await _plugin.createOrUpdateEvent(event);
    return createResult?.isSuccess == true && createResult?.data != null;
  }
}