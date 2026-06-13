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

  static Map<String, dynamic> _toRow(Inspiration i) => {
    'id': i.id,
    'text': i.text,
    'created_at': i.createdAt.toIso8601String(),
    'image_path': i.imagePath,
  };

  static Inspiration _fromRow(Map<String, dynamic> row) =>
      Inspiration.fromMap(row);
}
