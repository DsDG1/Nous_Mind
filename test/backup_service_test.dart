import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:nousmind/models/inspiration.dart';
import 'package:nousmind/models/reminder.dart';
import 'package:nousmind/services/backup_service.dart';
import 'package:nousmind/services/inspiration_image_store.dart';
import 'package:nousmind/services/inspiration_repository.dart';
import 'package:nousmind/services/reminder_repository.dart';
import 'package:nousmind/services/settings_repository.dart';
import 'package:nousmind/services/database.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tempDir;
  late AppDatabase db;
  late BackupService backup;
  late Directory imagesDir;
  late ReminderRepository reminders;
  late InspirationRepository inspirations;
  late SettingsRepository settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tempDir = await Directory.systemTemp.createTemp('flutter_app_backup_');
    PathProviderPlatform.instance = _TempPathProvider(tempDir);
    db = await AppDatabase.open(path: '${tempDir.path}/reminders.db');
    imagesDir = Directory('${tempDir.path}/images')..createSync();
    final imageStore = InspirationImageStore(imagesDir);
    reminders = ReminderRepository(db);
    inspirations = InspirationRepository(db);
    settings = SettingsRepository(db);
    backup = BackupService(
      reminderRepository: reminders,
      inspirationRepository: inspirations,
      settingsRepository: settings,
      imageStore: imageStore,
    );
  });

  tearDown(() async {
    await db.close();
    await tempDir.delete(recursive: true);
  });

  group('BackupService', () {
    test(
      'exports reminders, inspirations, and settings to a JSON file',
      () async {
        await reminders.insert(
          Reminder(
            id: 'r-1',
            title: 'Buy milk',
            reminderTime: DateTime.utc(2026, 6, 13, 10, 0),
          ),
        );
        await inspirations.insert(
          Inspiration(
            id: 'i-1',
            text: 'Read a book',
            createdAt: DateTime.utc(2026, 6, 13, 9, 0),
          ),
        );
        await settings.save(
          (await settings.load()).copyWith(
            aiAssistantEnabled: true,
            aiApiKey: 'sk-test',
          ),
        );

        final file = await backup.exportToFile();
        expect(file.existsSync(), isTrue);
        final content = await file.readAsString();
        expect(content, contains('Buy milk'));
        expect(content, contains('Read a book'));
        expect(content, contains('sk-test'));
        expect(content, contains('"ai_assistant_enabled": true'));
        expect(content, contains('"version": 1'));
      },
    );

    test('imports reminders and inspirations, skipping duplicates', () async {
      await reminders.insert(
        Reminder(
          id: 'r-existing',
          title: 'Existing',
          reminderTime: DateTime.utc(2026, 6, 13, 10, 0),
        ),
      );
      await inspirations.insert(
        Inspiration(
          id: 'i-existing',
          text: 'Existing inspiration',
          createdAt: DateTime.utc(2026, 6, 13, 9, 0),
        ),
      );

      final backupPayload = <String, dynamic>{
        'version': 1,
        'reminders': <Map<String, dynamic>>[
          Reminder(
            id: 'r-existing',
            title: 'Existing',
            reminderTime: DateTime.utc(2026, 6, 13, 10, 0),
          ).toJson(),
          Reminder(
            id: 'r-new',
            title: 'Brand new',
            reminderTime: DateTime.utc(2026, 6, 13, 11, 0),
          ).toJson(),
        ],
        'inspirations': <Map<String, dynamic>>[
          Inspiration(
            id: 'i-existing',
            text: 'Existing inspiration',
            createdAt: DateTime.utc(2026, 6, 13, 9, 0),
          ).toJson(),
          Inspiration(
            id: 'i-new',
            text: 'Brand new idea',
            createdAt: DateTime.utc(2026, 6, 13, 10, 0),
          ).toJson(),
        ],
        'settings': <String, dynamic>{},
      };
      final file = File('${tempDir.path}/backup.json')
        ..writeAsStringSync(jsonEncode(backupPayload));

      final result = await backup.importFromFile(file);

      expect(result.remindersImported, 1);
      expect(result.inspirationsImported, 1);
      final allReminders = await reminders.getAllActive();
      final allInspirations = await inspirations.getAll();
      expect(allReminders, hasLength(2));
      expect(allInspirations, hasLength(2));
      expect(
        allReminders.map((r) => r.id),
        containsAll(<String>['r-existing', 'r-new']),
      );
      expect(
        allInspirations.map((i) => i.id),
        containsAll(<String>['i-existing', 'i-new']),
      );
    });

    test('excludes trashed reminders from the export', () async {
      await reminders.insert(
        Reminder(
          id: 'r-active',
          title: 'Active reminder',
          reminderTime: DateTime.utc(2026, 6, 13, 10, 0),
        ),
      );
      await reminders.insert(
        Reminder(
          id: 'r-trashed',
          title: 'Trashed reminder',
          reminderTime: DateTime.utc(2026, 6, 13, 10, 0),
        ),
      );
      // Move one row to the trash; the export must drop it.
      await reminders.softDelete('r-trashed', DateTime.utc(2026, 6, 14, 9, 0));

      final file = await backup.exportToFile();
      final content = await file.readAsString();
      final decoded = jsonDecode(content) as Map<String, dynamic>;
      final exported = (decoded['reminders'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(Reminder.fromJson)
          .toList();

      expect(exported.map((r) => r.id), <String>['r-active']);
      expect(
        exported.any((r) => r.isDeleted),
        isFalse,
        reason: 'BackupService.exportToFile must not include trashed rows',
      );
    });

    test('rejects malformed backup files with FormatException', () async {
      final file = File('${tempDir.path}/bad.json')
        ..writeAsStringSync('"just a string"');
      expect(backup.importFromFile(file), throwsFormatException);
    });

    test(
      'getStats counts records and reports zero images by default',
      () async {
        await reminders.insert(
          Reminder(
            id: 'r-1',
            title: 'One',
            reminderTime: DateTime.utc(2026, 6, 13, 10, 0),
          ),
        );
        await reminders.insert(
          Reminder(
            id: 'r-2',
            title: 'Two',
            reminderTime: DateTime.utc(2026, 6, 13, 11, 0),
          ),
        );
        await inspirations.insert(
          Inspiration(
            id: 'i-1',
            text: 'Idea',
            createdAt: DateTime.utc(2026, 6, 13, 9, 0),
          ),
        );

        final stats = await backup.getStats();
        expect(stats.reminderCount, 2);
        expect(stats.inspirationCount, 1);
        expect(stats.imageBytes, 0);
      },
    );
  });
}

class _TempPathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _TempPathProvider(this.dir);

  final Directory dir;

  @override
  Future<String?> getTemporaryPath() async => dir.path;

  @override
  Future<String?> getApplicationDocumentsPath() async => dir.path;
}
