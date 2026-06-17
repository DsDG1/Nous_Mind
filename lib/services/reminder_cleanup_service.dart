import 'dart:async';
import 'dart:developer' as developer;

import 'package:nousmind/models/reminder.dart';
import 'package:nousmind/services/inspiration_image_store.dart';
import 'package:nousmind/services/notification_service.dart';
import 'package:nousmind/services/reminder_repository.dart';
import 'package:nousmind/viewmodels/settings_view_model.dart';

/// Encapsulates the periodic cleanup passes that keep the reminders
/// table from accumulating forever:
///
///   1. Trash retention — soft-deleted rows older than
///      [ReminderRepository.trashRetention] are permanently deleted
///      and their image files (if any) are removed from disk.
///   2. Auto-delete — when the user has `autoDeleteAfter24h` on,
///      active reminders whose fire time is more than 24 hours in
///      the past are permanently deleted along with their images and
///      scheduled notifications.
///
/// The class is intentionally side-effect free outside the two
/// "purge" methods; no in-memory cache, no notification listener.
/// Callers (the view model) update their own state from the returned
/// counts / id lists and trigger `notifyListeners` themselves.
class ReminderCleanupService {
  ReminderCleanupService({
    required this._repository,
    required this._notifications,
    required this._imageStore,
    required this._settings,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final ReminderRepository _repository;
  final NotificationService _notifications;
  final InspirationImageStore _imageStore;
  final SettingsViewModel _settings;
  final DateTime Function() _now;

  /// Permanently removes every trashed reminder older than
  /// [ReminderRepository.trashRetention]. Returns the number of rows
  /// actually purged (image files contribute too, so the count can
  /// exceed the number of rows whose deletion succeeded — a deleted
  /// image file counts even when its row had already been cleaned
  /// out by an earlier sweep).
  Future<int> purgeExpiredTrash() async {
    final cutoff = _now().subtract(ReminderRepository.trashRetention);
    final purgedImagePaths = await _repository.purgeTrashOlderThan(cutoff);
    if (purgedImagePaths.isEmpty) {
      return 0;
    }
    for (final imagePath in purgedImagePaths) {
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
    return purgedImagePaths.length;
  }

  /// When the user has `autoDeleteAfter24h` enabled, permanently
  /// removes active reminders whose fire time is more than 24 h in
  /// the past. Cancels each row's scheduled notification and deletes
  /// its image file. Returns the IDs of the deleted rows so the
  /// caller can drop them from its in-memory list.
  ///
  /// When the setting is off, returns an empty list without
  /// touching the database.
  Future<List<String>> purgeExpiredActive(List<Reminder> active) async {
    if (!_settings.settings.autoDeleteAfter24h) {
      return const <String>[];
    }
    final now = _now();
    final cutoff = now.subtract(const Duration(hours: 24));
    final expired = active
        .where((r) => r.reminderTime.isBefore(cutoff))
        .toList();
    if (expired.isEmpty) {
      return const <String>[];
    }
    final deletedIds = <String>[];
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
      deletedIds.add(reminder.id);
    }
    return deletedIds;
  }
}
