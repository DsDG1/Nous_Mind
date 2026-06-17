import 'package:sqflite/sqflite.dart';

import 'package:nousmind/models/tag.dart';
import 'package:nousmind/services/database.dart';

/// Thrown when the user tries to delete a custom tag that is still
/// referenced by at least one active reminder. The view model
/// surfaces the message via a SnackBar; the UI must offer a path to
/// reassign the affected reminders before retrying.
class TagInUseException implements Exception {
  TagInUseException(this.tagId, this.referencingCount);
  final String tagId;
  final int referencingCount;

  @override
  String toString() => 'TagInUseException($tagId, in_use_by=$referencingCount)';
}

/// CRUD over the `tags` table. Read paths return tags in
/// user-visible order (`sort_order ASC, name ASC`); writes refuse
/// to touch built-in rows.
class TagRepository {
  TagRepository(this._database);

  final AppDatabase _database;

  /// Returns every tag, ordered for display. Cheap to call
  /// repeatedly — the in-memory cache in [TagsViewModel] does the
  /// heavy lifting; this is the source of truth on cold start.
  Future<List<Tag>> getAll() async {
    final rows = await _database.db.query(
      'tags',
      orderBy: 'sort_order ASC, name ASC',
    );
    return rows.map(Tag.fromMap).toList();
  }

  /// Bulk-insert used by the v5 backfill. No-op on empty input.
  Future<void> insertAll(List<Tag> tags) async {
    if (tags.isEmpty) return;
    final batch = _database.db.batch();
    for (final tag in tags) {
      batch.insert('tags', tag.toMap());
    }
    await batch.commit(noResult: true);
  }

  /// Inserts a new custom tag. The caller is responsible for
  /// generating the id and validating the name + color; the
  /// repository trusts the row as-is.
  Future<void> insert(Tag tag) async {
    await _database.db.insert('tags', tag.toMap());
  }

  /// Updates an existing tag's mutable fields (name, color,
  /// sortOrder). The id and builtIn flag are immutable; the
  /// repository passes through whatever the caller hands it.
  Future<void> update(Tag tag) async {
    await _database.db.update(
      'tags',
      tag.toMap(),
      where: 'id = ?',
      whereArgs: [tag.id],
    );
  }

  /// Deletes a tag by id. Refuses to touch a built-in tag and
  /// refuses to delete a custom tag that's still referenced by an
  /// active reminder (caller must reassign first).
  ///
  /// Throws [TagInUseException] when the second guard fires.
  Future<void> delete(String id) async {
    final tag = await _findById(id);
    if (tag == null) return;
    if (tag.builtIn) {
      throw StateError('Cannot delete built-in tag $id');
    }
    final refCount = await _countActiveReferences(id);
    if (refCount > 0) {
      throw TagInUseException(id, refCount);
    }
    await _database.db.delete('tags', where: 'id = ?', whereArgs: [id]);
  }

  /// Counts custom (non-built-in) tags. The settings subpage uses
  /// this to enforce the 10-tag cap before letting the user open
  /// the add-tag dialog.
  Future<int> countCustom() async {
    final result = await _database.db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM tags WHERE built_in = 0',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<Tag?> _findById(String id) async {
    final rows = await _database.db.query(
      'tags',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Tag.fromMap(rows.first);
  }

  Future<int> _countActiveReferences(String tagId) async {
    final result = await _database.db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM reminders '
      'WHERE tag_id = ? AND is_deleted = 0',
      <Object?>[tagId],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }
}
