import 'dart:developer' as developer;

import 'package:device_calendar/device_calendar.dart' as dc;
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/reminder.dart';

/// Result of [CalendarService.addReminder]. Carries enough detail for
/// the UI to show a meaningful SnackBar instead of a generic "已取消".
enum CalendarAddResult {
  success,
  noCalendars,
  noWritableCalendar,
  writeFailed,
}

/// Thin wrapper around the `device_calendar` plugin so the rest of the
/// app talks to a single [CalendarService] surface, mirroring how
/// [NotificationService] wraps `flutter_local_notifications`.
class CalendarService {
  final dc.DeviceCalendarPlugin _plugin = dc.DeviceCalendarPlugin();

  /// Tracks whether the `timezone` package's location database has been
  /// initialised in this isolate. The `timezone` package exposes no
  /// public "is initialised" predicate, so we record the first call
  /// ourselves. [NotificationService.init] flips it during the normal
  /// cold-start path; [addReminder] flips it on the rare hot-reload /
  /// test path where that init was skipped.
  static bool _timezonesReady = false;

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
  /// Returns a [CalendarAddResult] indicating success or the specific
  /// reason the write failed.
  Future<CalendarAddResult> addReminder(Reminder reminder) async {
    _ensureTimezoneReady();

    final calResult = await _plugin.retrieveCalendars();
    if (!calResult.isSuccess || calResult.data == null) {
      developer.log(
        'retrieveCalendars failed: '
        'isSuccess=${calResult.isSuccess}, errors=${calResult.errors}',
        name: 'CalendarService',
      );
      return CalendarAddResult.writeFailed;
    }
    final calendars = calResult.data!;
    developer.log(
      'retrieved ${calendars.length} calendar(s)',
      name: 'CalendarService',
    );
    if (calendars.isEmpty) return CalendarAddResult.noCalendars;

    final writable = calendars.where((c) => c.isReadOnly == false).toList();
    if (writable.isEmpty) {
      developer.log(
        'no writable calendar among ${calendars.length} entries',
        name: 'CalendarService',
      );
      return CalendarAddResult.noWritableCalendar;
    }

    final cal = writable.firstWhere(
      (c) => c.isDefault == true,
      orElse: () => writable.first,
    );
    final calId = cal.id;
    developer.log(
      'selected calendar id=$calId, name=${cal.name}, '
      'isDefault=${cal.isDefault}, isReadOnly=${cal.isReadOnly}',
      name: 'CalendarService',
    );
    if (calId == null) {
      // Some Android accounts expose a calendar with id=null until the
      // first sync finishes; device_calendar would throw later.
      return CalendarAddResult.noWritableCalendar;
    }

    final location = tz.local;
    final start = tz.TZDateTime.from(reminder.reminderTime, location);
    final end = start.add(_defaultDuration);
    final event = dc.Event(
      calId,
      title: reminder.title,
      description: reminder.description,
      start: start,
      end: end,
      reminders: [dc.Reminder(minutes: _iosReminder.inMinutes)],
    );
    final createResult = await _plugin.createOrUpdateEvent(event);
    developer.log(
      'createOrUpdateEvent: isSuccess=${createResult?.isSuccess}, '
      'errors=${createResult?.errors}',
      name: 'CalendarService',
    );
    if (createResult?.isSuccess == true && createResult?.data != null) {
      return CalendarAddResult.success;
    }
    return CalendarAddResult.writeFailed;
  }

  /// Makes sure the `timezone` database is loaded and `tz.local` points
  /// somewhere valid. [NotificationService.init] already does this for
  /// the cold-start path, but tests and hot-reload may skip that.
  void _ensureTimezoneReady() {
    if (_timezonesReady) return;
    try {
      tz_data.initializeTimeZones();
      tz.setLocalLocation(tz.UTC);
      _timezonesReady = true;
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Failed to initialise timezone database',
        error: error,
        stackTrace: stackTrace,
        name: 'CalendarService',
      );
      tz.setLocalLocation(tz.UTC);
    }
  }
}