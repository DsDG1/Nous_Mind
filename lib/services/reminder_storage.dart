import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/reminder.dart';

/// Persists the full list of [Reminder]s as a single JSON string in
/// [SharedPreferences]. Simple and adequate for a basic reminders app.
class ReminderStorage {
  ReminderStorage(this._prefs);

  static const String _key = 'reminders';

  final SharedPreferences _prefs;

  /// Returns all stored reminders, or an empty list when nothing is stored.
  Future<List<Reminder>> loadAll() async {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) {
      return <Reminder>[];
    }
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((item) => Reminder.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  /// Replaces the entire stored list with [reminders].
  Future<void> saveAll(List<Reminder> reminders) async {
    final encoded = jsonEncode(reminders.map((r) => r.toJson()).toList());
    await _prefs.setString(_key, encoded);
  }
}
