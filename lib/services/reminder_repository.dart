import 'package:sqflite/sqflite.dart';

import '../models/reminder.dart';
import 'database.dart';

class ReminderRepository {
  ReminderRepository(this._database);

  final AppDatabase _database;

  /// Returns every non-trashed reminder, newest first. Backed by the
  /// `idx_reminders_is_deleted_deleted_at` index for stable ordering.
  Future<List<Reminder>> getAllActive() async {
    final rows = await _database.db.query(
      'reminders',
      where: 'is_deleted = 0',
      orderBy: 'created_at DESC',
    );
    return rows.map(_fromRow).toList();
  }

  /// Returns every trashed reminder, newest-delete first.
  Future<List<Reminder>> getAllTrash() async {
    final rows = await _database.db.query(
      'reminders',
      where: 'is_deleted = 1',
      orderBy: 'deleted_at DESC',
    );
    return rows.map(_fromRow).toList();
  }

  Future<void> insert(Reminder reminder) async {
    await _database.db.insert('reminders', _toRow(reminder));
  }

  Future<void> insertAll(List<Reminder> reminders) async {
    final batch = _database.db.batch();
    for (final reminder in reminders) {
      batch.insert('reminders', _toRow(reminder));
    }
    await batch.commit(noResult: true);
  }

  Future<void> update(Reminder reminder) async {
    await _database.db.update(
      'reminders',
      _toRow(reminder),
      where: 'id = ?',
      whereArgs: [reminder.id],
    );
  }

  /// Permanently removes a row. Used by both the trash page's
  /// "永久删除" path and the legacy 24h auto-delete sweep. Image
  /// cleanup is the caller's responsibility (the view model calls
  /// [InspirationImageStore.deleteByPath]).
  Future<void> permanentDelete(String id) async {
    await _database.db.delete('reminders', where: 'id = ?', whereArgs: [id]);
  }

  /// Soft-deletes a reminder by stamping [isDeleted] and [deletedAt].
  /// The row stays in the table so it can be restored later; the
  /// notification cancel is the caller's responsibility.
  Future<void> softDelete(String id, DateTime now) async {
    await _database.db.update(
      'reminders',
      {'is_deleted': 1, 'deleted_at': now.toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Un-soft-deletes a reminder by clearing both trash columns. The
  /// row becomes active again immediately; the caller re-arms the
  /// notification if the reminder's fire time is still in the future.
  Future<void> restore(String id) async {
    await _database.db.update(
      'reminders',
      {'is_deleted': 0, 'deleted_at': null},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Returns a single reminder row by primary key, or `null` when the
  /// id does not match any row. The query does not filter on
  /// [is_deleted] so callers can find trashed rows too.
  Future<Reminder?> findById(String id) async {
    final rows = await _database.db.query(
      'reminders',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  /// Batch-restores multiple reminders in a single SQL pass.
  Future<void> restoreByIds(List<String> ids) async {
    if (ids.isEmpty) return;
    final placeholders = List<String>.filled(ids.length, '?').join(',');
    await _database.db.update(
      'reminders',
      {'is_deleted': 0, 'deleted_at': null},
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
  }

  /// Permanently removes multiple reminders in a single SQL pass.
  Future<void> permanentDeleteByIds(List<String> ids) async {
    if (ids.isEmpty) return;
    final placeholders = List<String>.filled(ids.length, '?').join(',');
    await _database.db.delete(
      'reminders',
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
  }

  /// Counts active (non-trashed) reminders. Used by the home-page
  /// stats card.
  Future<int> count() async {
    final result = await _database.db.rawQuery(
      "SELECT COUNT(*) AS cnt FROM reminders WHERE is_deleted = 0",
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Counts trashed reminders. Surfaced in the data-settings tile and
  /// the trash page header.
  Future<int> countTrash() async {
    final result = await _database.db.rawQuery(
      "SELECT COUNT(*) AS cnt FROM reminders WHERE is_deleted = 1",
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Returns just the primary keys, used by import paths that need to
  /// dedup against existing rows without paying for full-row materialisation.
  Future<Set<String>> listIds() async {
    final rows = await _database.db.query('reminders', columns: ['id']);
    return {for (final row in rows) row['id'] as String};
  }

  /// Permanently removes every trashed reminder older than [cutoff].
  /// Returns the [imagePath] of every purged row so the caller can
  /// clean up the associated files on disk. Rows without an image
  /// contribute a `null` slot to keep the list parallel to the row
  /// order.
  Future<List<String?>> purgeTrashOlderThan(DateTime cutoff) async {
    final rows = await _database.db.query(
      'reminders',
      columns: <String>['id', 'image_path'],
      where: 'is_deleted = 1 AND deleted_at < ?',
      whereArgs: <Object?>[cutoff.toIso8601String()],
    );
    final ids = <String>[for (final row in rows) row['id'] as String];
    final imagePaths = <String?>[
      for (final row in rows) row['image_path'] as String?,
    ];
    if (ids.isEmpty) return imagePaths;
    final placeholders = List<String>.filled(ids.length, '?').join(',');
    await _database.db.delete(
      'reminders',
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
    return imagePaths;
  }

  /// Removes every active (non-trashed) row. Used by the data
  /// management subpage's "清空全部数据" path, which intentionally
  /// bypasses the trash — the user has already confirmed the
  /// destructive action via the dialog.
  Future<int> clearAll() async {
    return _database.db.delete('reminders', where: 'is_deleted = 0');
  }

  static Map<String, dynamic> _toRow(Reminder r) => {
    'id': r.id,
    'title': r.title,
    'reminder_time': r.reminderTime.toIso8601String(),
    'image_path': r.imagePath,
    'description': r.description,
    'is_deleted': r.isDeleted ? 1 : 0,
    'deleted_at': r.deletedAt?.toIso8601String(),
    'created_at': r.createdAt.toIso8601String(),
  };

  static Reminder _fromRow(Map<String, dynamic> row) => Reminder.fromMap(row);
}
