import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/inspiration.dart';
import '../models/reminder.dart';
import 'inspiration_image_store.dart';
import 'inspiration_repository.dart';
import 'reminder_repository.dart';
import 'settings_repository.dart';

/// Snapshot of the user's data for display on the data management subpage
/// and the settings home stats card.
class StorageStats {
  const StorageStats({
    required this.reminderCount,
    required this.inspirationCount,
    required this.imageBytes,
  });

  final int reminderCount;
  final int inspirationCount;
  final int imageBytes;
}

class BackupResult {
  const BackupResult({
    required this.remindersImported,
    required this.inspirationsImported,
  });

  final int remindersImported;
  final int inspirationsImported;
}

/// Aggregates reminders, inspirations, settings, and their image files
/// behind a single import/export API for the data management subpage.
///
/// JSON shape (versioned for forward-compatibility):
/// ```
/// {
///   "version": 1,
///   "exported_at": "<ISO8601>",
///   "reminders": [Reminder.toJson()...],
///   "inspirations": [Inspiration.toJson()...],
///   "settings": AppSettings.toJson()
/// }
/// ```
class BackupService {
  BackupService({
    required ReminderRepository reminderRepository,
    required InspirationRepository inspirationRepository,
    required SettingsRepository settingsRepository,
    required InspirationImageStore imageStore,
  }) : _reminders = reminderRepository,
       _inspirations = inspirationRepository,
       _settings = settingsRepository,
       // ignore: prefer_initializing_formals
       _imageStore = imageStore;

  final ReminderRepository _reminders;
  final InspirationRepository _inspirations;
  final SettingsRepository _settings;
  final InspirationImageStore _imageStore;

  static const int _backupVersion = 1;

  /// Counts records and sums the on-disk size of the image directory.
  /// Cheap enough to call from build methods.
  Future<StorageStats> getStats() async {
    final reminderCount = await _reminders.count();
    final inspirationCount = await _inspirations.count();
    final imageBytes = await _sumImageBytes();
    return StorageStats(
      reminderCount: reminderCount,
      inspirationCount: inspirationCount,
      imageBytes: imageBytes,
    );
  }

  Future<int> _sumImageBytes() async {
    final dir = _imageStore.imagesDir;
    if (!await dir.exists()) return 0;
    var total = 0;
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is File) {
        try {
          total += await entity.length();
        } on FileSystemException {
          // File disappeared between listing and stat-ing; ignore.
        }
      }
    }
    return total;
  }

  /// Serialises the current reminders, inspirations, and settings into
  /// a JSON file under the system temp directory and returns the file
  /// path. The caller is responsible for sharing / saving the file.
  Future<File> exportToFile() async {
    final reminders = await _reminders.getAll();
    final inspirations = await _inspirations.getAll();
    final settings = await _settings.load();
    final payload = <String, dynamic>{
      'version': _backupVersion,
      'exported_at': DateTime.now().toIso8601String(),
      'reminders': reminders.map((r) => r.toJson()).toList(),
      'inspirations': inspirations.map((i) => i.toJson()).toList(),
      'settings': settings.toJson(),
    };
    final json = const JsonEncoder.withIndent('  ').convert(payload);
    final dir = await getTemporaryDirectory();
    final stamp = _timestampForFilename(DateTime.now());
    final file = File(p.join(dir.path, 'nous_backup_$stamp.json'));
    await file.writeAsString(json, flush: true);
    return file;
  }

  /// Reads [file] and inserts the contained reminders and inspirations
  /// into the database. Entries whose `id` already exists are skipped, so
  /// importing the same backup twice is a no-op for duplicates. Settings
  /// are intentionally not restored — overwriting theme and notification
  /// preferences without confirmation would be hostile.
  Future<BackupResult> importFromFile(File file) async {
    final content = await file.readAsString();
    final decoded = jsonDecode(content);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Backup file root is not an object');
    }
    final remindersRaw = decoded['reminders'];
    final inspirationsRaw = decoded['inspirations'];
    if (remindersRaw is! List || inspirationsRaw is! List) {
      throw const FormatException('Backup file is missing required lists');
    }

    final existingReminders = {
      for (final r in await _reminders.getAll()) r.id: r,
    };
    final existingInspirations = {
      for (final i in await _inspirations.getAll()) i.id: i,
    };

    var remindersImported = 0;
    for (final item in remindersRaw) {
      if (item is! Map<String, dynamic>) continue;
      try {
        final reminder = Reminder.fromJson(item);
        if (existingReminders.containsKey(reminder.id)) continue;
        await _reminders.insert(reminder);
        existingReminders[reminder.id] = reminder;
        remindersImported += 1;
      } on Exception {
        // Skip malformed entries silently; the import still succeeds.
      }
    }

    var inspirationsImported = 0;
    for (final item in inspirationsRaw) {
      if (item is! Map<String, dynamic>) continue;
      try {
        final inspiration = Inspiration.fromJson(item);
        if (existingInspirations.containsKey(inspiration.id)) continue;
        await _inspirations.insert(inspiration);
        existingInspirations[inspiration.id] = inspiration;
        inspirationsImported += 1;
      } on Exception {
        // Skip malformed entries silently; the import still succeeds.
      }
    }

    return BackupResult(
      remindersImported: remindersImported,
      inspirationsImported: inspirationsImported,
    );
  }

  /// Formats a byte count as a human-readable string. Used by the data
  /// management subpage to render image storage usage.
  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static String _timestampForFilename(DateTime time) {
    String two(int n) => n.toString().padLeft(2, '0');
    String four(int n) => n.toString().padLeft(4, '0');
    return '${four(time.year)}${two(time.month)}${two(time.day)}'
        '_${two(time.hour)}${two(time.minute)}${two(time.second)}';
  }
}
