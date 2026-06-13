import 'package:flutter/foundation.dart';

import '../models/reminder_draft.dart';
import '../services/ai_analyzer.dart';

/// State machine for the AI assistant page.
enum AiAssistStatus { idle, analyzing, success, error }

/// Owns the in-flight analysis state for one assistant session.
///
/// `analyze(...)` clears any prior candidates, sets `status` to
/// `analyzing`, calls the [AiAnalyzer], and transitions to `success` with
/// the parsed drafts or to `error` with a Chinese error message. The
/// view model never throws to the UI — every failure is reflected in
/// `status` and `errorMessage`.
class AiAssistViewModel extends ChangeNotifier {
  AiAssistViewModel(this._analyzer);

  final AiAnalyzer _analyzer;

  AiAssistStatus _status = AiAssistStatus.idle;
  List<ReminderDraft> _candidates = const <ReminderDraft>[];
  String? _errorMessage;

  AiAssistStatus get status => _status;
  List<ReminderDraft> get candidates => List.unmodifiable(_candidates);
  String? get errorMessage => _errorMessage;
  bool get isLoading => _status == AiAssistStatus.analyzing;
  bool get isEmpty => _status == AiAssistStatus.success && _candidates.isEmpty;
  int get selectedCount => _candidates.where((c) => c.selected).length;

  /// Sends the supplied input to the analyzer. The caller passes the
  /// current API key (read from [SettingsViewModel] at tap time so live
  /// edits are honored), the device timezone, and the current `now`
  /// (used as "today" in the system prompt for resolving relative
  /// dates). Either or both of [text] and [imagePath] may be supplied.
  Future<void> analyze({
    required String apiKey,
    required String timezone,
    required DateTime now,
    String? text,
    String? imagePath,
  }) async {
    _status = AiAssistStatus.analyzing;
    _candidates = const <ReminderDraft>[];
    _errorMessage = null;
    notifyListeners();

    try {
      final drafts = await _analyzer.analyze(
        text: text,
        imagePath: imagePath,
        apiKey: apiKey,
        timezone: timezone,
        now: now,
      );
      _candidates = drafts;
      _status = AiAssistStatus.success;
      _errorMessage = null;
    } on AiAnalysisException catch (e) {
      _candidates = const <ReminderDraft>[];
      _status = AiAssistStatus.error;
      _errorMessage = e.message;
    } on Exception catch (e) {
      _candidates = const <ReminderDraft>[];
      _status = AiAssistStatus.error;
      _errorMessage = '分析失败:${e.toString()}';
    }
    notifyListeners();
  }

  /// Updates the editable fields of the candidate with [id]. `null`
  /// arguments leave the corresponding field unchanged.
  void updateCandidate(String id, {String? title, DateTime? suggestedTime}) {
    final index = _candidates.indexWhere((c) => c.id == id);
    if (index == -1) return;
    final original = _candidates[index];
    _candidates[index] = original.copyWith(
      title: title,
      suggestedTime: suggestedTime,
    );
    notifyListeners();
  }

  /// Removes the candidate with [id]. No-op if not found.
  void removeCandidate(String id) {
    final next = _candidates.where((c) => c.id != id).toList();
    if (next.length == _candidates.length) return;
    _candidates = next;
    if (_candidates.isEmpty && _status == AiAssistStatus.success) {
      // Stay in success so the empty state UI is shown.
    }
    notifyListeners();
  }

  /// Toggles the `selected` flag on the candidate with [id].
  void toggleSelected(String id, bool value) {
    final index = _candidates.indexWhere((c) => c.id == id);
    if (index == -1) return;
    _candidates[index] = _candidates[index].copyWith(selected: value);
    notifyListeners();
  }

  /// Clears any in-progress state and returns the page to its initial
  /// input form. Used when the user dismisses the review and wants to
  /// start over.
  void reset() {
    _status = AiAssistStatus.idle;
    _candidates = const <ReminderDraft>[];
    _errorMessage = null;
    notifyListeners();
  }
}
