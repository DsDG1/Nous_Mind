import 'dart:convert';
import 'dart:developer' as developer;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../models/app_settings.dart';
import '../models/inspiration.dart';
import '../models/reminder.dart';

class AppDatabase {
  AppDatabase._(this._db);

  final Database _db;

  static const int _version = 2;
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
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE inspirations (
        id TEXT PRIMARY KEY,
        text TEXT NOT NULL,
        created_at TEXT NOT NULL,
        image_path TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE app_settings (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        data TEXT NOT NULL
      )
    ''');
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
