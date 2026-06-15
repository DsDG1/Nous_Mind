// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:developer' as developer;

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

import 'package:nousmind/models/reminder_draft.dart';
import 'package:nousmind/services/ai_analyzer.dart';
import 'package:nousmind/services/ai_usage_guard.dart';
import 'package:nousmind/viewmodels/reminders_view_model.dart';
import 'package:nousmind/viewmodels/settings_view_model.dart';

/// Sealed event hierarchy emitted by [ReminderAiAdjustController] to
/// drive side-effecting UI (dialogs, bottom sheets, snackbars,
/// navigation, form-controller writes).
///
/// The view subscribes via [ReminderAiAdjustController.events] in
/// `initState` and translates each subtype into the matching Flutter
/// primitive. Keeping every side effect as a value keeps the
/// controller free of `BuildContext` and lets the entire flow be
/// unit-tested without a widget tree.
sealed class AiAdjustEvent {
  const AiAdjustEvent();
}

/// Asks the view to show the "确认调用 AI" dialog. The view pops
/// `bool?` and forwards the result via
/// [ReminderAiAdjustController.onConfirmDialogResult].
class ShowConfirmDialogEvent extends AiAdjustEvent {
  const ShowConfirmDialogEvent(this.quotaLine);
  final String quotaLine;
}

/// Asks the view to show the multi-draft review bottom sheet. The
/// view pops `List<int>?` (selected indices) and forwards the result
/// via [ReminderAiAdjustController.onBatchSheetResult].
class ShowBatchSheetEvent extends AiAdjustEvent {
  const ShowBatchSheetEvent(this.drafts);
  final List<ReminderDraft> drafts;
}

/// Asks the view to surface a Chinese SnackBar. The controller never
/// touches [ScaffoldMessenger] directly.
class ShowSnackBarEvent extends AiAdjustEvent {
  const ShowSnackBarEvent(this.message);
  final String message;
}

/// Asks the view to overwrite the form's title / description / time
/// with the AI's single suggestion. The view writes through its
/// `TextEditingController`s and `setState`.
class ApplyDraftEvent extends AiAdjustEvent {
  const ApplyDraftEvent({
    required this.title,
    required this.description,
    required this.reminderTime,
  });
  final String title;
  final String? description;
  final DateTime reminderTime;
}

/// Asks the view to pop the editor page (typically after a
/// successful batch-add).
class PopEvent extends AiAdjustEvent {
  const PopEvent();
}

/// Minimal batch-insert port used by the controller.
///
/// Typed as a function type rather than an abstract class so
/// production code can pass `(vm) => vm.addMultiple` (where [vm] is
/// a [RemindersViewModel]) and tests can substitute a one-line fake
/// without dragging in repositories, the notification service, or
/// the image store.
typedef ReminderBatchAdd = Future<int> Function(
  List<({String title, DateTime reminderTime, String? description})> drafts,
);

/// Owns the lifecycle of one "AI 自动调整" invocation in the reminder
/// editor: pre-flight checks (enabled / key / cooldown / daily
/// limit), the user confirm step, the analyzer call, the
/// single-vs-multi branch, and the success / error branches.
///
/// UI-agnostic by design: every side effect is delivered as an
/// [AiAdjustEvent] over [events]. Two of those events are
/// interactive (the confirm dialog and the multi-draft sheet) — the
/// view feeds the user's choice back through
/// [onConfirmDialogResult] and [onBatchSheetResult].
class ReminderAiAdjustController extends ChangeNotifier {
  ReminderAiAdjustController({
    required SettingsViewModel settings,
    required AiUsageGuard guard,
    required AiAnalyzer analyzer,
    required ReminderBatchAdd reminderAdder,
  })  : _settings = settings,
        _guard = guard,
        _analyzer = analyzer,
        _reminderAdder = reminderAdder;

  final SettingsViewModel _settings;
  final AiUsageGuard _guard;
  final AiAnalyzer _analyzer;
  final ReminderBatchAdd _reminderAdder;

  bool _isAnalyzing = false;

  /// True while the analyzer round-trip is in flight. Drives the
  /// spinner on the AI button via `Selector<…, bool>`.
  bool get isAnalyzing => _isAnalyzing;

  final StreamController<AiAdjustEvent> _events =
      StreamController<AiAdjustEvent>.broadcast();

  /// One-shot events the view consumes in `initState`.
  Stream<AiAdjustEvent> get events => _events.stream;

  // Pending user-input completers. `_askConfirm` / `_askBatchSelection`
  // create a completer, emit the corresponding event, and `await` on
  // the completer's future; the view resolves the future via the
  // matching `onXxxResult` hook.
  Completer<bool>? _pendingConfirm;
  Completer<List<int>?>? _pendingBatch;

