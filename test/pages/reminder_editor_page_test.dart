import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:nousmind/pages/reminder_editor_page.dart';
import 'package:nousmind/models/reminder_draft.dart';
import 'package:nousmind/services/ai_analyzer.dart';
import 'package:nousmind/services/ai_usage_guard.dart';
import 'package:nousmind/services/inspiration_image_store.dart';
import 'package:nousmind/viewmodels/reminders_view_model.dart';
import 'package:nousmind/viewmodels/settings_view_model.dart';
import 'package:nousmind/viewmodels/tags_view_model.dart';

import '../helpers/fakes.dart';

class _FakeAiAnalyzer implements AiAnalyzer {
  _FakeAiAnalyzer(this.drafts);
  final List<ReminderDraft> drafts;

  @override
  Future<List<ReminderDraft>> adjustReminder({
    required String? title,
    required String? description,
    String? imagePath,
    required String apiKey,
    required String timezone,
    required DateTime now,
    String? systemPromptTemplate,
    List<({String id, String name})> availableTags = const [],
  }) async {
    return drafts;
  }

  @override
  Future<String> analyzeError({
    required String text,
    required String apiKey,
    String? systemPrompt,
  }) async => '';

  @override
  void dispose() {}

  @override
  void setChineseOcrProvider(bool Function() provider) {}

  @override
  Future<Map<String, dynamic>> analyzeInspirations({
    required List<String> texts,
    required List<String> ocrTexts,
    required List<DateTime> dates,
    required List<String> enabledFunctions,
    required String apiKey,
    required String timezone,
    required DateTime now,
    String? systemPromptTemplate,
    List<({String id, String name})> availableTags = const [],
  }) async => const <String, dynamic>{};
}

void main() {
  late TestRemindersContext ctx;

  setUp(() async {
    ctx = await TestRemindersContext.create();
    // Enable AI assistant and set fake API key so AI button can be clicked
    await ctx.settingsVm.setAiAssistantEnabled(true);
    await ctx.settingsVm.setAiApiKey('test-key');
  });

  tearDown(() async {
    await ctx.dispose();
  });

  Widget wrap({required Widget child, required AiAnalyzer analyzer}) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<RemindersViewModel>.value(
          value: ctx.remindersVm,
        ),
        ChangeNotifierProvider<SettingsViewModel>.value(value: ctx.settingsVm),
        ChangeNotifierProvider<TagsViewModel>.value(value: ctx.tagsVm),
        Provider<InspirationImageStore>.value(
          value: ctx.testDb.imageStore.store,
        ),
        Provider<AiUsageGuard>(
          create: (context) =>
              AiUsageGuard(settings: context.read<SettingsViewModel>()),
        ),
        Provider<AiAnalyzer>.value(value: analyzer),
      ],
      child: child,
    );
  }

  testWidgets(
    'AI detects multiple items, long press or tap edit on item shows edit dialog, updates it',
    (tester) async {
      final drafts = [
        ReminderDraft(
          id: '1',
          title: 'Draft A',
          suggestedTime: DateTime(2026, 6, 15, 10),
        ),
        ReminderDraft(
          id: '2',
          title: 'Draft B',
          suggestedTime: DateTime(2026, 6, 15, 11),
        ),
      ];
      final analyzer = _FakeAiAnalyzer(drafts);

      await tester.pumpWidget(
        wrap(
          child: const MaterialApp(home: ReminderEditorPage()),
          analyzer: analyzer,
        ),
      );

      Future<void> pumpFrames() async {
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      // Initial state: empty form. We click AI button.
      // The AI button shows auto_awesome icon.
      final aiButton = find.byIcon(Icons.auto_awesome);
      expect(aiButton, findsOneWidget);

      // AI button requires double tap to prevent accidental triggers (see _onAiPressed)
      await tester.tap(aiButton);
      await tester.pump();
      await tester.tap(aiButton);

      // Allow AI call and dialog to show
      await tester.pump(); // Show confirm dialog
      expect(find.text('确认调用 AI'), findsOneWidget);
      await tester.tap(find.text('调用 AI'));

      // Pump frames so AI completes and bottom sheet is shown
      await pumpFrames();

      // Verify bottom sheet shows the drafts
      expect(find.text('检测到 2 条提醒'), findsOneWidget);
      expect(find.text('Draft A'), findsOneWidget);
      expect(find.text('Draft B'), findsOneWidget);

      // Find the edit button for "Draft B" and tap it
      // The second edit button corresponds to index 1 (Draft B)
      final editButtons = find.byIcon(Icons.edit_outlined);
      expect(editButtons, findsNWidgets(2));
      await tester.tap(editButtons.at(1));
      await pumpFrames();

      // Edit dialog should be open
      expect(find.text('编辑提醒内容'), findsOneWidget);

      // Find the title text field and change it to "Draft B Edited"
      final titleField = find
          .ancestor(of: find.text('Draft B'), matching: find.byType(TextField))
          .first;
      await tester.enterText(titleField, 'Draft B Edited');
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('保存'),
        ),
      );
      await pumpFrames();

      // The edit dialog should be closed and the draft list updated
      expect(find.text('编辑提醒内容'), findsNothing);
      expect(find.text('Draft B Edited'), findsOneWidget);
      expect(find.text('Draft B'), findsNothing);

      // Let's test the long press gesture on "Draft A"
      await tester.longPress(find.text('Draft A'));
      await pumpFrames();

      // Edit dialog should be open for Draft A
      expect(find.text('编辑提醒内容'), findsOneWidget);
      final titleFieldA = find
          .ancestor(of: find.text('Draft A'), matching: find.byType(TextField))
          .first;
      await tester.enterText(titleFieldA, 'Draft A Edited');
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('保存'),
        ),
      );
      await pumpFrames();

      // Verify Draft A is updated
      expect(find.text('Draft A Edited'), findsOneWidget);
      expect(find.text('Draft A'), findsNothing);

      // Click Save (添加 2 项)
      await tester.tap(find.text('添加 2 项'));
      await pumpFrames();

      // Verify they are added to the list in memory
      expect(ctx.remindersVm.reminders, hasLength(2));
      expect(
        ctx.remindersVm.reminders.any((r) => r.title == 'Draft A Edited'),
        isTrue,
      );
      expect(
        ctx.remindersVm.reminders.any((r) => r.title == 'Draft B Edited'),
        isTrue,
      );
    },
  );
}
