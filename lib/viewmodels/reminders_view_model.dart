import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import '../models/reminder.dart';
import '../services/inspiration_image_store.dart';
import '../services/notification_service.dart';
import '../services/reminder_repository.dart';
import 'settings_view_model.dart';

/// Holds the in-memory list of reminders, persists every change, and keeps
/// the OS-level scheduled notifications in sync.
///
/// The view model exposes an immutable view via [reminders] and notifies
/// listeners after each mutation. Storage writes are awaited so that the
/// on-disk state matches the in-memory state when the call returns.
/// Notification scheduling is best-effort — failures are logged but never
/// thrown, so a missing permission does not break the in-memory flow.
///
/// When [onReminderDue] is set, the view model tracks the nearest upcoming
/// reminder via an internal timer and fires the callback at the exact
/// [Reminder.reminderTime]. This is used to show an in-app popup regardless
/// of which tab is active.
class RemindersViewModel extends ChangeNotifier {
  RemindersViewModel(
    this._repository,
    this._notifications,
    this._settings,
    this._imageStore,
  ) {
    _bootstrap();
  }

  final ReminderRepository _repository;
  final NotificationService _notifications;
  final SettingsViewModel _settings;
  final InspirationImageStore _imageStore;
  final List<Reminder> _reminders = <Reminder>[];

  bool _loaded = false;
  bool get isLoaded => _loaded;

  /// Invoked (on the next event-loop tick after the timer fires) when a
  /// reminder reaches its exact [Reminder.reminderTime] while the app is
  /// running. Set by [main] to show an in-app popup.
  void Function(Reminder)? onReminderDue;

  Timer? _nearestTimer;

  /// Unmodifiable view of the current list.
  List<Reminder> get reminders => List.unmodifiable(_reminders);

  @override
  void dispose() {
    _cancelNearestTimer();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final loaded = await _repository.getAll();
    _reminders
      ..clear()
      ..addAll(loaded);
    _loaded = true;
    notifyListeners();
    // Re-arm any future reminders. Covers the case where the OS dropped
    // scheduled alarms (e.g. Android after device reboot).
    await _rescheduleAll();
    _scheduleNearestTimer();
    // Honour the user's auto-delete preference on cold start so past-due
    // reminders from a previous session don't accumulate forever.
    await _purgeExpiredReminders();
  }

