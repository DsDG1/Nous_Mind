import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import '../models/reminder.dart';
import '../services/notification_service.dart';
import '../services/reminder_storage.dart';
import 'settings_view_model.dart';

/// Holds the in-memory list of reminders, persists every change, and keeps
/// the OS-level scheduled notifications in sync.
///
/// The view model exposes an immutable view via [reminders] and notifies
/// listeners after each mutation. Storage writes are awaited so that the
/// on-disk state matches the in-memory state when the call returns.
/// Notification scheduling is best-effort — failures are logged but never
/// thrown, so a missing permission does not break the in-memory flow.
class RemindersViewModel extends ChangeNotifier {
  RemindersViewModel(this._storage, this._notifications, this._settings) {
    _bootstrap();
  }

  final ReminderStorage _storage;
  final NotificationService _notifications;
  final SettingsViewModel _settings;
  final List<Reminder> _reminders = <Reminder>[];

  bool _loaded = false;
  bool get isLoaded => _loaded;

  /// Unmodifiable view of the current list.
  List<Reminder> get reminders => List.unmodifiable(_reminders);

  Future<void> _bootstrap() async {
    final loaded = await _storage.loadAll();
    _reminders
      ..clear()
      ..addAll(loaded);
    _loaded = true;
    notifyListeners();
    // Re-arm any future reminders. Covers the case where the OS dropped
    // scheduled alarms (e.g. Android after device reboot).
    await _rescheduleAll();
  }

  Future<void> _rescheduleAll() async {
    final now = DateTime.now();
    for (final reminder in _reminders) {
      if (reminder.reminderTime.isAfter(now)) {
        await _safeSchedule(reminder);
      }
    }
  }

  /// Appends a new reminder to the end of the list and persists it.
  Future<void> add({
    required String title,
    required DateTime reminderTime,
  }) async {
    final reminder = Reminder(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: title,
      reminderTime: reminderTime,
    );
    _reminders.add(reminder);
    await _storage.saveAll(_reminders);
    notifyListeners();
    await _notifications.requestPermissions();
    await _safeSchedule(reminder);
  }

  /// Replaces the reminder with the same [Reminder.id] and persists the list.
  Future<void> update(Reminder reminder) async {
    final index = _reminders.indexWhere((r) => r.id == reminder.id);
    if (index == -1) {
      return;
    }
    _reminders[index] = reminder;
    await _storage.saveAll(_reminders);
    notifyListeners();
    await _notifications.cancelReminder(reminder.id);
    await _safeSchedule(reminder);
  }

  /// Removes the reminder with [id] from the list and persists the change.
  Future<void> delete(String id) async {
    final removed = _reminders.length;
    _reminders.removeWhere((r) => r.id == id);
    if (_reminders.length == removed) {
      return;
    }
    await _storage.saveAll(_reminders);
    notifyListeners();
    await _notifications.cancelReminder(id);
  }

  /// Wraps [NotificationService.scheduleReminder] so that a permission
  /// denial or other platform error never escapes the view model. Reminders
  /// are stored regardless of whether the notification was scheduled.
  ///
  /// The current user preferences are read at schedule time, so toggling
  /// settings before adding a reminder is honoured immediately.
  Future<void> _safeSchedule(Reminder reminder) async {
    final prefs = _settings.settings;
    try {
      await _notifications.scheduleReminder(
        reminder,
        leadTime: prefs.leadTime.duration,
        vibrationEnabled: prefs.vibrationEnabled,
        quietHours: prefs.quietHoursEnabled ? prefs.quietHours : null,
      );
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Failed to schedule reminder notification',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
