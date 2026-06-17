import 'package:flutter/material.dart';

import 'package:nousmind/models/app_settings.dart';
import 'package:nousmind/services/settings_repository.dart';

/// Owns the in-memory [AppSettings] and writes every mutation through to
/// [SettingsRepository] before notifying listeners. The view model is
/// provided app-wide so a single instance backs the MaterialApp theme and
/// the settings subpages.
class SettingsViewModel extends ChangeNotifier {
  SettingsViewModel({
    required this._repository,
    required AppSettings initialSettings,
  }) : _settings = initialSettings;

  final SettingsRepository _repository;
  AppSettings _settings;

  /// Current settings snapshot. Always non-null.
  AppSettings get settings => _settings;

  /// Replaces the in-memory settings, persists them, and notifies
  /// listeners. The [next] value is the only authoritative source after
  /// the call returns — concurrent updates from outside are not merged.
  Future<void> _update(AppSettings next) async {
    _settings = next;
    notifyListeners();
    await _repository.save(next);
  }

  Future<void> setThemeMode(ThemeMode mode) =>
      _update(_settings.copyWith(themeMode: mode));

  Future<void> setSeedColor(AppSeedColor color) =>
      _update(_settings.copyWith(seedColor: color));

  Future<void> setVibrationEnabled(bool value) =>
      _update(_settings.copyWith(vibrationEnabled: value));

  Future<void> setQuietHoursEnabled(bool value) =>
      _update(_settings.copyWith(quietHoursEnabled: value));

  Future<void> setQuietHours(QuietHoursWindow window) =>
      _update(_settings.copyWith(quietHours: window));

  Future<void> setSnoozeDuration(SnoozeDuration snooze) =>
      _update(_settings.copyWith(snoozeDuration: snooze));

  Future<void> setAutoDeleteAfter24h(bool value) =>
      _update(_settings.copyWith(autoDeleteAfter24h: value));

  /// Toggles the user-facing "AI assistant is enabled" switch. Independent
  /// of [setAiApiKey] — the API key is preserved when the assistant is
  /// disabled, so re-enabling later does not require re-entering it.
  Future<void> setAiAssistantEnabled(bool value) =>
      _update(_settings.copyWith(aiAssistantEnabled: value));

  /// Records the user's one-time consent to the AI assistant (User
  /// Agreement + Privacy Policy) and flips the switch on in the same
  /// write. Listeners therefore never see a half-applied state where
  /// the switch is on but the consent flag is still `null`.
  Future<void> acceptAiConsent() => _update(
    _settings.copyWith(
      aiAssistantEnabled: true,
      aiConsentAcceptedAt: DateTime.now(),
    ),
  );

  /// Persists the AI assistant API key. Whitespace-only values and `null`
  /// both clear the key, so the storage layer never sees a blank string.
  Future<void> setAiApiKey(String? value) => _update(
    _settings.copyWith(
      aiApiKey: (value == null || value.trim().isEmpty) ? null : value.trim(),
    ),
  );

  /// Toggles the user-facing "中文 OCR" preference. Independent of the
  /// model's on-disk presence: the analyzer will fall back to Latin
  /// when the Chinese model is missing or fails, so flipping this
  /// switch never bricks OCR.
  Future<void> setChineseOcrEnabled(bool value) =>
      _update(_settings.copyWith(chineseOcrEnabled: value));

  /// Persists the user's custom system prompt for the "错误日志 → AI
  /// 分析" flow. `null` or whitespace clears the field, restoring the
  /// built-in default (`DeepSeekAnalyzer.defaultErrorAnalysisPrompt`).
  Future<void> setAiErrorAnalysisPrompt(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return _update(_settings.copyWith(clearAiErrorAnalysisPrompt: true));
    }
    return _update(_settings.copyWith(aiErrorAnalysisPrompt: trimmed));
  }

  /// Persists the user's custom system prompt template for the "AI
  /// 自动调整" flow in the reminder editor. `null` or whitespace
  /// clears the field, restoring the built-in default
  /// (`DeepSeekAnalyzer.defaultAdjustPromptTemplate`).
  Future<void> setAiAdjustPrompt(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return _update(_settings.copyWith(clearAiAdjustPrompt: true));
    }
    return _update(_settings.copyWith(aiAdjustPrompt: trimmed));
  }

  /// Persists the user's custom system prompt template for the "灵感分析"
  /// flow. `null` or whitespace clears the field, restoring the
  /// built-in default (`DeepSeekAnalyzer.defaultInspirationAnalysisPromptTemplate`).
  Future<void> setAiInspirationPrompt(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return _update(_settings.copyWith(clearAiInspirationPrompt: true));
    }
    return _update(_settings.copyWith(aiInspirationPrompt: trimmed));
  }

  // ---------------------------------------------------------------------------
  // AI usage-quota fields. The guard ([AiUsageGuard]) calls these to keep
  // its counters in sync with persisted state. The day-rollover logic lives
  // here, not in the guard, because the guard does not own the clock
  // boundary — the settings model does.
  // ---------------------------------------------------------------------------

  /// User-configurable hard ceiling on AI calls per local-day. Mirrors
  /// the input field on the AI settings page.
  Future<void> setAiDailyLimit(int value) =>
      _update(_settings.copyWith(aiDailyLimit: value));

  /// User-facing master switch for the daily-quota check. Defaults to
  /// `true`; when `false`, [AiUsageGuard] skips the ceiling check
  /// entirely while still enforcing the in-process cooldown.
  Future<void> setAiDailyLimitEnabled(bool value) =>
      _update(_settings.copyWith(aiDailyLimitEnabled: value));

  /// Returns the today's call count, rolling over to 0 when the
  /// current local-day differs from [aiCallsResetAt]. Read-only; the
  /// guard calls this rather than touching the field directly so the
  /// same rollover rule applies everywhere.
  int get aiCallsTodayRollover {
    final resetAt = _settings.aiCallsResetAt;
    if (resetAt == null) return _settings.aiCallsToday;
    if (_isSameLocalDay(resetAt, DateTime.now())) {
      return _settings.aiCallsToday;
    }
    return 0;
  }

  int get aiDailyLimit => _settings.aiDailyLimit;
  bool get aiDailyLimitEnabled => _settings.aiDailyLimitEnabled;
  int get aiCallsToday => aiCallsTodayRollover;

  int get aiCallsRemainingToday {
    final remaining = aiDailyLimit - aiCallsToday;
    return remaining < 0 ? 0 : remaining;
  }

  /// Bumps the in-memory counter after a successful AI call and
  /// persists the new value. If the persisted reset timestamp is from
  /// a previous local-day (or null) the counter resets to 1 instead
  /// of incrementing, so day boundaries never accumulate stale
  /// counts.
  Future<void> incrementAiCallsToday() {
    final now = DateTime.now();
    final current = _settings.aiCallsResetAt;
    final isNewDay = current == null || !_isSameLocalDay(current, now);
    final next = isNewDay ? 1 : _settings.aiCallsToday + 1;
    return _update(_settings.copyWith(aiCallsToday: next, aiCallsResetAt: now));
  }

  /// User-facing "clear today's usage" action exposed from the AI
  /// settings page. Drops the counter to 0 and clears the reset
  /// timestamp so the next call starts a fresh window.
  Future<void> resetAiUsage() {
    return _update(
      _settings.copyWith(aiCallsToday: 0, clearAiCallsResetAt: true),
    );
  }

  static bool _isSameLocalDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}
