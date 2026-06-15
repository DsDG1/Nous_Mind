import 'package:flutter/material.dart';

import '../models/app_settings.dart';
import '../services/settings_repository.dart';

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

  /// Persists the user's custom prompt template for the AI assistant's
  /// reminder-extraction flow. `null` or whitespace clears the field,
  /// which makes [DeepSeekAnalyzer] fall back to its built-in default
  /// (`defaultAssistantPromptTemplate`).
  Future<void> setAiAssistantPrompt(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return _update(_settings.copyWith(clearAiAssistantPrompt: true));
    }
    return _update(_settings.copyWith(aiAssistantPrompt: trimmed));
  }

  /// Persists the user's custom system prompt for the "AI 一键润色"
  /// flow. `null` or whitespace clears the field, restoring the
  /// built-in default (`DeepSeekAnalyzer.defaultPolishPrompt`).
  Future<void> setAiPolishPrompt(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return _update(_settings.copyWith(clearAiPolishPrompt: true));
    }
    return _update(_settings.copyWith(aiPolishPrompt: trimmed));
  }

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
}