  /// Reloads the in-memory list from the database. Used by the data
  /// management subpage after bulk imports or clears so the UI mirrors
  /// the on-disk state without restarting the app.
  Future<void> refresh() => _bootstrap();

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
    String? imagePath,
    String? description,
  }) async {
    final reminder = Reminder(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: title,
      reminderTime: reminderTime,
      imagePath: imagePath,
      description: description,
    );
    _reminders.add(reminder);
    await _repository.insert(reminder);
    notifyListeners();
    await _notifications.requestPermissions();
    await _safeSchedule(reminder);
    _scheduleNearestTimer();
  }

  /// Replaces the reminder with the same [Reminder.id] and persists it.
  Future<void> update(Reminder reminder) async {
    final index = _reminders.indexWhere((r) => r.id == reminder.id);
    if (index == -1) {
      return;
    }
    _reminders[index] = reminder;
    await _repository.update(reminder);
    notifyListeners();
    await _notifications.cancelReminder(reminder.id);
    await _safeSchedule(reminder);
    _scheduleNearestTimer();
  }

  /// Removes the reminder with [id] from the list and persists the change.
  /// Also deletes the associated image file if present.
  Future<void> delete(String id) async {
    final index = _reminders.indexWhere((r) => r.id == id);
    if (index == -1) {
      return;
    }
    final imagePath = _reminders[index].imagePath;
    _reminders.removeAt(index);
    await _repository.delete(id);
    notifyListeners();
    await _notifications.cancelReminder(id);
    _scheduleNearestTimer();
    if (imagePath != null) {
      await _imageStore.deleteByPath(imagePath);
    }
  }

  /// Wraps [NotificationService.scheduleReminder] so that a permission
  /// denial or other platform error never escapes the view model. Reminders
  /// are stored regardless of whether the notification was scheduled.
  ///
  /// The current user preferences are read at schedule time, so toggling
  /// settings before adding a reminder is honoured immediately. The snooze
  /// action label is templated against the user's current
  /// [SnoozeDuration] so the in-shade button always matches the actual
  /// snooze the app will apply.
  Future<void> _safeSchedule(Reminder reminder) async {
    final prefs = _settings.settings;
    try {
      await _notifications.scheduleReminder(
        reminder,
        vibrationEnabled: prefs.vibrationEnabled,
        quietHours: prefs.quietHoursEnabled ? prefs.quietHours : null,
        snoozeActionLabel: '稍后提醒（${prefs.snoozeDuration.label}）',
      );
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Failed to schedule reminder notification',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Pushes the reminder's time forward by [duration] and re-schedules
  /// both the system notification and the in-app due timer.
  Future<void> snoozeReminder(String id, Duration duration) async {
    final index = _reminders.indexWhere((r) => r.id == id);
    if (index == -1) {
      return;
    }
    final reminder = _reminders[index];
    final snoozed = reminder.copyWith(
      reminderTime: DateTime.now().add(duration),
    );
    _reminders[index] = snoozed;
    await _repository.update(snoozed);
    notifyListeners();
    await _notifications.cancelReminder(id);
    await _safeSchedule(snoozed);
    _scheduleNearestTimer();
  }

  /// Removes reminders whose scheduled time is more than 24 hours in the
  /// past, but only when the user has opted in via [AppSettings].
  /// Anchored to [Reminder.reminderTime] — snoozing a reminder refreshes
  /// `reminderTime` and therefore extends the 24-hour window naturally.
  Future<void> _purgeExpiredReminders() async {
    if (!_settings.settings.autoDeleteAfter24h) {
      return;
    }
    final now = DateTime.now();
    final expired = _reminders
        .where(
          (r) => r.reminderTime.add(const Duration(hours: 24)).isBefore(now),
        )
        .toList();
    if (expired.isEmpty) {
      return;
    }
    for (final reminder in expired) {
      try {
        await _notifications.cancelReminder(reminder.id);
      } on Exception catch (error, stackTrace) {
        developer.log(
          'Failed to cancel notification during purge',
          error: error,
          stackTrace: stackTrace,
        );
      }
      final imagePath = reminder.imagePath;
      if (imagePath != null) {
        try {
          await _imageStore.deleteByPath(imagePath);
        } on Exception catch (error, stackTrace) {
          developer.log(
            'Failed to delete reminder image during purge',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }
      await _repository.delete(reminder.id);
    }
    _reminders.removeWhere((r) => expired.any((e) => e.id == r.id));
    notifyListeners();
    _scheduleNearestTimer();
  }

  /// Public hook so the app's lifecycle observer can trigger a purge on
  /// every foreground resume without exposing the private method.
  Future<void> onAppResumed() => _purgeExpiredReminders();

  /// Removes every reminder, cancels its scheduled notification, and
  /// deletes the associated image file (if any). Used by the data
  /// management subpage for bulk clear. Returns the number of
  /// reminders actually removed.
  Future<int> clearAll() async {
    final all = List<Reminder>.from(_reminders);
    for (final reminder in all) {
      try {
        await _notifications.cancelReminder(reminder.id);
      } on Exception catch (error, stackTrace) {
        developer.log(
          'Failed to cancel notification during clearAll',
          error: error,
          stackTrace: stackTrace,
        );
      }
      final imagePath = reminder.imagePath;
      if (imagePath != null) {
        try {
          await _imageStore.deleteByPath(imagePath);
        } on Exception catch (error, stackTrace) {
          developer.log(
            'Failed to delete reminder image during clearAll',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }
    }
    final removed = await _repository.clearAll();
    _reminders.clear();
    notifyListeners();
    _scheduleNearestTimer();
    return removed;
  }

  /// Bulk-add helper used by the AI assistant flow. All drafts land in
  /// the list, each OS notification is scheduled, then a single batch
  /// insert keeps the persistence path efficient.
  ///
  /// Returns the number of reminders actually added.
  Future<int> addMultiple(
    List<({String title, DateTime reminderTime, String? description})> drafts,
  ) async {
    if (drafts.isEmpty) return 0;
    final baseId = DateTime.now().microsecondsSinceEpoch;
    final newcomers = <Reminder>[];
    for (var i = 0; i < drafts.length; i++) {
      final draft = drafts[i];
      final reminder = Reminder(
        id: '$baseId-$i',
        title: draft.title,
        reminderTime: draft.reminderTime,
        description: draft.description,
      );
      _reminders.add(reminder);
      newcomers.add(reminder);
      await _safeSchedule(reminder);
    }
    await _repository.insertAll(newcomers);
    notifyListeners();
    _scheduleNearestTimer();
    return drafts.length;
  }

  // ---- In-app due-timer helpers --------------------------------

  void _cancelNearestTimer() {
    _nearestTimer?.cancel();
    _nearestTimer = null;
  }

  /// Finds the nearest future [Reminder.reminderTime] and arms a one-shot
  /// [Timer] to fire at that instant. Timer is best-effort; on some
  /// platforms (Android Doze) the callback may be delayed.
  void _scheduleNearestTimer() {
    _cancelNearestTimer();
    final now = DateTime.now();
    Reminder? nearest;
    for (final reminder in _reminders) {
      if (reminder.reminderTime.isAfter(now)) {
        if (nearest == null ||
            reminder.reminderTime.isBefore(nearest.reminderTime)) {
          nearest = reminder;
        }
      }
    }
    if (nearest == null) {
      return;
    }
    final delay = nearest.reminderTime.difference(now);
    if (delay <= Duration.zero) {
      return;
    }
    _nearestTimer = Timer(delay, () => _onNearestDue(nearest!));
  }

  void _onNearestDue(Reminder reminder) {
    onReminderDue?.call(reminder);
    _scheduleNearestTimer();
  }
}
