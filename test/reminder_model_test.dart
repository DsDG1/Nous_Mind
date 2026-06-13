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
  });
}
