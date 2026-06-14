import 'package:sqflite/sqflite.dart';

import '../models/inspiration.dart';
import 'database.dart';

class InspirationRepository {
  InspirationRepository(this._database);

  final AppDatabase _database;

  Future<List<Inspiration>> getAll() async {
    final rows = await _database.db.query(
      'inspirations',
      orderBy: 'created_at DESC',
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

  Future<void> delete(String id) async {
    await _database.db.delete('inspirations', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Inspiration>> search(String query) async {
    final rows = await _database.db.query(
      'inspirations',
      where: 'text LIKE ?',
      whereArgs: ['%$query%'],
      orderBy: 'created_at DESC',
    );
    return rows.map(_fromRow).toList();
  }

  Future<int> count() async {
    final result = await _database.db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM inspirations',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Returns just the primary keys, used by import paths that need to
  /// dedup against existing rows without paying for full-row materialisation.
  Future<Set<String>> listIds() async {
    final rows = await _database.db.query('inspirations', columns: ['id']);
    return {for (final row in rows) row['id'] as String};
  }

  /// Removes every row from the inspirations table. Used by the data
  /// management subpage to bulk-clear entries. Callers are responsible
  /// for deleting any associated image files.
  Future<int> clearAll() async {
    return _database.db.delete('inspirations');
  }

  static Map<String, dynamic> _toRow(Inspiration i) => {
    'id': i.id,
    'text': i.text,
    'created_at': i.createdAt.toIso8601String(),
    'image_path': i.imagePath,
  };

  static Inspiration _fromRow(Map<String, dynamic> row) =>
      Inspiration.fromMap(row);
}
