import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/models/reminder.dart';

void main() {
  final fixedTime = DateTime(2026, 6, 13, 18, 30);

  group('Reminder', () {
    test('round-trips through JSON', () {
      final original = Reminder(
        id: '1700000000000000',
        title: '买菜',
        reminderTime: fixedTime,
        createdAt: fixedTime,
      );

      final restored = Reminder.fromJson(original.toJson());

      expect(restored.id, original.id);
      expect(restored.title, original.title);
      expect(restored.reminderTime, original.reminderTime);
      expect(restored.createdAt, original.createdAt);
    });

    test('round-trips through Map (SQLite)', () {
      final original = Reminder(
        id: '1700000000000000',
        title: '买菜',
        reminderTime: fixedTime,
        imagePath: '/tmp/test.jpg',
        createdAt: fixedTime,
      );

      final restored = Reminder.fromMap(original.toMap());

      expect(restored.id, original.id);
      expect(restored.title, original.title);
      expect(restored.reminderTime, original.reminderTime);
      expect(restored.imagePath, original.imagePath);
      expect(restored.createdAt, original.createdAt);
    });

    test('copyWith updates only the given fields', () {
      final original = Reminder(
        id: '1',
        title: '买菜',
        reminderTime: fixedTime,
        createdAt: fixedTime,
      );

      final updated = original.copyWith(title: '买菜和水果');

      expect(updated.id, original.id);
      expect(updated.title, '买菜和水果');
      expect(updated.reminderTime, original.reminderTime);
      expect(updated.createdAt, original.createdAt);
    });

    test('description round-trips through JSON', () {
      final original = Reminder(
        id: '1700000000000000',
        title: '买菜',
        reminderTime: fixedTime,
        description: '胡萝卜 2 根,西红柿 3 个,鸡蛋一盒',
        createdAt: fixedTime,
      );

      final restored = Reminder.fromJson(original.toJson());

      expect(restored.description, original.description);
    });

    test('description round-trips through Map (SQLite)', () {
      final original = Reminder(
        id: '1700000000000000',
        title: '买菜',
        reminderTime: fixedTime,
        description: '带购物袋,记得带钥匙',
        createdAt: fixedTime,
      );

      final restored = Reminder.fromMap(original.toMap());

      expect(restored.description, original.description);
    });

    test('description defaults to null when missing from JSON', () {
      // Pre-v3 backups and migrated rows land here. The model must
      // accept the missing field without throwing.
      final json = <String, dynamic>{
        'id': '1700000000000000',
        'title': '买菜',
        'reminder_time': fixedTime.toIso8601String(),
        'created_at': fixedTime.toIso8601String(),
      };

      final restored = Reminder.fromJson(json);

      expect(restored.description, isNull);
    });

    test('description defaults to null when column missing from Map', () {
      // Pre-v3 rows in SQLite do not have a description column.
      final map = <String, dynamic>{
        'id': '1700000000000000',
        'title': '买菜',
        'reminder_time': fixedTime.toIso8601String(),
        'image_path': null,
        'created_at': fixedTime.toIso8601String(),
      };

      final restored = Reminder.fromMap(map);

      expect(restored.description, isNull);
    });

    test('whitespace-only description is normalized to null on parse', () {
      // Some callers strip before persisting; the parser still treats
      // empty/whitespace strings as "no description" so the editor
      // and notification rendering stay in sync.
      final json = <String, dynamic>{
        'id': '1700000000000000',
        'title': '买菜',
        'reminder_time': fixedTime.toIso8601String(),
        'description': '   \n  ',
        'created_at': fixedTime.toIso8601String(),
      };

      final restored = Reminder.fromJson(json);

      expect(restored.description, isNull);
    });

    test('copyWith clearDescription wipes the field', () {
      final original = Reminder(
        id: '1',
        title: '买菜',
        reminderTime: fixedTime,
        description: 'old body',
        createdAt: fixedTime,
      );

      final cleared = original.copyWith(clearDescription: true);

      expect(cleared.description, isNull);
    });
  });
}
