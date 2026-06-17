import 'package:sqflite/sqflite.dart';

import 'package:nousmind/models/inspiration.dart';
import 'package:nousmind/services/database.dart';

class InspirationRepository {
  InspirationRepository(this._database);

  final AppDatabase _database;

  /// Returns every active (non-trashed) inspiration, newest first.
  Future<List<Inspiration>> getAll() async {
    final rows = await _database.db.query(
      'inspirations',
      where: 'is_deleted = 0',
      orderBy: 'created_at DESC',
    );
    return rows.map(_fromRow).toList();
  }

  /// Returns every trashed inspiration, newest-delete first.
  Future<List<Inspiration>> getAllTrash() async {
    final rows = await _database.db.query(
      'inspirations',
      where: 'is_deleted = 1',
      orderBy: 'deleted_at DESC',
    );
    return rows.map(_fromRow).toList();
  }

  Future<void> insert(Inspiration inspiration) async {
    await _database.db.insert('inspirations', _toRow(inspiration));
  }

  Future<void> insertAll(List<Inspiration> inspirations) async {
    final batch = _database.db.batch();
    for (final inspiration in inspirations) {
      batch.insert('inspirations', _toRow(inspiration));
    }
    await batch.commit(noResult: true);
  }

  Future<void> update(Inspiration inspiration) async {
    await _database.db.update(
      'inspirations',
      _toRow(inspiration),
      where: 'id = ?',
      whereArgs: [inspiration.id],
    );
  }

  /// Permanently removes a row.
  Future<void> permanentDelete(String id) async {
    await _database.db.delete('inspirations', where: 'id = ?', whereArgs: [id]);
  }

  /// Soft-deletes an inspiration by stamping [isDeleted] and [deletedAt].
  Future<void> softDelete(String id, DateTime now) async {
    await _database.db.update(
      'inspirations',
      {'is_deleted': 1, 'deleted_at': now.toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Un-soft-deletes an inspiration.
  Future<void> restore(String id) async {
    await _database.db.update(
      'inspirations',
      {'is_deleted': 0, 'deleted_at': null},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Returns a single inspiration row by primary key, or `null` if not found.
  Future<Inspiration?> findById(String id) async {
    final rows = await _database.db.query(
      'inspirations',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  /// Batch-restores multiple inspirations.
  Future<void> restoreByIds(List<String> ids) async {
    if (ids.isEmpty) return;
    final placeholders = List<String>.filled(ids.length, '?').join(',');
    await _database.db.update(
      'inspirations',
      {'is_deleted': 0, 'deleted_at': null},
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
  }

  /// Permanently removes multiple inspirations.
  Future<void> permanentDeleteByIds(List<String> ids) async {
    if (ids.isEmpty) return;
    final placeholders = List<String>.filled(ids.length, '?').join(',');
    await _database.db.delete(
      'inspirations',
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
  }

  /// Searches active inspirations whose text or OCR text matches [query].
  Future<List<Inspiration>> search(String query) async {
    final rows = await _database.db.query(
      'inspirations',
      where: '(text LIKE ? OR ocr_text LIKE ?) AND is_deleted = 0',
      whereArgs: ['%$query%', '%$query%'],
      orderBy: 'created_at DESC',
    );
    return rows.map(_fromRow).toList();
  }

  /// Counts active (non-trashed) inspirations.
  Future<int> count() async {
    final result = await _database.db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM inspirations WHERE is_deleted = 0',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Counts trashed inspirations.
  Future<int> countTrash() async {
    final result = await _database.db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM inspirations WHERE is_deleted = 1',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Returns just the primary keys, used by import paths.
  Future<Set<String>> listIds() async {
    final rows = await _database.db.query('inspirations', columns: ['id']);
    return {for (final row in rows) row['id'] as String};
  }

  /// Permanently removes every trashed inspiration older than [cutoff].
  /// Returns the [imagePath] of every purged row.
  Future<List<String?>> purgeTrashOlderThan(DateTime cutoff) async {
    final rows = await _database.db.query(
      'inspirations',
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
      'inspirations',
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
    return imagePaths;
  }

  /// Removes every active (non-trashed) row.
  Future<int> clearAll() async {
    return _database.db.delete('inspirations', where: 'is_deleted = 0');
  }

  static Map<String, dynamic> _toRow(Inspiration i) => {
    'id': i.id,
    'text': i.text,
    'created_at': i.createdAt.toIso8601String(),
    'image_path': i.imagePath,
    'ocr_text': i.ocrText,
    'is_deleted': i.isDeleted ? 1 : 0,
    'deleted_at': i.deletedAt?.toIso8601String(),
  };

  static Inspiration _fromRow(Map<String, dynamic> row) =>
      Inspiration.fromMap(row);
}
