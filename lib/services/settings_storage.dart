import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';

/// Persists [AppSettings] as a single JSON string under one key in
/// [SharedPreferences]. Reads are synchronous because [SharedPreferences]
/// loads all keys into memory up front; writes are awaited so callers
/// observe a durable change before continuing.
class SettingsStorage {
  SettingsStorage(this._prefs);

  static const String _key = 'app_settings';

  final SharedPreferences _prefs;

  /// Returns the stored [AppSettings], or the default-constructed
  /// [AppSettings] when nothing has ever been persisted.
  AppSettings load() {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) {
      return const AppSettings();
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return const AppSettings();
      }
      return AppSettings.fromJson(decoded);
    } on FormatException {
      return const AppSettings();
    }
  }

  Future<void> save(AppSettings settings) async {
    await _prefs.setString(_key, jsonEncode(settings.toJson()));
  }
}
