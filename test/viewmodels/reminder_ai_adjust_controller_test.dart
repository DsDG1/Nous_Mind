import 'package:flutter_test/flutter_test.dart';

import 'package:nousmind/models/reminder_draft.dart';
import 'package:nousmind/services/ai_analyzer.dart';
import 'package:nousmind/services/ai_usage_guard.dart';
import 'package:nousmind/viewmodels/reminder_ai_adjust_controller.dart';
import 'package:nousmind/viewmodels/settings_view_model.dart';

import '../helpers/fakes.dart';

/// Hand-rolled fake for [AiAnalyzer]. Counts how many times the
/// adjust endpoint was hit so tests can assert the controller
/// stopped at the right gate.
class _FakeAiAnalyzer implements AiAnalyzer {
  _FakeAiAnalyzer({this.drafts = const <ReminderDraft>[], this.error});
  final List<ReminderDraft> drafts;
  final Object? error;
  int adjustCalls = 0;

  @override
  Future<List<ReminderDraft>> adjustReminder({
    required String? title,
    required String? description,
    String? imagePath,
    required String apiKey,
    required String timezone,
    required DateTime now,
    String? systemPromptTemplate,
    List<({String id, String name})> availableTags =
        const <({String id, String name})>[],
  }) async {
    adjustCalls++;
    if (error != null) throw error!;
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
    List<({String id, String name})> availableTags =
        const <({String id, String name})>[],
  }) async => <String, dynamic>{};
}

/// Captures the last batch passed to the [ReminderBatchAdd] port so
/// tests can assert on its size and contents.
class _BatchCall {
  int callCount = 0;
  int lastBatchSize = 0;
  Future<int> call(
    List<
      ({
        String title,
        DateTime reminderTime,
        String? description,
        String? tagId,
      })
    >
    drafts,
  ) async {
    callCount++;
    lastBatchSize = drafts.length;
    return drafts.length;
  }
}

SettingsViewModel _makeVm({
  bool aiEnabled = true,
  String? apiKey = 'sk-test',
  int aiDailyLimit = 3,
  bool aiDailyLimitEnabled = true,
  int aiCallsToday = 0,
}) => makeSettingsVm(
  aiAssistantEnabled: aiEnabled,
  aiApiKey: apiKey,
  aiDailyLimit: aiDailyLimit,
  aiDailyLimitEnabled: aiDailyLimitEnabled,
  aiCallsToday: aiCallsToday,
);

/// Drives [ReminderAiAdjustController.adjust] end-to-end with
/// scripted user responses. The auto-respond happens inside the
/// stream listener so events are appended in the order they were
/// delivered; the helper then drains pending microtasks so the
/// broadcast stream's delivery microtasks (which are queued after
/// `adjust`'s completion microtask) flush before the subscription
/// is cancelled.
Future<List<AiAdjustEvent>> _runAdjust({
  required ReminderAiAdjustController controller,
  bool confirm = true,
  List<int>? batchSelection,
}) async {
  final events = <AiAdjustEvent>[];
  final sub = controller.events.listen((event) {
    events.add(event);
    if (event is ShowConfirmDialogEvent) {
      controller.onConfirmDialogResult(confirm);
    } else if (event is ShowBatchSheetEvent) {
      controller.onBatchSheetResult(batchSelection);
    }
  });
  await controller.adjust(
    title: 't',
    description: 'd',
    reminderTime: DateTime(2026, 6, 15, 10),
    imagePath: null,
    timezone: 'UTC',
  );
  // Flush any broadcast-stream delivery microtasks that were
  // scheduled after `adjust`'s completion. A few rounds is enough
  // for the deepest branch (confirm → analyzer → batch sheet → add
  // → pop).
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
  await sub.cancel();
  return events;
}

