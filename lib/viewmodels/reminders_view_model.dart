import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import 'package:nousmind/models/reminder.dart';
import 'package:nousmind/models/tag.dart';
import 'package:nousmind/services/inspiration_image_store.dart';
import 'package:nousmind/services/nearest_reminder_timer.dart';
import 'package:nousmind/services/notification_service.dart';
import 'package:nousmind/services/reminder_cleanup_service.dart';
import 'package:nousmind/services/reminder_repository.dart';
import 'package:nousmind/viewmodels/settings_view_model.dart';

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
/// reminder via an internal [_NearestReminderTimer] and fires the callback
/// at the exact [Reminder.reminderTime]. This is used to show an in-app
/// popup regardless of which tab is active.
///
/// Soft-deleted reminders are kept in the database for
/// [ReminderRepository.trashRetention] so the user can restore them from
/// the trash page. Rows past that window are purged permanently along
/// with their image files by [ReminderCleanupService].
class RemindersViewModel extends ChangeNotifier {
  RemindersViewModel(
    this._repository,
    this._notifications,
    this._settings,
    this._imageStore,
    this._cleanup,
  ) {
    // Built in the body (not the initializer list) because the timer's
    // `onDue` closure reads the instance field `onReminderDue`, which
    // is not yet accessible from an initializer. The closure captures
    // `this` by reference, so any later assignment to `onReminderDue`
    // is honoured without rebuilding the timer.
    _timer = NearestReminderTimer(
      onDue: (reminder) => onReminderDue?.call(reminder),
    );
    _bootstrap();
  }

  final ReminderRepository _repository;
  final NotificationService _notifications;
  final SettingsViewModel _settings;
  final InspirationImageStore _imageStore;
  final ReminderCleanupService _cleanup;
  late final NearestReminderTimer _timer;
  final List<Reminder> _reminders = <Reminder>[];

  /// Cached trash count, kept in sync with every soft-delete / restore /
  /// purge. Surfaced by the data-settings tile and the trash page
  /// header. Updated through [notifyListeners] on every change.
  int _trashCount = 0;

  /// Currently-applied tag filter. `null` means "全部" (all). A
  /// non-null value is a [Tag.id]; the filter UI maps "已完成" to
  /// [kCompletedTagId] so a single selection covers both real
  /// tags and the pseudo-category. Survives hot reload and page
  /// rebuilds so the user can navigate away and back without
  /// losing the current filter.
  String? _selectedTagId;
  String? get selectedTagId => _selectedTagId;

  bool _loaded = false;
  bool get isLoaded => _loaded;

  /// Invoked (on the next event-loop tick after the timer fires) when a
  /// reminder reaches its exact [Reminder.reminderTime] while the app is
  /// running. Set by [main] to show an in-app popup.
  void Function(Reminder)? onReminderDue;

  /// Unmodifiable view of the current list of active (non-trashed)
  /// reminders, in `created_at DESC` order. Use [visibleReminders]
  /// from the home page so the active tag filter and the
  /// complete-to-bottom sort are applied.
  List<Reminder> get reminders => List.unmodifiable(_reminders);

  /// The list the home page should render. Applies the current
  /// [selectedTagId] filter, and — in the "全部" view — pushes
  /// completed rows to the bottom so the active reminders stay
  /// grouped above the done ones. The order is stable: within each
  /// bucket, items are sorted by `created_at DESC, id DESC` so
  /// concurrent adds (which share the same microsecond tick) do
  /// not flicker.
  List<Reminder> get visibleReminders {
    final filter = _selectedTagId;
    final base = filter == null
        ? List<Reminder>.of(_reminders)
        : _reminders.where((r) => r.tagId == filter).toList();
    int compareActiveFirst(Reminder a, Reminder b) {
      if (a.isCompleted != b.isCompleted) {
        return a.isCompleted ? 1 : -1;
      }
      final byCreated = b.createdAt.compareTo(a.createdAt);
      if (byCreated != 0) return byCreated;
      return b.id.compareTo(a.id);
    }

    base.sort(compareActiveFirst);
    return List.unmodifiable(base);
  }

  /// Number of reminders currently in the trash. Cheap read; the
  /// underlying value is refreshed by every mutating call so consumers
  /// that listen on the same `ChangeNotifier` get live updates.
  int get trashCount => _trashCount;

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _timer.dispose();
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
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
    _timer.schedule(_reminders);
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

