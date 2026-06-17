import 'package:flutter_test/flutter_test.dart';

import 'package:nousmind/viewmodels/inspirations_view_model.dart';
import 'package:nousmind/viewmodels/settings_view_model.dart';

import '../helpers/fakes.dart';

class TestInspirationsContext {
  TestInspirationsContext._({
    required this.testDb,
    required this.settingsVm,
    required this.inspirationsVm,
  });

  final TestDatabase testDb;
  final SettingsViewModel settingsVm;
  final InspirationsViewModel inspirationsVm;

  static Future<TestInspirationsContext> create() async {
    final db = await TestDatabase.create();
    final settingsVm = makeSettingsVm();
    final inspirationsVm = InspirationsViewModel(
      db.inspirationRepository,
      db.imageStore.store,
      settingsVm,
    );
    await inspirationsVm.refresh();
    return TestInspirationsContext._(
      testDb: db,
      settingsVm: settingsVm,
      inspirationsVm: inspirationsVm,
    );
  }

  Future<void> dispose() async {
    inspirationsVm.dispose();
    settingsVm.dispose();
    await testDb.dispose();
  }
}

void main() {
  group('InspirationsViewModel', () {
    late TestInspirationsContext ctx;

    setUp(() async {
      ctx = await TestInspirationsContext.create();
    });

    tearDown(() async {
      await ctx.dispose();
    });

    test('add appends an inspiration', () async {
      await ctx.inspirationsVm.add(text: 'Idea 1');

      expect(ctx.inspirationsVm.inspirations, hasLength(1));
      expect(ctx.inspirationsVm.inspirations.single.text, 'Idea 1');
      expect(ctx.inspirationsVm.trashCount, 0);
    });

    test('softDelete removes from active list and bumps trashCount', () async {
      await ctx.inspirationsVm.add(text: 'Idea 1');
      final id = ctx.inspirationsVm.inspirations.single.id;

      await ctx.inspirationsVm.delete(id);

      expect(ctx.inspirationsVm.inspirations, isEmpty);
      expect(ctx.inspirationsVm.trashCount, 1);
    });

    test('restore brings back trashed inspiration', () async {
      await ctx.inspirationsVm.add(text: 'Idea 1');
      final id = ctx.inspirationsVm.inspirations.single.id;
      await ctx.inspirationsVm.delete(id);

      await ctx.inspirationsVm.restore(id);

      expect(ctx.inspirationsVm.inspirations, hasLength(1));
      expect(ctx.inspirationsVm.inspirations.single.text, 'Idea 1');
      expect(ctx.inspirationsVm.trashCount, 0);
    });

    test('purgeTrash permanently deletes inspirations', () async {
      await ctx.inspirationsVm.add(text: 'Idea 1');
      final id = ctx.inspirationsVm.inspirations.single.id;
      await ctx.inspirationsVm.delete(id);

      final purged = await ctx.inspirationsVm.purgeTrash();

      expect(purged, 1);
      expect(ctx.inspirationsVm.trashCount, 0);
      expect(await ctx.testDb.inspirationRepository.countTrash(), 0);
    });
  });
}
