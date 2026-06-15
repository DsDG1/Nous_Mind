import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:nousmind/models/app_settings.dart';
import 'package:nousmind/models/inspiration.dart';
import 'package:nousmind/models/reminder.dart';
import 'package:nousmind/services/database.dart';
import 'package:nousmind/services/inspiration_repository.dart';
import 'package:nousmind/services/reminder_repository.dart';
import 'package:nousmind/services/settings_repository.dart';

void main() {
  // Use the FFI-backed SQLite implementation for consistent behavior across
  // host platforms during testing. This also avoids needing a mobile emulator.
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('flutter_app_db_test_');
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  String dbPath() => '${tempDir.path}/reminders.db';

  group('AppDatabase.open', () {
    test('creates the schema without FTS5 dependencies', () async {
      final db = await AppDatabase.open(path: dbPath());
      addTearDown(db.close);

      final tables = await db.db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'",
      );
      final names = tables.map((r) => r['name'] as String).toList();

      expect(
        names,
        containsAll(<String>['reminders', 'inspirations', 'app_settings']),
      );
      expect(names, isNot(contains('inspirations_fts')));
    });

    test('seeds default settings on first open', () async {
      final db = await AppDatabase.open(path: dbPath());
      addTearDown(db.close);

      final settings = await SettingsRepository(db).load();

      expect(settings.themeMode, ThemeMode.system);
      expect(settings.seedColor, AppSeedColor.blue);
    });

    test('migrates legacy SharedPreferences data', () async {
      final prefs = await SharedPreferences.getInstance();
      final reminder = Reminder(
        id: '1',
        title: 'Legacy reminder',
        reminderTime: DateTime.utc(2026, 6, 13, 10, 0),
      );
      final inspiration = Inspiration(
        id: '2',
        text: 'Legacy inspiration',
        createdAt: DateTime.utc(2026, 6, 13, 9, 0),
      );
      await prefs.setString('reminders', '[${jsonEncode(reminder.toJson())}]');
      await prefs.setString(
        'inspirations',
        '[${jsonEncode(inspiration.toJson())}]',
      );

      final db = await AppDatabase.open(path: dbPath());
      addTearDown(db.close);

      final reminders = await ReminderRepository(db).getAllActive();
      final inspirations = await InspirationRepository(db).getAll();

      expect(reminders, hasLength(1));
      expect(reminders.first.title, 'Legacy reminder');
      expect(inspirations, hasLength(1));
      expect(inspirations.first.text, 'Legacy inspiration');
    });

    test('does not migrate twice when app_settings already exists', () async {
      final prefs = await SharedPreferences.getInstance();
      final reminder = Reminder(
        id: '1',
        title: 'Legacy reminder',
        reminderTime: DateTime.utc(2026, 6, 13, 10, 0),
      );
      await prefs.setString('reminders', '[${jsonEncode(reminder.toJson())}]');

      // First open performs the migration.
      final first = await AppDatabase.open(path: dbPath());
      await first.close();

      // Second open should leave the single migrated row untouched.
      final second = await AppDatabase.open(path: dbPath());
      addTearDown(second.close);

      final reminders = await ReminderRepository(second).getAllActive();
      expect(reminders, hasLength(1));
    });
  });

  group('InspirationRepository.search', () {
    test('uses LIKE when no FTS5 is available', () async {
      final db = await AppDatabase.open(path: dbPath());
      addTearDown(db.close);

      final repo = InspirationRepository(db);
      await repo.insert(
        Inspiration(
          id: '1',
          text: 'Buy coffee beans',
          createdAt: DateTime.utc(2026, 6, 13, 8, 0),
        ),
      );
      await repo.insert(
        Inspiration(
          id: '2',
          text: 'Walk in the park',
          createdAt: DateTime.utc(2026, 6, 13, 9, 0),
        ),
      );

      final results = await repo.search('coffee');

      expect(results, hasLength(1));
      expect(results.first.text, 'Buy coffee beans');
    });
  });
}
