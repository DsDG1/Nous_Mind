import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'package:nousmind/models/app_settings.dart';
import 'package:nousmind/services/database.dart';

class SettingsRepository {
  SettingsRepository(this._database);

  final AppDatabase _database;

  Future<AppSettings> load() async {
    final rows = await _database.db.query(
      'app_settings',
      where: 'id = ?',
      whereArgs: [1],
    );
    if (rows.isEmpty) {
      return const AppSettings();
    }
    try {
      final data = rows.first['data'] as String?;
      if (data == null) return const AppSettings();
      final decoded = jsonDecode(data);
      if (decoded is! Map<String, dynamic>) return const AppSettings();
      return AppSettings.fromJson(decoded);
    } on FormatException {
      return const AppSettings();
    }
  }

  Future<void> save(AppSettings settings) async {
    final data = jsonEncode(settings.toJson());
    await _database.db.insert('app_settings', {
      'id': 1,
      'data': data,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
