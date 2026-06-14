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
///
/// Soft-deleted reminders are kept in the database for [trashRetention]
/// so the user can restore them from the trash page. Rows past that
/// window are purged permanently along with their image files.
class RemindersViewModel extends ChangeNotifier {
  RemindersViewModel(
    this._repository,
    this._notifications,
    this._settings,
    this._imageStore,
  ) {
    _bootstrap();
  }

  /// How long a soft-deleted reminder stays in the trash before the
  /// next purge sweep removes it permanently. Hard-coded for now;
  /// promoting it to a user-facing setting is on the roadmap but
  /// intentionally out of scope for v1.3.0.
  static const Duration trashRetention = Duration(days: 30);

  final ReminderRepository _repository;
  final NotificationService _notifications;
  final SettingsViewModel _settings;
  final InspirationImageStore _imageStore;
  final List<Reminder> _reminders = <Reminder>[];

  /// Cached trash count, kept in sync with every soft-delete / restore /
  /// purge. Surfaced by the data-settings tile and the trash page
  /// header. Updated through [notifyListeners] on every change.
  int _trashCount = 0;

  bool _loaded = false;
  bool get isLoaded => _loaded;

  /// Invoked (on the next event-loop tick after the timer fires) when a
  /// reminder reaches its exact [Reminder.reminderTime] while the app is
  /// running. Set by [main] to show an in-app popup.
  void Function(Reminder)? onReminderDue;

  Timer? _nearestTimer;

  /// Unmodifiable view of the current list of active (non-trashed)
  /// reminders.
  List<Reminder> get reminders => List.unmodifiable(_reminders);

  /// Number of reminders currently in the trash. Cheap read; the
  /// underlying value is refreshed by every mutating call so consumers
  /// that listen on the same `ChangeNotifier` get live updates.
  int get trashCount => _trashCount;

  @override
  void dispose() {
    _cancelNearestTimer();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final loaded = await _repository.getAllActive();
    _trashCount = await _repository.countTrash();
    _reminders
      ..clear()
      ..addAll(loaded);
    _loaded = true;
    notifyListeners();
    // Re-arm any future reminders. Covers the case where the OS dropped
    // scheduled alarms (e.g. Android after device reboot).
    await _rescheduleAll();
    _scheduleNearestTimer();
    // Honour the user's auto-delete preference and the 30-day trash
    // retention on cold start so stale rows don't accumulate forever.
    await _purgeTrashAndExpired();
  }

  /// Reloads the in-memory list from the database. Used by the data
  /// management subpage after bulk imports or clears so the UI mirrors
  /// the on-disk state without restarting the app.
  Future<void> refresh() => _bootstrap();

  /// Refreshes the cached trash count without touching the active
  /// reminder list. Cheaper than [refresh] for surfaces that only
  /// care about the trash tile / page (e.g. the data settings page
  /// when returning from the trash page).
  Future<void> refreshTrashCount() async {
    _trashCount = await _repository.countTrash();
    notifyListeners();
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

  /// Soft-deletes a reminder. The row is kept in the database for
  /// [trashRetention] so the user can restore it from the trash page;
  /// the scheduled notification (if any) is cancelled immediately so
  /// the user does not get notified for something they just deleted.
  /// The on-disk image is **not** removed — the permanent-delete
  /// path handles image cleanup so a restore keeps the picture.
  Future<void> softDelete(String id, {DateTime? now}) async {
    final index = _reminders.indexWhere((r) => r.id == id);
    if (index == -1) {
      return;
    }
    final reminder = _reminders[index];
    final deleted = reminder.copyWith(
      isDeleted: true,
      deletedAt: now ?? DateTime.now(),
    );
    _reminders[index] = deleted;
    await _repository.softDelete(id, deleted.deletedAt!);
    _trashCount += 1;
    notifyListeners();
    try {
      await _notifications.cancelReminder(id);
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Failed to cancel notification during soft delete',
        error: error,
        stackTrace: stackTrace,
      );
    }
    _scheduleNearestTimer();
  }

  /// Restores a trashed reminder back to the active list. Re-arms the
  /// OS notification if the reminder's fire time is still in the
  /// future; past-due reminders stay visible but skip the
  /// notification schedule (the next 24h auto-delete sweep will pick
  /// them up if the user has that preference on).
  Future<void> restore(String id) async {
    // Refresh from the database in case the in-memory cache is stale
    // (e.g. the user re-launched the app while a trashed row existed).
    final trashed = await _repository.getAllTrash();
    final original = trashed.where((r) => r.id == id).firstOrNull;
    if (original == null) {
      // Fall back to a minimal restore if the row vanished (e.g. it
      // was purged between page-open and tap).
      return;
    }
    final restored = original.copyWith(isDeleted: false, clearDeletedAt: true);
    _reminders.insert(0, restored);
    // Keep the existing sort (newest created first) stable; resorting
    // would only matter for the top of the list and the user just
    // re-created the row, so a leading position is acceptable.
    await _repository.restore(id);
    _trashCount = (_trashCount - 1).clamp(0, 1 << 30);
    notifyListeners();
    if (restored.reminderTime.isAfter(DateTime.now())) {
      await _safeSchedule(restored);
    }
    _scheduleNearestTimer();
  }

