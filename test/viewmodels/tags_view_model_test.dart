import 'package:flutter_test/flutter_test.dart';

import 'package:nousmind/viewmodels/tags_view_model.dart';

import '../helpers/fakes.dart';

class TestTagsContext {
  TestTagsContext._({
    required this.testDb,
    required this.tagsVm,
  });

  final TestDatabase testDb;
  final TagsViewModel tagsVm;

  static Future<TestTagsContext> create() async {
    final db = await TestDatabase.create();
    final tagsVm = TagsViewModel(db.tagRepository);
    await tagsVm.refresh();
    return TestTagsContext._(
      testDb: db,
      tagsVm: tagsVm,
    );
  }

  Future<void> dispose() async {
    tagsVm.dispose();
    await testDb.dispose();
  }
}

void main() {
  group('TagsViewModel', () {
    late TestTagsContext ctx;

    setUp(() async {
      ctx = await TestTagsContext.create();
    });

    tearDown(() async {
      await ctx.dispose();
    });

    test('add tag generates ID successfully without crash', () async {
      final tag = await ctx.tagsVm.add(name: 'Work', color: 0xFF00FF00);
      expect(tag, isNotNull);
      expect(tag!.name, 'Work');
      expect(tag.color, 0xFF00FF00);
      expect(tag.builtIn, isFalse);
      
      // UUID length should be 36 characters (8-4-4-4-12 format)
      expect(tag.id.length, 36);
      expect(tag.id[8], '-');
      expect(tag.id[13], '-');
      expect(tag.id[18], '-');
      expect(tag.id[23], '-');
    });

    test('cannot add tags exceeding cap', () async {
      for (var i = 0; i < TagsViewModel.customTagCap; i++) {
        final tag = await ctx.tagsVm.add(name: 'Tag $i', color: 0xFF000000);
        expect(tag, isNotNull);
      }
      final failedTag = await ctx.tagsVm.add(name: 'Extra Tag', color: 0xFF000000);
      expect(failedTag, isNull);
    });

    test('cannot add duplicate or empty tags', () async {
      final tag = await ctx.tagsVm.add(name: 'Duplicate', color: 0xFF000000);
      expect(tag, isNotNull);

      final duplicate = await ctx.tagsVm.add(name: 'Duplicate', color: 0xFF000000);
      expect(duplicate, isNull);

      final empty = await ctx.tagsVm.add(name: '', color: 0xFF000000);
      expect(empty, isNull);
    });
  });
}
