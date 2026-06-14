import 'package:sqflite/sqflite.dart';

import '../models/reminder.dart';
import 'database.dart';

class ReminderRepository {
  ReminderRepository(this._database);

  final AppDatabase _database;

  Future<List<Reminder>> getAll() async {
    final rows = await _database.db.query(
      'reminders',
      orderBy: 'created_at DESC',
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

  Future<void> delete(String id) async {
    await _database.db.delete('reminders', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> count() async {
    final result = await _database.db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM reminders',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Returns just the primary keys, used by import paths that need to
  /// dedup against existing rows without paying for full-row materialisation.
  Future<Set<String>> listIds() async {
    final rows = await _database.db.query('reminders', columns: ['id']);
    return {for (final row in rows) row['id'] as String};
  }

  /// Removes every row from the reminders table. Used by the data
  /// management subpage to bulk-clear entries.
  Future<int> clearAll() async {
    return _database.db.delete('reminders');
  }

  static Map<String, dynamic> _toRow(Reminder r) => {
    'id': r.id,
    'title': r.title,
    'reminder_time': r.reminderTime.toIso8601String(),
    'image_path': r.imagePath,
    'created_at': r.createdAt.toIso8601String(),
  };

  static Reminder _fromRow(Map<String, dynamic> row) => Reminder.fromMap(row);
}
