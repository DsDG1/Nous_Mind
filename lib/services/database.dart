import 'dart:convert';
import 'dart:developer' as developer;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'package:nousmind/models/app_settings.dart';
import 'package:nousmind/models/inspiration.dart';
import 'package:nousmind/models/reminder.dart';
import 'package:nousmind/models/tag.dart';

class AppDatabase {
  AppDatabase._(this._db);

  final Database _db;

  static const int _version = 8;
  static const String _name = 'reminders.db';

  Database get db => _db;

  static Future<AppDatabase> open({String? path}) async {
    final targetPath =
        path ?? p.join((await getApplicationDocumentsDirectory()).path, _name);
    final db = await openDatabase(
      targetPath,
      version: _version,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    final instance = AppDatabase._(db);
    await instance._migrateIfNeeded();
    return instance;
  }

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE reminders (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        reminder_time TEXT NOT NULL,
        image_path TEXT,
        description TEXT,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        deleted_at TEXT,
        created_at TEXT NOT NULL,
        tag_id TEXT,
        previous_tag_id TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_reminders_is_deleted_deleted_at '
      'ON reminders (is_deleted, deleted_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_reminders_tag_id ON reminders (tag_id)',
    );
    await db.execute('''
      CREATE TABLE tags (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        color INTEGER NOT NULL,
        built_in INTEGER NOT NULL DEFAULT 0,
        sort_order INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE inspirations (
        id TEXT PRIMARY KEY,
        text TEXT NOT NULL,
        created_at TEXT NOT NULL,
        image_path TEXT,
        ocr_text TEXT,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        deleted_at TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_inspirations_is_deleted_deleted_at '
      'ON inspirations (is_deleted, deleted_at)',
    );
    await db.execute('''
      CREATE TABLE app_settings (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        data TEXT NOT NULL
      )
    ''');
    // Seed the built-in tags + the "已完成" pseudo-tag for fresh
    // installs. The v5 migration does the same for upgrading
    // installs; the seed helper is idempotent (skipped when the
    // `tags` table is non-empty).
    await _seedBuiltinTags(db);
  }

  static Future<void> _onUpgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      // Version 1 optionally created FTS5 tables/triggers on devices where
      // FTS5 was available. They are no longer used, so clean them up.
      await db.execute('DROP TABLE IF EXISTS inspirations_fts');
      await db.execute('DROP TRIGGER IF EXISTS inspirations_ai');
      await db.execute('DROP TRIGGER IF EXISTS inspirations_ad');
      await db.execute('DROP TRIGGER IF EXISTS inspirations_au');
    }
    if (oldVersion < 3) {
      // v3 adds the optional multi-line body to reminders. ALTER TABLE
      // is additive and preserves every existing row; SQLite stores the
      // column as NULL for rows written before the migration, which
      // [Reminder.fromMap] already treats as "no description".
      await db.execute('ALTER TABLE reminders ADD COLUMN description TEXT');
    }
    if (oldVersion < 4) {
      // v4 adds soft-delete ("trash") support. Pre-existing rows get
      // `is_deleted = 0` via the column default and `deleted_at = NULL`
      // (implicit), so they continue to behave as active reminders
      // without any per-row backfill.
      await db.execute(
        'ALTER TABLE reminders ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0',
      );
      await db.execute('ALTER TABLE reminders ADD COLUMN deleted_at TEXT');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_reminders_is_deleted_deleted_at '
        'ON reminders (is_deleted, deleted_at)',
      );
    }
    if (oldVersion < 5) {
      // v5 introduces user-defined tags. A new `tags` table holds the
      // 4 built-in defaults plus the "已完成" pseudo-tag plus any
      // custom tags the user creates. The `reminders.tag_id` column
      // is nullable so pre-existing rows keep working with no tag.
      await db.execute('''
        CREATE TABLE tags (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          color INTEGER NOT NULL,
          built_in INTEGER NOT NULL DEFAULT 0,
          sort_order INTEGER NOT NULL DEFAULT 0
        )
      ''');
      await db.execute('ALTER TABLE reminders ADD COLUMN tag_id TEXT');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_reminders_tag_id ON reminders (tag_id)',
      );
      // Backfill the built-in tags. Skipped automatically when the
      // `tags` table is non-empty (covers the rare reinstall path).
      await _seedBuiltinTags(db);
    }
    if (oldVersion < 6) {
      await db.execute('ALTER TABLE inspirations ADD COLUMN ocr_text TEXT');
    }
    if (oldVersion < 7) {
      await db.execute(
        'ALTER TABLE inspirations ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0',
      );
      await db.execute('ALTER TABLE inspirations ADD COLUMN deleted_at TEXT');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_inspirations_is_deleted_deleted_at '
        'ON inspirations (is_deleted, deleted_at)',
      );
    }
    if (oldVersion < 8) {
      // v8 adds previous_tag_id to reminders so that un-completing a
      // reminder can restore the tag that was set before the user
      // tapped the complete button. Pre-existing rows get NULL, which
      // is the correct default ("had no tag before completing").
      await db.execute(
        'ALTER TABLE reminders ADD COLUMN previous_tag_id TEXT',
      );
    }
  }

  /// Inserts the built-in default tags + the "已完成" pseudo-tag
  /// when the `tags` table is empty. No-op otherwise. Called from
  /// both [_onCreate] (fresh install) and the v4→v5 [_onUpgrade]
  /// branch (upgrade install).
  static Future<void> _seedBuiltinTags(Database db) async {
    final existing = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM tags'),
    );
    if (existing != null && existing > 0) return;
    final batch = db.batch();
    for (final tag in Tag.defaultTags) {
      batch.insert('tags', tag.toMap());
    }
    await batch.commit(noResult: true);
  }

  Future<void> _migrateIfNeeded() async {
    final count = Sqflite.firstIntValue(
      await _db.rawQuery('SELECT COUNT(*) FROM app_settings'),
    );
    if (count != null && count > 0) return;
    final prefs = await SharedPreferences.getInstance();
    await _migrateReminders(prefs);
    await _migrateInspirations(prefs);
    await _migrateSettings(prefs);
  }

  Future<void> _migrateReminders(SharedPreferences prefs) async {
    final raw = prefs.getString('reminders');
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      final batch = _db.batch();
      for (final item in decoded) {
        if (item is! Map<String, dynamic>) continue;
        final reminder = Reminder.fromJson(item);
        batch.insert('reminders', {
          'id': reminder.id,
          'title': reminder.title,
          'reminder_time': reminder.reminderTime.toIso8601String(),
          'image_path': reminder.imagePath,
          'created_at': DateTime.now().toIso8601String(),
        });
      }
      await batch.commit(noResult: true);
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Failed to migrate reminders',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _migrateInspirations(SharedPreferences prefs) async {
    final raw = prefs.getString('inspirations');
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      final batch = _db.batch();
      for (final item in decoded) {
        if (item is! Map<String, dynamic>) continue;
        final inspiration = Inspiration.fromJson(item);
        batch.insert('inspirations', {
          'id': inspiration.id,
          'text': inspiration.text,
          'created_at': inspiration.createdAt.toIso8601String(),
          'image_path': inspiration.imagePath,
        });
      }
      await batch.commit(noResult: true);
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Failed to migrate inspirations',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _migrateSettings(SharedPreferences prefs) async {
    final raw = prefs.getString('app_settings');
    if (raw == null || raw.isEmpty) {
      await _db.insert('app_settings', {
        'id': 1,
        'data': jsonEncode(const AppSettings().toJson()),
      });
      return;
    }
    try {
      final decoded = jsonDecode(raw);
      final settings = AppSettings.fromJson(
        decoded is Map<String, dynamic> ? decoded : <String, dynamic>{},
      );
      await _db.insert('app_settings', {
        'id': 1,
        'data': jsonEncode(settings.toJson()),
      });
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Failed to migrate settings',
        error: error,
        stackTrace: stackTrace,
      );
      await _db.insert('app_settings', {
        'id': 1,
        'data': jsonEncode(const AppSettings().toJson()),
      });
    }
  }

  Future<void> close() => _db.close();
}
