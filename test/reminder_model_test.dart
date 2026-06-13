import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/models/reminder.dart';

void main() {
  group('Reminder', () {
    test('round-trips through JSON', () {
      final original = Reminder(
        id: '1700000000000000',
        title: '买菜',
        reminderTime: DateTime.utc(2026, 6, 13, 18, 30),
      );

      final restored = Reminder.fromJson(original.toJson());

      expect(restored.id, original.id);
      expect(restored.title, original.title);
      expect(restored.reminderTime, original.reminderTime);
    });

    test('copyWith updates only the given fields', () {
      final original = Reminder(
        id: '1',
        title: '买菜',
        reminderTime: DateTime.utc(2026, 6, 13, 18, 30),
      );

      final updated = original.copyWith(title: '买菜和水果');

      expect(updated.id, original.id);
      expect(updated.title, '买菜和水果');
      expect(updated.reminderTime, original.reminderTime);
    });
  });
}
