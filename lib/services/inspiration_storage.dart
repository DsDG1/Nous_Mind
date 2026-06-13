import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/inspiration.dart';

/// Persists the full list of [Inspiration]s as a single JSON string in
/// [SharedPreferences]. Simple and adequate for a basic inspirations app.
class InspirationStorage {
  InspirationStorage(this._prefs);

  static const String _key = 'inspirations';

  final SharedPreferences _prefs;

  /// Returns all stored inspirations, or an empty list when nothing is stored.
  Future<List<Inspiration>> loadAll() async {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) {
      return <Inspiration>[];
    }
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((item) => Inspiration.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  /// Replaces the entire stored list with [inspirations].
  Future<void> saveAll(List<Inspiration> inspirations) async {
    final encoded = jsonEncode(inspirations.map((i) => i.toJson()).toList());
    await _prefs.setString(_key, encoded);
  }
}
