import 'dart:async';
import 'dart:developer' as developer;

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

import '../models/reminder_draft.dart';
import '../services/ai_analyzer.dart';
import '../services/error_log_service.dart';
import 'settings_view_model.dart';

/// State machine for the AI assistant page.
enum AiAssistStatus { idle, analyzing, success, error }

/// Owns the in-flight analysis state for one assistant session.
///
/// `analyze(...)` clears any prior candidates, sets `status` to
/// `analyzing`, calls the [AiAnalyzer], and transitions to `success` with
/// the parsed drafts or to `error` with a Chinese error message. The
/// view model never throws to the UI — every failure is reflected in
/// `status` and `errorMessage`.
///
/// The view model also enforces two defensive layers:
///   * **Auth lockout** — three consecutive [AiAuthException] failures
///     flip [isLockedDueToAuth] to `true`, disabling analysis until the
///     user changes the API key in settings. The lock is only lifted by
///     [_onSettingsChanged] observing a new key value, so a transient
///     success cannot unlock a broken key.
///   * **Click throttle** — three `analyze` calls within a rolling
///     3-second window flip [isThrottled] on for 10 seconds, blocking
///     the button and surfacing a countdown banner. The lock self-clears
///     when the window expires.
class AiAssistViewModel extends ChangeNotifier {
  AiAssistViewModel(
    this._analyzer, {
    required SettingsViewModel settings,
    ErrorLogService? errorLog,
    // ignore: prefer_initializing_formals
  }) : _settings = settings,
       // ignore: prefer_initializing_formals
       _errorLog = errorLog {
    _lastSeenApiKey = _settings.settings.aiApiKey;
    _settings.addListener(_onSettingsChanged);
  }

  /// Number of consecutive [AiAuthException] failures that flips the
  /// lockout on. The lockout banner in [AiAssistantPage] surfaces this
  /// number in its copy, so it is public.
  static const int authLockThreshold = 3;

  /// Rolling window over which click timestamps are counted.
  @visibleForTesting
  static const Duration clickWindow = Duration(seconds: 3);

  /// Maximum clicks permitted inside [clickWindow] before throttling.
  @visibleForTesting
  static const int maxClicksInWindow = 3;

  /// Duration of the throttle after the threshold is hit.
  @visibleForTesting
  static const Duration throttleDuration = Duration(seconds: 10);

  final AiAnalyzer _analyzer;
  final SettingsViewModel _settings;
  final ErrorLogService? _errorLog;

  AiAssistStatus _status = AiAssistStatus.idle;
  List<ReminderDraft> _candidates = const <ReminderDraft>[];
  String? _errorMessage;

  int _consecutiveAuthFailures = 0;
  bool _isLockedDueToAuth = false;
  final List<DateTime> _recentClickTimestamps = <DateTime>[];
  DateTime? _throttleUntil;
  String? _lastSeenApiKey;

  AiAssistStatus get status => _status;
  List<ReminderDraft> get candidates => List.unmodifiable(_candidates);
  String? get errorMessage => _errorMessage;
  bool get isLoading => _status == AiAssistStatus.analyzing;
  bool get isEmpty => _status == AiAssistStatus.success && _candidates.isEmpty;
  int get selectedCount => _candidates.where((c) => c.selected).length;

  /// True after [authLockThreshold] consecutive auth failures. The user
  /// must update the API key in settings to clear this flag.
  bool get isLockedDueToAuth => _isLockedDueToAuth;

  /// Number of auth failures counted so far, exposed for tests and the
  /// banner copy.
  int get consecutiveAuthFailures => _consecutiveAuthFailures;

  /// True while the click throttle is active.
  bool get isThrottled {
    final until = _throttleUntil;
    if (until == null) return false;
    if (clock.now().isBefore(until)) return true;
    // Expired but not yet cleared; clear lazily so subsequent reads are
    // consistent without forcing a rebuild.
    _throttleUntil = null;
    return false;
  }

  /// Whole-second countdown for the active throttle. Returns `0` when
  /// the throttle is not active.
  int get throttleRemainingSeconds {
    final until = _throttleUntil;
    if (until == null) return 0;
    final remaining = until.difference(clock.now()).inSeconds;
    if (remaining <= 0) {
      _throttleUntil = null;
      return 0;
    }
    return remaining;
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettingsChanged);
    super.dispose();
  }

  /// Resets the auth failure counter and lockout flag when the user
  /// changes the stored API key. Other settings changes are ignored.
  void _onSettingsChanged() {
    final current = _settings.settings.aiApiKey;
    if (current == _lastSeenApiKey) return;
    _lastSeenApiKey = current;
    _consecutiveAuthFailures = 0;
    if (_isLockedDueToAuth) {
      _isLockedDueToAuth = false;
      notifyListeners();
    }
  }

  /// Sends the supplied input to the analyzer. The caller passes the
  /// current API key (read from [SettingsViewModel] at tap time so live
  /// edits are honored), the device timezone, and the current `now`
  /// (used as "today" in the system prompt for resolving relative
  /// dates). Either or both of [text] and [imagePath] may be supplied.
  ///
  /// Returns early without touching [status] when the auth lockout or
  /// click throttle is active. The first [maxClicksInWindow] clicks
  /// inside [clickWindow] are honoured; the third click flips the
  /// throttle on and itself does not call the analyzer.
  Future<void> analyze({
    required String apiKey,
    required String timezone,
    required DateTime now,
    String? text,
    String? imagePath,
  }) async {
    if (_isLockedDueToAuth) return;
    if (isThrottled) return;

    // Prune the click window before deciding whether this click is the
    // threshold-breaching one.
    _recentClickTimestamps.removeWhere((t) => now.difference(t) > clickWindow);
    _recentClickTimestamps.add(now);
    if (_recentClickTimestamps.length >= maxClicksInWindow) {
      _throttleUntil = now.add(throttleDuration);
      _recentClickTimestamps.clear();
      notifyListeners();
      return;
    }

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
      _consecutiveAuthFailures = 0;
    } on AiAuthException catch (e, st) {
      developer.log('AI 分析失败', error: e, stackTrace: st);
      _errorLog?.record(source: 'AiAssistViewModel', error: e, stackTrace: st);
      _candidates = const <ReminderDraft>[];
      _status = AiAssistStatus.error;
      _errorMessage = e.message;
      _consecutiveAuthFailures++;
      if (_consecutiveAuthFailures >= authLockThreshold) {
        _isLockedDueToAuth = true;
      }
    } catch (e, st) {
      developer.log('AI 分析失败', error: e, stackTrace: st);
      _errorLog?.record(source: 'AiAssistViewModel', error: e, stackTrace: st);
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

  /// Sets the error state with [message] and notifies listeners.
  /// Used by the UI layer when a previously-uncaught error escapes the
  /// [analyze] method (e.g. a Dart [Error] that bypasses [Exception]
  /// handlers deeper in the call stack).
  void setError(String message) {
    _status = AiAssistStatus.error;
    _errorMessage = message;
    _candidates = const <ReminderDraft>[];
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