void main() {
  group('ReminderAiAdjustController.adjust — pre-flight gates', () {
    test(
      'emits snackbar and skips analyzer when AI assistant is disabled',
      () async {
        final settings = _makeVm(aiEnabled: false);
        final guard = AiUsageGuard(settings: settings);
        final analyzer = _FakeAiAnalyzer();
        final batch = _BatchCall();
        final c = ReminderAiAdjustController(
          settings: settings,
          guard: guard,
          analyzer: analyzer,
          reminderAdder: batch.call,
        );

        final events = await _runAdjust(controller: c);

        expect(events, hasLength(1));
        expect(events.single, isA<ShowSnackBarEvent>());
        expect((events.single as ShowSnackBarEvent).message, contains('启用'));
        expect(analyzer.adjustCalls, 0);
        expect(batch.callCount, 0);
        expect(settings.aiCallsToday, 0);
        c.dispose();
      },
    );

    test('emits snackbar and skips analyzer when API key is missing', () async {
      final settings = _makeVm(apiKey: null);
      final guard = AiUsageGuard(settings: settings);
      final analyzer = _FakeAiAnalyzer();
      final batch = _BatchCall();
      final c = ReminderAiAdjustController(
        settings: settings,
        guard: guard,
        analyzer: analyzer,
        reminderAdder: batch.call,
      );

      final events = await _runAdjust(controller: c);

      expect(events, hasLength(1));
      expect(events.single, isA<ShowSnackBarEvent>());
      expect((events.single as ShowSnackBarEvent).message, contains('API 密钥'));
      expect(analyzer.adjustCalls, 0);
      expect(settings.aiCallsToday, 0);
      c.dispose();
    });

    test(
      'emits snackbar and skips analyzer when API key is whitespace',
      () async {
        final settings = _makeVm(apiKey: '   ');
        final guard = AiUsageGuard(settings: settings);
        final analyzer = _FakeAiAnalyzer();
        final batch = _BatchCall();
        final c = ReminderAiAdjustController(
          settings: settings,
          guard: guard,
          analyzer: analyzer,
          reminderAdder: batch.call,
        );

        final events = await _runAdjust(controller: c);

        expect(events, hasLength(1));
        expect(events.single, isA<ShowSnackBarEvent>());
        expect(analyzer.adjustCalls, 0);
        c.dispose();
      },
    );

    test(
      'emits cooldown snackbar and skips analyzer when in cooldown',
      () async {
        final settings = _makeVm(aiDailyLimit: 3);
        final guard = AiUsageGuard(settings: settings);
        // Land a prior call so the guard enters the cooldown window.
        await guard.recordSuccess();
        final analyzer = _FakeAiAnalyzer();
        final batch = _BatchCall();
        final c = ReminderAiAdjustController(
          settings: settings,
          guard: guard,
          analyzer: analyzer,
          reminderAdder: batch.call,
        );

        final events = await _runAdjust(controller: c);

        expect(events, hasLength(1));
        expect(events.single, isA<ShowSnackBarEvent>());
        expect((events.single as ShowSnackBarEvent).message, contains('请稍候'));
        expect(analyzer.adjustCalls, 0);
        expect(batch.callCount, 0);
        c.dispose();
      },
    );

    test(
      'emits daily-limit snackbar and skips analyzer when quota is full',
      () async {
        final settings = _makeVm(aiDailyLimit: 2, aiCallsToday: 2);
        final guard = AiUsageGuard(settings: settings);
        final analyzer = _FakeAiAnalyzer();
        final batch = _BatchCall();
        final c = ReminderAiAdjustController(
          settings: settings,
          guard: guard,
          analyzer: analyzer,
          reminderAdder: batch.call,
        );

        final events = await _runAdjust(controller: c);

        expect(events, hasLength(1));
        expect(events.single, isA<ShowSnackBarEvent>());
        expect((events.single as ShowSnackBarEvent).message, contains('上限'));
        expect(analyzer.adjustCalls, 0);
        c.dispose();
      },
    );
  });

  group('ReminderAiAdjustController.adjust — user confirm path', () {
    test(
      'user cancels confirm dialog → analyzer not called, no recordSuccess',
      () async {
        final settings = _makeVm();
        final guard = AiUsageGuard(settings: settings);
        final analyzer = _FakeAiAnalyzer();
        final batch = _BatchCall();
        final c = ReminderAiAdjustController(
          settings: settings,
          guard: guard,
          analyzer: analyzer,
          reminderAdder: batch.call,
        );

        final events = await _runAdjust(controller: c, confirm: false);

        // The confirm dialog is shown and dismissed; nothing else
        // happens, so no quota is charged and no analyzer call lands.
        expect(events.whereType<ShowConfirmDialogEvent>(), hasLength(1));
        expect(events.whereType<ShowSnackBarEvent>(), isEmpty);
        expect(events.whereType<ApplyDraftEvent>(), isEmpty);
        expect(events.whereType<PopEvent>(), isEmpty);
        expect(analyzer.adjustCalls, 0);
        expect(batch.callCount, 0);
        expect(settings.aiCallsToday, 0);
        c.dispose();
      },
    );
  });

  group('ReminderAiAdjustController.adjust — analyzer result branches', () {
    test('empty drafts → snackbar + recordSuccess counted', () async {
      final settings = _makeVm();
      final guard = AiUsageGuard(settings: settings);
      final analyzer = _FakeAiAnalyzer(drafts: const <ReminderDraft>[]);
      final batch = _BatchCall();
      final c = ReminderAiAdjustController(
        settings: settings,
        guard: guard,
        analyzer: analyzer,
        reminderAdder: batch.call,
      );

      final events = await _runAdjust(controller: c);

      expect(events.whereType<ShowConfirmDialogEvent>(), hasLength(1));
      expect(events.whereType<ShowSnackBarEvent>(), hasLength(1));
      expect(
        (events.whereType<ShowSnackBarEvent>().single.message),
        contains('未识别'),
      );
      expect(events.whereType<ApplyDraftEvent>(), isEmpty);
      expect(events.whereType<PopEvent>(), isEmpty);
      // recordSuccess runs on every successful round-trip,
      // including the empty case, so the daily counter advances.
      expect(settings.aiCallsToday, 1);
      expect(analyzer.adjustCalls, 1);
      expect(batch.callCount, 0);
      c.dispose();
    });

    test(
      'single draft → ApplyDraftEvent + snackbar, no batch, no pop',
      () async {
        final draft = ReminderDraft(
          id: '1',
          title: 'new title',
          suggestedTime: DateTime(2026, 6, 15, 11),
          description: 'new desc',
        );
        final settings = _makeVm();
        final guard = AiUsageGuard(settings: settings);
        final analyzer = _FakeAiAnalyzer(drafts: [draft]);
        final batch = _BatchCall();
        final c = ReminderAiAdjustController(
          settings: settings,
          guard: guard,
          analyzer: analyzer,
          reminderAdder: batch.call,
        );

        final events = await _runAdjust(controller: c);

        final apply = events.whereType<ApplyDraftEvent>().single;
        expect(apply.title, 'new title');
        expect(apply.description, 'new desc');
        expect(apply.reminderTime, DateTime(2026, 6, 15, 11));

        expect(events.whereType<ShowSnackBarEvent>(), hasLength(1));
        expect(
          (events.whereType<ShowSnackBarEvent>().single.message),
          contains('已自动调整'),
        );
        expect(events.whereType<ShowBatchSheetEvent>(), isEmpty);
        expect(events.whereType<PopEvent>(), isEmpty);
        expect(batch.callCount, 0);
        expect(settings.aiCallsToday, 1);
        c.dispose();
      },
    );

    test(
      'multi drafts + user selects some → addMultiple + snackbar + PopEvent',
      () async {
        final drafts = [
          ReminderDraft(
            id: '1',
            title: 'A',
            suggestedTime: DateTime(2026, 6, 15, 10),
          ),
          ReminderDraft(
            id: '2',
            title: 'B',
            suggestedTime: DateTime(2026, 6, 15, 11),
            description: 'desc-B',
          ),
          ReminderDraft(
            id: '3',
            title: 'C',
            suggestedTime: DateTime(2026, 6, 15, 12),
          ),
        ];
        final settings = _makeVm();
        final guard = AiUsageGuard(settings: settings);
        final analyzer = _FakeAiAnalyzer(drafts: drafts);
        final batch = _BatchCall();
        final c = ReminderAiAdjustController(
          settings: settings,
          guard: guard,
          analyzer: analyzer,
          reminderAdder: batch.call,
        );

        final events = await _runAdjust(
          controller: c,
          batchSelection: <int>[0, 2],
        );

        expect(events.whereType<ShowConfirmDialogEvent>(), hasLength(1));
        expect(events.whereType<ShowBatchSheetEvent>(), hasLength(1));
        expect(events.whereType<PopEvent>(), hasLength(1));
        expect(events.whereType<ShowSnackBarEvent>(), hasLength(1));
        expect(
          (events.whereType<ShowSnackBarEvent>().single.message),
          contains('已添加 2 项'),
        );
        // Selected indices [0, 2] map to drafts A and C — B is left
        // out. The batch port should have been called with the two
        // selected records, not all three.
        expect(batch.callCount, 1);
        expect(batch.lastBatchSize, 2);
        expect(settings.aiCallsToday, 1);
        c.dispose();
      },
    );

    test(
      'multi drafts + user deselects all → no addMultiple, no PopEvent',
      () async {
        final drafts = [
          ReminderDraft(
            id: '1',
            title: 'A',
            suggestedTime: DateTime(2026, 6, 15, 10),
          ),
          ReminderDraft(
            id: '2',
            title: 'B',
            suggestedTime: DateTime(2026, 6, 15, 11),
          ),
        ];
        final settings = _makeVm();
        final guard = AiUsageGuard(settings: settings);
        final analyzer = _FakeAiAnalyzer(drafts: drafts);
        final batch = _BatchCall();
        final c = ReminderAiAdjustController(
          settings: settings,
          guard: guard,
          analyzer: analyzer,
          reminderAdder: batch.call,
        );

        final events = await _runAdjust(controller: c, batchSelection: <int>[]);

        expect(events.whereType<ShowBatchSheetEvent>(), hasLength(1));
        expect(events.whereType<PopEvent>(), isEmpty);
        expect(events.whereType<ShowSnackBarEvent>(), isEmpty);
        expect(batch.callCount, 0);
        // recordSuccess still runs because the analyzer returned
        // successfully; the daily counter advances regardless of the
        // user choosing to drop the drafts.
        expect(settings.aiCallsToday, 1);
        c.dispose();
      },
    );

    test(
      'multi drafts + user dismisses sheet (null) → no addMultiple, no Pop',
      () async {
        final drafts = [
          ReminderDraft(
            id: '1',
            title: 'A',
            suggestedTime: DateTime(2026, 6, 15, 10),
          ),
          ReminderDraft(
            id: '2',
            title: 'B',
            suggestedTime: DateTime(2026, 6, 15, 11),
          ),
          ReminderDraft(
            id: '3',
            title: 'C',
            suggestedTime: DateTime(2026, 6, 15, 12),
          ),
        ];
        final settings = _makeVm();
        final guard = AiUsageGuard(settings: settings);
        final analyzer = _FakeAiAnalyzer(drafts: drafts);
        final batch = _BatchCall();
        final c = ReminderAiAdjustController(
          settings: settings,
          guard: guard,
          analyzer: analyzer,
          reminderAdder: batch.call,
        );

        final events = await _runAdjust(controller: c, batchSelection: null);

        expect(events.whereType<ShowBatchSheetEvent>(), hasLength(1));
        expect(events.whereType<PopEvent>(), isEmpty);
        expect(events.whereType<ShowSnackBarEvent>(), isEmpty);
        expect(batch.callCount, 0);
        c.dispose();
      },
    );
  });

  group('ReminderAiAdjustController.adjust — error branches', () {
    test(
      'AiAnalysisException → snackbar with exception message, no recordSuccess',
      () async {
        final settings = _makeVm();
        final guard = AiUsageGuard(settings: settings);
        final analyzer = _FakeAiAnalyzer(error: AiRateLimitException('请求过于频繁'));
        final batch = _BatchCall();
        final c = ReminderAiAdjustController(
          settings: settings,
          guard: guard,
          analyzer: analyzer,
          reminderAdder: batch.call,
        );

        final events = await _runAdjust(controller: c);

        expect(events.whereType<ShowConfirmDialogEvent>(), hasLength(1));
        expect(events.whereType<ShowSnackBarEvent>(), hasLength(1));
        expect(
          (events.whereType<ShowSnackBarEvent>().single.message),
          '请求过于频繁',
        );
        expect(events.whereType<ApplyDraftEvent>(), isEmpty);
        expect(events.whereType<PopEvent>(), isEmpty);
        expect(batch.callCount, 0);
        // The exception bypasses recordSuccess so the daily counter
        // does not advance on a failed call.
        expect(settings.aiCallsToday, 0);
        c.dispose();
      },
    );

    test('generic Exception → fallback snackbar, no recordSuccess', () async {
      final settings = _makeVm();
      final guard = AiUsageGuard(settings: settings);
      final analyzer = _FakeAiAnalyzer(error: Exception('boom'));
      final batch = _BatchCall();
      final c = ReminderAiAdjustController(
        settings: settings,
        guard: guard,
        analyzer: analyzer,
        reminderAdder: batch.call,
      );

      final events = await _runAdjust(controller: c);

      expect(events.whereType<ShowConfirmDialogEvent>(), hasLength(1));
      expect(events.whereType<ShowSnackBarEvent>(), hasLength(1));
      expect(
        (events.whereType<ShowSnackBarEvent>().single.message),
        contains('请稍后重试'),
      );
      expect(events.whereType<ApplyDraftEvent>(), isEmpty);
      expect(events.whereType<PopEvent>(), isEmpty);
      expect(batch.callCount, 0);
      expect(settings.aiCallsToday, 0);
      c.dispose();
    });
  });

  group('ReminderAiAdjustController — analyzer state', () {
    test(
      'isAnalyzing flips to true only during the analyzer round-trip',
      () async {
        final settings = _makeVm();
        final guard = AiUsageGuard(settings: settings);
        final analyzer = _FakeAiAnalyzer(
          drafts: [
            ReminderDraft(
              id: '1',
              title: 'A',
              suggestedTime: DateTime(2026, 6, 15, 10),
            ),
          ],
        );
        final batch = _BatchCall();
        final c = ReminderAiAdjustController(
          settings: settings,
          guard: guard,
          analyzer: analyzer,
          reminderAdder: batch.call,
        );

        // Idle before adjust().
        expect(c.isAnalyzing, isFalse);

        await _runAdjust(controller: c);

        // Back to idle after adjust() returns.
        expect(c.isAnalyzing, isFalse);
        c.dispose();
      },
    );
  });
}
