import 'package:flutter/material.dart';

import '../models/app_settings.dart';
import '../services/settings_storage.dart';

/// Owns the in-memory [AppSettings] and writes every mutation through to
/// [SettingsStorage] before notifying listeners. The view model is provided
/// app-wide so a single instance backs the MaterialApp theme and the
/// settings subpages.
class SettingsViewModel extends ChangeNotifier {
  SettingsViewModel(this._storage) : _settings = _storage.load();

  final SettingsStorage _storage;
  AppSettings _settings;

  /// Current settings snapshot. Always non-null.
  AppSettings get settings => _settings;

  /// Replaces the in-memory settings, persists them, and notifies
  /// listeners. The [next] value is the only authoritative source after
  /// the call returns — concurrent updates from outside are not merged.
  Future<void> _update(AppSettings next) async {
    _settings = next;
    notifyListeners();
    await _storage.save(next);
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

  Future<void> setLeadTime(LeadTime leadTime) =>
      _update(_settings.copyWith(leadTime: leadTime));

  Future<void> setSnoozeDuration(SnoozeDuration snooze) =>
      _update(_settings.copyWith(snoozeDuration: snooze));
}
