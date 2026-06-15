import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:nousmind/models/inspiration.dart';
import 'package:nousmind/models/reminder.dart';
import 'package:nousmind/services/inspiration_image_store.dart';
import 'package:nousmind/services/inspiration_repository.dart';
import 'package:nousmind/services/reminder_repository.dart';
import 'package:nousmind/services/settings_repository.dart';

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

  /// Latest stats snapshot. Settings UIs read this via [ValueListenableBuilder]
  /// so they can paint the previously-cached value instantly on entry, while
  /// [refreshStats] runs in the background and updates the same notifier.
  final ValueNotifier<StorageStats?> statsNotifier =
      ValueNotifier<StorageStats?>(null);

  /// Shared in-flight future so concurrent callers (e.g. multiple settings
  /// rebuilds within the same frame) coalesce into a single computation.
  Future<StorageStats>? _inflight;

  static const int _backupVersion = 1;

  /// Re-runs the underlying counts and writes the new snapshot to
  /// [statsNotifier]. Single-flight: parallel calls share the same future.
  Future<StorageStats> refreshStats() {
    final pending = _inflight;
    if (pending != null) return pending;
    final future = _computeStats().whenComplete(() => _inflight = null);
    _inflight = future;
    return future;
  }

  /// Backwards-compatible wrapper that callers can still await without
  /// touching [statsNotifier]. Identical semantics to [refreshStats] now.
  Future<StorageStats> getStats() => refreshStats();

  /// Called after mutations (import, clear) to keep the cached value fresh.
  /// We do not clear the old value first so the UI does not flicker to `—`
  /// before the new numbers arrive.
  Future<StorageStats> invalidateAndRefresh() => refreshStats();

  Future<StorageStats> _computeStats() async {
    final results = await Future.wait<Object?>(<Future<Object?>>[
      _reminders.count(),
      _inspirations.count(),
      _sumImageBytes(),
    ]);
    final stats = StorageStats(
      reminderCount: results[0]! as int,
      inspirationCount: results[1]! as int,
      imageBytes: results[2]! as int,
    );
    statsNotifier.value = stats;
    return stats;
  }

  /// Sums the byte sizes of every file directly under the images directory.
  /// File-stat calls are issued in parallel via [Future.wait], so the cost
  /// is bounded by the slowest single stat instead of the directory size.
  Future<int> _sumImageBytes() async {
    final dir = _imageStore.imagesDir;
    if (!await dir.exists()) return 0;
    final futures = <Future<int>>[];
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is File) {
        futures.add(_safeLength(entity));
      }
    }
    if (futures.isEmpty) return 0;
    final lengths = await Future.wait(futures);
    return lengths.fold<int>(0, (sum, value) => sum + value);
  }

  Future<int> _safeLength(File file) async {
    try {
      return await file.length();
    } on FileSystemException {
      // File disappeared between listing and stat-ing; ignore.
      return 0;
    }
  }

  /// Serialises the current reminders, inspirations, and settings into
  /// a JSON file under the system temp directory and returns the file
  /// path. The caller is responsible for sharing / saving the file.
  ///
  /// Trashed reminders (`is_deleted = true`) are intentionally excluded
  /// from the export — the trash is a transient safety net for the
  /// last 30 days, not a long-term archive. Callers that want a fuller
  /// export can read the repository directly.
  ///
  /// JSON encoding is offloaded to a background isolate via [compute] so
  /// large backups do not stall the UI thread.
  Future<File> exportToFile() async {
    final reminders = await _reminders.getAllActive();
    final inspirations = await _inspirations.getAll();
    final settings = await _settings.load();
    final input = _ExportInput(
      version: _backupVersion,
      exportedAt: DateTime.now().toIso8601String(),
      reminders: reminders.map((r) => r.toJson()).toList(growable: false),
      inspirations: inspirations.map((i) => i.toJson()).toList(growable: false),
      settings: settings.toJson(),
    );
    final json = await compute(_buildPayloadAndEncode, input);
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
  ///
  /// Inserts run in a single batched transaction per table, so importing
  /// large backups completes in roughly one round-trip per table instead
  /// of one per record.
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

    final existingReminderIds = await _reminders.listIds();
    final existingInspirationIds = await _inspirations.listIds();

    final toInsertReminders = <Reminder>[];
    for (final item in remindersRaw) {
      if (item is! Map<String, dynamic>) continue;
      try {
        final reminder = Reminder.fromJson(item);
        if (existingReminderIds.contains(reminder.id)) continue;
        existingReminderIds.add(reminder.id);
        toInsertReminders.add(reminder);
      } on Exception {
        // Skip malformed entries silently; the import still succeeds.
      }
    }

    final toInsertInspirations = <Inspiration>[];
    for (final item in inspirationsRaw) {
      if (item is! Map<String, dynamic>) continue;
      try {
        final inspiration = Inspiration.fromJson(item);
        if (existingInspirationIds.contains(inspiration.id)) continue;
        existingInspirationIds.add(inspiration.id);
        toInsertInspirations.add(inspiration);
      } on Exception {
        // Skip malformed entries silently; the import still succeeds.
      }
    }

    if (toInsertReminders.isNotEmpty) {
      await _reminders.insertAll(toInsertReminders);
    }
    if (toInsertInspirations.isNotEmpty) {
      await _inspirations.insertAll(toInsertInspirations);
    }

    return BackupResult(
      remindersImported: toInsertReminders.length,
      inspirationsImported: toInsertInspirations.length,
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

  void dispose() {
    statsNotifier.dispose();
  }
}

/// Plain-data carrier for export payloads. All fields are isolate-sendable
/// (ints, Strings, and nested Maps/Lists of the same) so this class can be
/// passed to [compute] without copying through JSON first.
class _ExportInput {
  const _ExportInput({
    required this.version,
    required this.exportedAt,
    required this.reminders,
    required this.inspirations,
    required this.settings,
  });

  final int version;
  final String exportedAt;
  final List<Map<String, dynamic>> reminders;
  final List<Map<String, dynamic>> inspirations;
  final Map<String, dynamic> settings;
}

/// Top-level so it can be invoked by [compute]: it must be a static or
/// top-level function with a single positional argument.
String _buildPayloadAndEncode(_ExportInput input) {
  final payload = <String, dynamic>{
    'version': input.version,
    'exported_at': input.exportedAt,
    'reminders': input.reminders,
    'inspirations': input.inspirations,
    'settings': input.settings,
  };
  return const JsonEncoder.withIndent('  ').convert(payload);
}