  /// Fetches the trashed reminders from the database. Used by the
  /// trash page; intentionally not cached on the view model because
  /// the page is the only consumer and the list can be large.
  /// The cached [trashCount] is refreshed as a side effect so the
  /// data-settings tile does not show stale values while the user
  /// is on the trash page. Does not call [notifyListeners] because
  /// the trash page uses [FutureBuilder], not [Consumer].
  Future<List<Reminder>> refreshAndFetchTrash() async {
    final items = await _repository.getAllTrash();
    _trashCount = items.length;
    return items;
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
    String? tagId,
  }) async {
    final reminder = Reminder(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: title,
      reminderTime: reminderTime,
      imagePath: imagePath,
      description: description,
      tagId: tagId,
    );
    _reminders.add(reminder);
    await _repository.insert(reminder);
    notifyListeners();
    await _notifications.requestPermissions();
    await _safeSchedule(reminder);
    _timer.schedule(_reminders);
  }

  /// Replaces the reminder with the same [Reminder.id] and persists it.
  Future<void> update(Reminder reminder) async {
    final index = _reminders.indexWhere((r) => r.id == reminder.id);
    if (index == -1) {
      return;
    }
    _reminders[index] = reminder;
    notifyListeners();
    await _repository.update(reminder);
    await _notifications.cancelReminder(reminder.id);
    await _safeSchedule(reminder);
    _timer.schedule(_reminders);
  }

  /// Soft-deletes a reminder. The row is kept in the database for
  /// [ReminderRepository.trashRetention] so the user can restore it
  /// from the trash page; the scheduled notification (if any) is
  /// cancelled immediately so the user does not get notified for
  /// something they just deleted.
  /// The on-disk image is **not** removed — the permanent-delete
  /// path handles image cleanup so a restore keeps the picture.
  Future<void> softDelete(String id, {DateTime? now}) async {
    final index = _reminders.indexWhere((r) => r.id == id);
    if (index == -1) {
      return;
    }
    final deletedAt = now ?? DateTime.now();
    _reminders.removeAt(index);
    _trashCount += 1;
    // Notify before the DB write so the Consumer rebuilds in the same frame
    // as the Dismissible's onDismissed callback. Otherwise the await below
    // delays the rebuild past the framework's assertion check, producing
    // "A dismissed Dismissible widget is still part of the tree".
    notifyListeners();
    await _repository.softDelete(id, deletedAt);
    try {
      await _notifications.cancelReminder(id);
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Failed to cancel notification during soft delete',
        error: error,
        stackTrace: stackTrace,
      );
    }
    _timer.schedule(_reminders);
  }

  /// Restores a trashed reminder back to the active list. Re-arms the
  /// OS notification if the reminder's fire time is still in the
  /// future; past-due reminders stay visible but skip the
  /// notification schedule (the next 24h auto-delete sweep will pick
  /// them up if the user has that preference on).
  Future<void> restore(String id) async {
    final original = await _repository.findById(id);
    if (original == null) return;
    final restored = original.copyWith(isDeleted: false, clearDeletedAt: true);
    _reminders.removeWhere((r) => r.id == id);
    _reminders.insert(0, restored);
    _trashCount = (_trashCount - 1).clamp(0, 1 << 30);
    notifyListeners();
    await _repository.restore(id);
    if (restored.reminderTime.isAfter(DateTime.now())) {
      await _safeSchedule(restored);
    }
    _timer.schedule(_reminders);
  }

  /// Batch-restores multiple trashed reminders via a single SQL pass.
  /// Used by the trash page's "全部恢复" action and the data-settings
  /// "撤销" button so the UI does not freeze when restoring many items.
  Future<int> restoreAll(List<String> ids) async {
    if (ids.isEmpty) return 0;
    final trashed = await _repository.getAllTrash();
    final toRestore = <Reminder>[];
    for (final r in trashed) {
      if (ids.contains(r.id)) {
        toRestore.add(r.copyWith(isDeleted: false, clearDeletedAt: true));
      }
    }
    if (toRestore.isEmpty) return 0;
    _reminders.removeWhere((r) => ids.contains(r.id));
    _reminders.insertAll(0, toRestore);
    _trashCount = (_trashCount - toRestore.length).clamp(0, 1 << 30);
    notifyListeners();
    await _repository.restoreByIds(ids);
    final now = DateTime.now();
    await Future.wait(
      toRestore.where((r) => r.reminderTime.isAfter(now)).map(_safeSchedule),
    );
    _timer.schedule(_reminders);
    return toRestore.length;
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
    _reminders.clear();
    _trashCount += toTrash.length;
    notifyListeners();
    for (final r in toTrash) {
      await _repository.softDelete(r.id, now);
    }
    try {
      await Future.wait(
        toTrash.map((r) => _notifications.cancelReminder(r.id)),
      );
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Failed to cancel some notifications during clearAllToTrash',
        error: error,
        stackTrace: stackTrace,
      );
    }
    _timer.schedule(_reminders);
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
    final ids = trashed.map((r) => r.id).toList();
    await _repository.permanentDeleteByIds(ids);
    for (final r in trashed) {
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
    notifyListeners();
    await _repository.update(snoozed);
    await _notifications.cancelReminder(id);
    await _safeSchedule(snoozed);
    _timer.schedule(_reminders);
  }

  /// Combined sweep that runs on cold start and on every foreground
  /// resume. Delegates the actual purge work to [ReminderCleanupService]
  /// and only updates the view-model state when something actually
  /// changed:
  ///
  ///   * `_cleanup.purgeExpiredTrash` — returns the number of trashed
  ///     rows purged. If non-zero, refresh `_trashCount` so the
  ///     data-settings tile reflects the new total.
  ///   * `_cleanup.purgeExpiredActive` — returns the IDs of active
  ///     rows purged under the user's 24h auto-delete setting. Drop
  ///     those from `_reminders` and re-arm the in-app timer.
  ///
  /// `notifyListeners` is fired at most once at the end of the sweep.
  Future<void> _purgeTrashAndExpired() async {
    final purgedCount = await _cleanup.purgeExpiredTrash();
    if (purgedCount > 0) {
      _trashCount = await _repository.countTrash();
    }

    final expiredIds = await _cleanup.purgeExpiredActive(_reminders);
    if (expiredIds.isNotEmpty) {
      _reminders.removeWhere((r) => expiredIds.contains(r.id));
    }

    if (purgedCount > 0 || expiredIds.isNotEmpty) {
      notifyListeners();
    }
    _timer.schedule(_reminders);
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
    _reminders.clear();
    notifyListeners();
    try {
      await Future.wait(all.map((r) => _notifications.cancelReminder(r.id)));
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Failed to cancel some notifications during clearAll',
        error: error,
        stackTrace: stackTrace,
      );
    }
    for (final reminder in all) {
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
    _timer.schedule(_reminders);
    return removed;
  }

  /// Bulk-add helper used by the AI assistant flow. All drafts land in
  /// the list, each OS notification is scheduled, then a single batch
  /// insert keeps the persistence path efficient.
  ///
  /// Returns the number of reminders actually added.
  Future<int> addMultiple(
    List<
      ({
        String title,
        DateTime reminderTime,
        String? description,
        String? tagId,
      })
    >
    drafts,
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
        tagId: draft.tagId,
      );
      _reminders.add(reminder);
      newcomers.add(reminder);
      await _safeSchedule(reminder);
    }
    await _repository.insertAll(newcomers);
    notifyListeners();
    _timer.schedule(_reminders);
    return drafts.length;
  }

  /// Updates the active tag filter. Pass `null` for "全部". A
  /// [Selector] over the resulting list means the AppBar rebuilds
  /// without touching the reminder list cache.
  void setSelectedTagId(String? id) {
    if (_selectedTagId == id) return;
    _selectedTagId = id;
    notifyListeners();
  }

  /// Marks a reminder as complete (or un-completes it). On complete,
  /// the reminder is tagged with [kCompletedTagId] and its previously
  /// selected [tagId] is stashed into [Reminder.previousTagId] so the
  /// original category is recoverable. On un-complete, the stashed
  /// [Reminder.previousTagId] is restored as [tagId] (and the slot is
  /// cleared) — if the reminder was uncategorised before completion,
  /// `tagId` is restored to `null`. The scheduled OS notification is
  /// cancelled on complete; a future-fire-time notification is re-armed
  /// on un-complete. Past-due reminders stay un-armed even on
  /// un-complete, matching the restore path's behaviour.
  Future<void> setCompleted(String id, bool value) async {
    final index = _reminders.indexWhere((r) => r.id == id);
    if (index == -1) return;
    final original = _reminders[index];
    final Reminder next;
    if (value) {
      // Stash the pre-completion tag so un-complete can restore it.
      // Skip the stash if the row is already completed (idempotent
      // re-tap) or if the current tag is itself the completed
      // pseudo-id (defensive: avoid turning `previousTagId` into
      // `kCompletedTagId`).
      final stash = (original.tagId != null &&
              original.tagId != kCompletedTagId)
          ? original.tagId
          : original.previousTagId;
      next = original.copyWith(
        tagId: kCompletedTagId,
        previousTagId: stash,
      );
    } else {
      // Restore the pre-completion tag (or null if there was none) and
      // clear the slot so a future complete cycle starts fresh.
      // `clearTagId` is needed when restoring to null because
      // `Reminder.copyWith` treats a null `tagId` argument as
      // "leave alone" — see reminder.dart: tagId is only nulled out
      // when `clearTagId` is true.
      next = original.copyWith(
        tagId: original.previousTagId,
        clearTagId: original.previousTagId == null,
        clearPreviousTagId: true,
      );
    }
    // Skip persistence and side-effects when nothing changed.
    if (next.tagId == original.tagId &&
        next.previousTagId == original.previousTagId) {
      return;
    }
    _reminders[index] = next;
    notifyListeners();
    await _repository.update(next);
    if (value) {
      try {
        await _notifications.cancelReminder(id);
      } on Exception catch (error, stackTrace) {
        developer.log(
          'Failed to cancel notification during complete',
          error: error,
          stackTrace: stackTrace,
        );
      }
    } else if (next.reminderTime.isAfter(DateTime.now())) {
      await _safeSchedule(next);
    }
    _timer.schedule(_reminders);
  }
}