  /// Moves every active reminder to the trash in one pass. Used by
  /// the data-settings "全部移入回收站" action. The OS notification for
  /// each row is cancelled; image files are left in place so a
  /// subsequent "全部恢复" brings everything back intact.
  ///
  /// Returns the number of reminders that were moved.
  Future<int> clearAllToTrash() async {
    if (_reminders.isEmpty) return 0;
    final now = DateTime.now();
    final toTrash = List<Reminder>.from(_reminders);
    for (final r in toTrash) {
      final stamped = r.copyWith(isDeleted: true, deletedAt: now);
      final i = _reminders.indexWhere((e) => e.id == r.id);
      if (i != -1) _reminders[i] = stamped;
      await _repository.softDelete(r.id, now);
      try {
        await _notifications.cancelReminder(r.id);
      } on Exception catch (error, stackTrace) {
        developer.log(
          'Failed to cancel notification during clearAllToTrash',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
    _trashCount += toTrash.length;
    notifyListeners();
    _scheduleNearestTimer();
    return toTrash.length;
  }

  /// Permanently removes every trashed reminder. Used by the trash
  /// page's "永久删除" action. Image files are deleted from disk; the
  /// OS notification cancel is a no-op (soft delete already cancelled
  /// them).
  ///
  /// Returns the number of reminders actually removed.
  Future<int> purgeTrash() async {
    final trashed = await _repository.getAllTrash();
    if (trashed.isEmpty) return 0;
    for (final r in trashed) {
      await _repository.permanentDelete(r.id);
      final imagePath = r.imagePath;
      if (imagePath != null) {
        try {
          await _imageStore.deleteByPath(imagePath);
        } on Exception catch (error, stackTrace) {
          developer.log(
            'Failed to delete trashed reminder image',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }
    }
    _trashCount = 0;
    notifyListeners();
    return trashed.length;
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

  /// Combined sweep that runs on cold start and on every foreground
  /// resume:
  ///   1. Permanently deletes trashed rows older than [trashRetention]
  ///      and the associated image files.
  ///   2. When the user has `autoDeleteAfter24h` enabled, permanently
  ///      deletes active rows whose fire time is more than 24 h in the
  ///      past.
  ///
  /// The two passes are independent: a row that was soft-deleted 30
  /// days ago is purged regardless of the auto-delete setting, and
  /// vice versa. Both passes update the in-memory cache and emit
  /// `notifyListeners` exactly once at the end.
  Future<void> _purgeTrashAndExpired() async {
    final trashCutoff = DateTime.now().subtract(trashRetention);
    final purgedTrashImages = await _repository.purgeTrashOlderThan(
      trashCutoff,
    );
    for (final imagePath in purgedTrashImages) {
      if (imagePath == null) continue;
      try {
        await _imageStore.deleteByPath(imagePath);
      } on Exception catch (error, stackTrace) {
        developer.log(
          'Failed to delete trashed reminder image during purge',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
    final trashPurged = purgedTrashImages.isNotEmpty;

    if (!_settings.settings.autoDeleteAfter24h) {
      if (trashPurged) {
        _trashCount = await _repository.countTrash();
        notifyListeners();
      }
      return;
    }

    final now = DateTime.now();
    final expired = _reminders
        .where(
          (r) => r.reminderTime.add(const Duration(hours: 24)).isBefore(now),
        )
        .toList();
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
      await _repository.permanentDelete(reminder.id);
    }
    _reminders.removeWhere((r) => expired.any((e) => e.id == r.id));
    if (trashPurged || expired.isNotEmpty) {
      if (trashPurged) {
        _trashCount = await _repository.countTrash();
      }
      notifyListeners();
    }
    _scheduleNearestTimer();
  }

  /// Public hook so the app's lifecycle observer can trigger a purge on
  /// every foreground resume without exposing the private method.
  Future<void> onAppResumed() => _purgeTrashAndExpired();

  /// Removes every active reminder, cancels its scheduled notification,
  /// and deletes the associated image file (if any). Used by the data
  /// management subpage for bulk clear. Returns the number of
  /// reminders actually removed. Trashed rows are intentionally
  /// untouched — the user has already moved them aside.
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