  /// Runs the full AI adjust flow. Returns when the analyzer's
  /// response has been fully delivered (or rejected) and the
  /// controller is back to the idle state. Safe to call again
  /// afterwards; each call runs independently.
  Future<void> adjust({
    required String title,
    required String description,
    required DateTime reminderTime,
    required String? imagePath,
    required String timezone,
  }) async {
    final settings = _settings.settings;

    if (!settings.aiAssistantEnabled) {
      _emit(const ShowSnackBarEvent('请先在 设置 → AI 助手 中启用 AI 助手'));
      return;
    }
    final apiKey = settings.aiApiKey;
    if (apiKey == null || apiKey.trim().isEmpty) {
      _emit(const ShowSnackBarEvent('请先在 设置 → AI 助手 中填写 API 密钥'));
      return;
    }

    final verdict = _guard.tryAcquire();
    if (verdict is AcquireCooldown) {
      _emit(ShowSnackBarEvent(
        'AI 刚调用过,请稍候 ${verdict.retryAfter.inSeconds} 秒再试',
      ));
      return;
    }
    if (verdict is AcquireDailyLimitReached) {
      _emit(ShowSnackBarEvent(
        '今日 AI 调用已达上限(${verdict.limit}/${verdict.limit}),'
        '明天自动恢复或前往设置调整',
      ));
      return;
    }
    final allowed = verdict as AcquireAllowed;

    final confirmed = await _askConfirm(allowed.remaining);
    if (!confirmed) return;

    _setAnalyzing(true);
    try {
      final drafts = await _analyzer.adjustReminder(
        title: title.isEmpty ? null : title,
        description: description.isEmpty ? null : description,
        imagePath: imagePath,
        apiKey: apiKey,
        timezone: timezone,
        now: clock.now(),
        systemPromptTemplate: settings.aiAdjustPrompt,
      );
      // recordSuccess is called for every analyzer round-trip that
      // didn't throw, including the empty-drafts case, so the daily
      // quota tracks actual network spend rather than "useful"
      // results — a model that returned `[]` still cost us a request.
      await _guard.recordSuccess();

      if (drafts.isEmpty) {
        _emit(const ShowSnackBarEvent('AI 未识别到可调整的内容'));
        return;
      }
      if (drafts.length == 1) {
        final draft = drafts.first;
        _emit(ApplyDraftEvent(
          title: draft.title,
          description: draft.description,
          reminderTime: draft.suggestedTime,
        ));
        _emit(const ShowSnackBarEvent('AI 已自动调整'));
        return;
      }
      final selectedIndices = await _askBatchSelection(drafts);
      if (selectedIndices == null || selectedIndices.isEmpty) return;
      final selectedDrafts = [for (final i in selectedIndices) drafts[i]];
      await _reminderAdder(
        selectedDrafts
            .map(
              (d) => (
                title: d.title,
                reminderTime: d.suggestedTime,
                description: d.description,
              ),
            )
            .toList(),
      );
      _emit(ShowSnackBarEvent('已添加 ${selectedDrafts.length} 项'));
      _emit(const PopEvent());
    } on AiAnalysisException catch (error) {
      _emit(ShowSnackBarEvent(error.message));
    } on Exception catch (error, stackTrace) {
      developer.log('AI adjust failed', error: error, stackTrace: stackTrace);
      _emit(const ShowSnackBarEvent('AI 调整失败,请稍后重试'));
    } finally {
      _setAnalyzing(false);
    }
  }

  /// View callback for the "确认调用 AI" dialog result. `true` means
  /// the user tapped "调用 AI"; `false` covers both "取消" and
  /// outside-tap / back-press dismiss. Must only be called when a
  /// confirm dialog is on screen.
  void onConfirmDialogResult(bool confirmed) {
    final pending = _pendingConfirm;
    if (pending == null) return;
    _pendingConfirm = null;
    if (!pending.isCompleted) pending.complete(confirmed);
  }

  /// View callback for the multi-draft bottom sheet result. `null`
  /// means the user dismissed the sheet (back swipe / X button);
  /// an empty list means the user explicitly deselected every row.
  /// Both abort the batch-add path; only a non-empty list triggers
  /// `addMultiple` and the `PopEvent`.
  void onBatchSheetResult(List<int>? selectedIndices) {
    final pending = _pendingBatch;
    if (pending == null) return;
    _pendingBatch = null;
    if (!pending.isCompleted) pending.complete(selectedIndices);
  }

  Future<bool> _askConfirm(int? remaining) {
    final completer = Completer<bool>();
    _pendingConfirm = completer;
    final quotaLine = remaining == null
        ? '今日不限制调用次数,是否继续?'
        : '将消耗 1 次 AI 调用(今日剩余 $remaining 次),是否继续?';
    _emit(ShowConfirmDialogEvent(quotaLine));
    return completer.future;
  }

  Future<List<int>?> _askBatchSelection(List<ReminderDraft> drafts) {
    final completer = Completer<List<int>?>();
    _pendingBatch = completer;
    _emit(ShowBatchSheetEvent(drafts));
    return completer.future;
  }

  void _setAnalyzing(bool value) {
    if (_isAnalyzing == value) return;
    _isAnalyzing = value;
    notifyListeners();
  }

  void _emit(AiAdjustEvent event) {
    if (_events.isClosed) return;
    _events.add(event);
  }

  @override
  void dispose() {
    // If a confirm / batch prompt is still pending when the view
    // goes away, resolve it with the "cancel" sentinel so the
    // outstanding `await` in `adjust` returns immediately instead
    // of leaking a dangling future.
    final confirm = _pendingConfirm;
    if (confirm != null && !confirm.isCompleted) {
      confirm.complete(false);
    }
    _pendingConfirm = null;
    final batch = _pendingBatch;
    if (batch != null && !batch.isCompleted) {
      batch.complete(null);
    }
    _pendingBatch = null;
    _events.close();
    super.dispose();
  }
}
