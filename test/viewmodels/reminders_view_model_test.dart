import 'package:flutter_test/flutter_test.dart';

import 'package:nousmind/models/reminder.dart';
import 'package:nousmind/models/tag.dart';

import '../helpers/fakes.dart';

void main() {
  group('RemindersViewModel', () {
    late TestRemindersContext ctx;

    setUp(() async {
      ctx = await TestRemindersContext.create();
    });

    tearDown(() async {
      await ctx.dispose();
    });

    test('add appends a reminder and schedules a notification', () async {
      final reminderTime = DateTime.now().add(const Duration(hours: 1));
      final scheduleBefore = ctx.notifications.scheduleCount;

      await ctx.remindersVm.add(title: '买菜', reminderTime: reminderTime);

      expect(ctx.remindersVm.reminders, hasLength(1));
      expect(ctx.remindersVm.reminders.single.title, '买菜');
      expect(ctx.remindersVm.reminders.single.reminderTime, reminderTime);
      expect(ctx.remindersVm.trashCount, 0);
      expect(ctx.notifications.scheduleCount, scheduleBefore + 1);
    });

    test('softDelete removes the row from the active list and bumps '
        'trashCount', () async {
      final reminderTime = DateTime.now().add(const Duration(hours: 1));
      await ctx.remindersVm.add(title: '买菜', reminderTime: reminderTime);
      final id = ctx.remindersVm.reminders.single.id;
      final cancelBefore = ctx.notifications.cancelCount;

      await ctx.remindersVm.softDelete(id);

      expect(ctx.remindersVm.reminders, isEmpty);
      expect(ctx.remindersVm.trashCount, 1);
      expect(ctx.notifications.cancelCount, cancelBefore + 1);
    });

    test(
      'restore brings a trashed reminder back into the active list',
      () async {
        final reminderTime = DateTime.now().add(const Duration(hours: 1));
        await ctx.remindersVm.add(title: '买菜', reminderTime: reminderTime);
        final id = ctx.remindersVm.reminders.single.id;
        await ctx.remindersVm.softDelete(id);
        expect(ctx.remindersVm.reminders, isEmpty);
        expect(ctx.remindersVm.trashCount, 1);

        await ctx.remindersVm.restore(id);

        expect(ctx.remindersVm.reminders, hasLength(1));
        expect(ctx.remindersVm.reminders.single.title, '买菜');
        expect(ctx.remindersVm.trashCount, 0);
      },
    );

    test('clearAllToTrash moves every active reminder to the trash in '
        'one pass', () async {
      final future = DateTime.now().add(const Duration(hours: 1));
      await ctx.remindersVm.add(title: 'a', reminderTime: future);
      await ctx.remindersVm.add(title: 'b', reminderTime: future);
      await ctx.remindersVm.add(title: 'c', reminderTime: future);
      expect(ctx.remindersVm.reminders, hasLength(3));

      final moved = await ctx.remindersVm.clearAllToTrash();

      expect(moved, 3);
      expect(ctx.remindersVm.reminders, isEmpty);
      expect(ctx.remindersVm.trashCount, 3);
      // The DB agrees.
      expect(await ctx.testDb.reminderRepository.countTrash(), 3);
    });

    test('onAppResumed delegates to ReminderCleanupService to purge '
        '30d-old trash rows', () async {
      // Pre-populate a trashed reminder that's past the retention
      // window. We bypass the VM and insert directly so the row is in
      // the DB before bootstrap.
      final oldReminder = Reminder(
        id: 'old',
        title: '一个月前的回收站',
        reminderTime: DateTime.now().subtract(const Duration(days: 40)),
        isDeleted: true,
        deletedAt: DateTime.now().subtract(const Duration(days: 31)),
      );
      await ctx.testDb.reminderRepository.insert(oldReminder);
      expect(await ctx.testDb.reminderRepository.countTrash(), 1);

      await ctx.remindersVm.onAppResumed();

      expect(await ctx.testDb.reminderRepository.countTrash(), 0);
      expect(ctx.remindersVm.trashCount, 0);
    });

    test('add → softDelete → restore → clearAllToTrash all update the '
        'in-memory timer via _timer.schedule', () async {
      // The nearest-reminder timer is private; we cannot reach into it
      // from a unit test without exposing internals. Instead, verify
      // the externally observable side-effect of every code path that
      // touches the timer: each mutation completes without throwing
      // and the VM's `dispose()` (which cancels the timer) runs
      // cleanly in tearDown. Production wiring at `main.dart` is the
      // integration test for the timer → pop-up callback.
      final future = DateTime.now().add(const Duration(hours: 1));
      await ctx.remindersVm.add(title: 'a', reminderTime: future);
      final id = ctx.remindersVm.reminders.single.id;
      await ctx.remindersVm.softDelete(id);
      await ctx.remindersVm.restore(id);
      await ctx.remindersVm.clearAllToTrash();
      expect(ctx.remindersVm.reminders, isEmpty);
    });

    group('setCompleted (bug: 提醒标签完成 / 取消完成后丢失)', () {
      test('complete stashes the prior tagId into previousTagId', () async {
        final reminderTime = DateTime.now().add(const Duration(hours: 1));
        await ctx.remindersVm.add(
          title: '买菜',
          reminderTime: reminderTime,
          tagId: 'work-tag',
        );
        final id = ctx.remindersVm.reminders.single.id;

        await ctx.remindersVm.setCompleted(id, true);

        final after = ctx.remindersVm.reminders.single;
        expect(after.isCompleted, isTrue);
        expect(after.tagId, kCompletedTagId);
        expect(after.previousTagId, 'work-tag');

        // The DB row agrees — both columns were written.
        final fromDb = await ctx.testDb.reminderRepository.findById(id);
        expect(fromDb?.tagId, kCompletedTagId);
        expect(fromDb?.previousTagId, 'work-tag');
      });

      test('un-complete restores the stashed tagId and clears the slot',
          () async {
        final reminderTime = DateTime.now().add(const Duration(hours: 1));
        await ctx.remindersVm.add(
          title: '买菜',
          reminderTime: reminderTime,
          tagId: 'work-tag',
        );
        final id = ctx.remindersVm.reminders.single.id;
        await ctx.remindersVm.setCompleted(id, true);

        await ctx.remindersVm.setCompleted(id, false);

        final after = ctx.remindersVm.reminders.single;
        expect(after.isCompleted, isFalse);
        expect(after.tagId, 'work-tag');
        expect(after.previousTagId, isNull);

        // The DB row agrees — the previous tag is restored and the
        // stash slot is cleared so a future complete cycle starts fresh.
        final fromDb = await ctx.testDb.reminderRepository.findById(id);
        expect(fromDb?.tagId, 'work-tag');
        expect(fromDb?.previousTagId, isNull);
      });

      test('uncategorised reminder stays uncategorised across the cycle',
          () async {
        final reminderTime = DateTime.now().add(const Duration(hours: 1));
        await ctx.remindersVm.add(title: '买菜', reminderTime: reminderTime);
        final id = ctx.remindersVm.reminders.single.id;

        await ctx.remindersVm.setCompleted(id, true);
        var after = ctx.remindersVm.reminders.single;
        expect(after.isCompleted, isTrue);
        expect(after.tagId, kCompletedTagId);
        expect(after.previousTagId, isNull);

        await ctx.remindersVm.setCompleted(id, false);
        after = ctx.remindersVm.reminders.single;
        expect(after.isCompleted, isFalse);
        expect(after.tagId, isNull);
        expect(after.previousTagId, isNull);
      });

      test('re-tapping complete on an already-completed row is a no-op',
          () async {
        final reminderTime = DateTime.now().add(const Duration(hours: 1));
        await ctx.remindersVm.add(
          title: '买菜',
          reminderTime: reminderTime,
          tagId: 'work-tag',
        );
        final id = ctx.remindersVm.reminders.single.id;
        await ctx.remindersVm.setCompleted(id, true);
        final cancelAfterFirst = ctx.notifications.cancelCount;
        final remindersAfterFirst = ctx.remindersVm.reminders.single;

        await ctx.remindersVm.setCompleted(id, true);

        // The notification cancel side-effect is the main thing we
        // must avoid. The row's fields should also be byte-identical
        // to the post-first-complete state, but `Reminder` has no
        // `==` operator — assert on the DB row instead.
        expect(ctx.notifications.cancelCount, cancelAfterFirst,
            reason: 'no-op setCompleted must not re-cancel');
        final fromDb = await ctx.testDb.reminderRepository.findById(id);
        expect(fromDb?.tagId, kCompletedTagId);
        expect(fromDb?.previousTagId, 'work-tag');
        // Sanity: the in-memory snapshot we captured is the same
        // logical row that's still in `_reminders` (id match).
        expect(ctx.remindersVm.reminders.single.id, remindersAfterFirst.id);
        expect(ctx.remindersVm.reminders.single.tagId,
            remindersAfterFirst.tagId);
        expect(ctx.remindersVm.reminders.single.previousTagId,
            remindersAfterFirst.previousTagId);
      });

      test('complete cancels the scheduled notification; un-complete '
          're-arms a future one', () async {
        final reminderTime = DateTime.now().add(const Duration(hours: 2));
        await ctx.remindersVm.add(
          title: '买菜',
          reminderTime: reminderTime,
          tagId: 'work-tag',
        );
        final id = ctx.remindersVm.reminders.single.id;
        final scheduleAfterAdd = ctx.notifications.scheduleCount;
        final cancelAfterAdd = ctx.notifications.cancelCount;

        await ctx.remindersVm.setCompleted(id, true);
        expect(ctx.notifications.cancelCount, cancelAfterAdd + 1);

        await ctx.remindersVm.setCompleted(id, false);
        expect(ctx.notifications.scheduleCount, scheduleAfterAdd + 1);
      });
    });
  });
}
