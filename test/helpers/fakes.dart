// Shared fakes and helpers for widget tests.
//
// Conventions:
//   * Hand-rolled, no mocking framework. The project does not depend on
//     mockito or mocktail.
//   * Every fake implements or extends a real production class so the
//     compiler catches interface drift.
//   * Helpers below are exercised by both legacy unit tests (ai usage
//     guard, reminder AI adjust) and the new widget smoke tests.

import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:nousmind/models/app_settings.dart';
import 'package:nousmind/models/reminder.dart';
import 'package:nousmind/services/backup_service.dart';
import 'package:nousmind/services/database.dart';
import 'package:nousmind/services/inspiration_image_store.dart';
import 'package:nousmind/services/inspiration_repository.dart';
import 'package:nousmind/services/notification_service.dart';
import 'package:nousmind/services/reminder_cleanup_service.dart';
import 'package:nousmind/services/reminder_repository.dart';
import 'package:nousmind/services/settings_repository.dart';
import 'package:nousmind/services/tag_repository.dart';
import 'package:nousmind/viewmodels/reminders_view_model.dart';
import 'package:nousmind/viewmodels/settings_view_model.dart';
import 'package:nousmind/viewmodels/tags_view_model.dart';

// ---------------------------------------------------------------------------
// Settings: in-memory repository + view-model factory.
// Consolidated from the two copies that previously lived in
// ai_usage_guard_test.dart and reminder_ai_adjust_controller_test.dart.
// ---------------------------------------------------------------------------

/// In-memory [SettingsRepository] for tests. Implements only the surface
/// [SettingsViewModel] actually uses; the test never touches sqflite.
class MemorySettingsRepository implements SettingsRepository {
  MemorySettingsRepository([AppSettings? initial])
    : _stored = initial ?? const AppSettings();

  AppSettings _stored;
  AppSettings get stored => _stored;

  @override
  Future<AppSettings> load() async => _stored;

  @override
  Future<void> save(AppSettings settings) async {
    _stored = settings;
  }
}

/// Builds a [SettingsViewModel] backed by an in-memory repository. The
/// optional `initial` settings override individual fields without
/// requiring the test to build the whole object from scratch.
SettingsViewModel makeSettingsVm({
  bool aiAssistantEnabled = false,
  String? aiApiKey,
  int aiDailyLimit = 50,
  bool aiDailyLimitEnabled = true,
  int aiCallsToday = 0,
  DateTime? aiCallsResetAt,
  AppSettings? base,
}) {
  final initial = (base ?? const AppSettings()).copyWith(
    aiAssistantEnabled: aiAssistantEnabled,
    aiApiKey: aiApiKey,
    aiDailyLimit: aiDailyLimit,
    aiDailyLimitEnabled: aiDailyLimitEnabled,
    aiCallsToday: aiCallsToday,
    aiCallsResetAt: aiCallsResetAt,
  );
  final repo = MemorySettingsRepository(initial);
  return SettingsViewModel(repository: repo, initialSettings: initial);
}

// ---------------------------------------------------------------------------
// NotificationService: stub that no-ops every plugin call. The VM catches
// the resulting MissingPluginException anyway, but the stub keeps logs
// quiet and avoids depending on plugin behavior in CI.
// ---------------------------------------------------------------------------

class FakeNotificationService extends NotificationService {
  int scheduleCount = 0;
  int cancelCount = 0;

  @override
  Future<void> init({
    required void Function() onTapBody,
    void Function(NotificationResponse response)? onAction,
  }) async {}

  @override
  Future<bool> requestPermissions() async => true;

  @override
  Future<void> scheduleReminder(
    Reminder reminder, {
    bool vibrationEnabled = true,
    QuietHoursWindow? quietHours,
    String snoozeActionLabel = '稍后提醒',
  }) async {
    scheduleCount++;
  }

  @override
  Future<void> cancelReminder(String reminderId) async {
    cancelCount++;
  }

  @override
  Future<void> showImmediate({
    required String title,
    required String body,
    bool vibrationEnabled = true,
  }) async {}
}

// ---------------------------------------------------------------------------
// Image store: real implementation pointed at a temp directory so the
// VM's purge paths have something safe to call deleteByPath on.
// ---------------------------------------------------------------------------

class TestImageStore {
  TestImageStore._(this.directory, this.store);

  final Directory directory;
  final InspirationImageStore store;

  static Future<TestImageStore> create(Directory parent) async {
    final dir = Directory('${parent.path}/images')..createSync();
    return TestImageStore._(dir, InspirationImageStore(dir));
  }

  Future<void> dispose() async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }
}

// ---------------------------------------------------------------------------
// Test database: encapsulates the FFI + temp-dir boilerplate so individual
// tests just call `await TestDatabase.create()` in setUp and `dispose()`
// in tearDown.
// ---------------------------------------------------------------------------

class TestDatabase {
  TestDatabase._({
    required this.tempDir,
    required this.database,
    required this.reminderRepository,
    required this.inspirationRepository,
    required this.settingsRepository,
    required this.tagRepository,
    required this.backupService,
    required this.imageStore,
  });

  final Directory tempDir;
  final AppDatabase database;
  final ReminderRepository reminderRepository;
  final InspirationRepository inspirationRepository;
  final SettingsRepository settingsRepository;
  final TagRepository tagRepository;
  final BackupService backupService;
  final TestImageStore imageStore;

  static bool _ffiInitialised = false;

  /// One-shot FFI init. Safe to call from multiple tests in the same
  /// process — the second call is a no-op.
  static void ensureFfiInitialised() {
    if (_ffiInitialised) return;
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    _ffiInitialised = true;
  }

  static Future<TestDatabase> create({String? tag}) async {
    ensureFfiInitialised();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final tempDir = await Directory.systemTemp.createTemp(
      tag ?? 'flutter_app_widget_test_',
    );
    PathProviderPlatform.instance = _TempPathProvider(tempDir);
    final db = await AppDatabase.open(path: '${tempDir.path}/reminders.db');
    final reminderRepo = ReminderRepository(db);
    final inspirationRepo = InspirationRepository(db);
    final settingsRepo = SettingsRepository(db);
    final tagRepo = TagRepository(db);
    final imageStore = await TestImageStore.create(tempDir);
    final backup = BackupService(
      reminderRepository: reminderRepo,
      inspirationRepository: inspirationRepo,
      settingsRepository: settingsRepo,
      imageStore: imageStore.store,
    );
    return TestDatabase._(
      tempDir: tempDir,
      database: db,
      reminderRepository: reminderRepo,
      inspirationRepository: inspirationRepo,
      settingsRepository: settingsRepo,
      tagRepository: tagRepo,
      backupService: backup,
      imageStore: imageStore,
    );
  }

  Future<void> dispose() async {
    await database.close();
    await imageStore.dispose();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  }

  /// Inserts [reminders] into the active table so a freshly built VM
  /// sees them after bootstrap. Caller is responsible for ordering.
  Future<void> seedReminders(Iterable<Reminder> reminders) async {
    for (final r in reminders) {
      await reminderRepository.insert(r);
    }
  }
}

class _TempPathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _TempPathProvider(this.dir);

  final Directory dir;

  @override
  Future<String?> getTemporaryPath() async => dir.path;

  @override
  Future<String?> getApplicationDocumentsPath() async => dir.path;
}

// ---------------------------------------------------------------------------
// Reminders VM: composes the database, fake notification service, settings
// VM, and image store into a single ready-to-pump view model. The fake
// notification service keeps the bootstrap silent; the seeded reminders
// appear after one pumpAndSettle cycle.
// ---------------------------------------------------------------------------

class TestRemindersContext {
  TestRemindersContext._({
    required this.testDb,
    required this.settingsVm,
    required this.notifications,
    required this.remindersVm,
    required this.tagsVm,
  });

  final TestDatabase testDb;
  final SettingsViewModel settingsVm;
  final FakeNotificationService notifications;
  final RemindersViewModel remindersVm;
  final TagsViewModel tagsVm;

  static Future<TestRemindersContext> create({
    AppSettings? baseSettings,
  }) async {
    final db = await TestDatabase.create();
    final settingsVm = makeSettingsVm(base: baseSettings);
    final notifications = FakeNotificationService();
    final cleanup = ReminderCleanupService(
      repository: db.reminderRepository,
      notifications: notifications,
      imageStore: db.imageStore.store,
      settings: settingsVm,
    );
    final remindersVm = RemindersViewModel(
      db.reminderRepository,
      notifications,
      settingsVm,
      db.imageStore.store,
      cleanup,
    );
    final tagsVm = TagsViewModel(db.tagRepository);
    // The constructor fires `_bootstrap()` as an un-awaited future, so
    // unit tests that poke the VM right after construction would race
    // with bootstrap's `notifyListeners` (and trip ChangeNotifier's
    // "used after disposed" guard if the test disposes the VM first).
    // Awaiting refresh() forces bootstrap to complete before create()
    // returns.
    await remindersVm.refresh();
    await tagsVm.refresh();
    return TestRemindersContext._(
      testDb: db,
      settingsVm: settingsVm,
      notifications: notifications,
      remindersVm: remindersVm,
      tagsVm: tagsVm,
    );
  }

  Future<void> seedReminders(Iterable<Reminder> reminders) async {
    // Insert directly into the repository. The VM does not need to
    // be refreshed here — the home page test pumps the widget after
    // this call, which triggers a fresh bootstrap that will see the
    // new rows.
    await testDb.seedReminders(reminders);
  }

  /// Inserts [reminders] and triggers a VM refresh. Caller must wrap
  /// in [WidgetTester.runAsync] when used inside a `testWidgets`
  /// body, since the refresh path runs real I/O.
  Future<void> seedRemindersAndRefresh(Iterable<Reminder> reminders) async {
    await testDb.seedReminders(reminders);
    await remindersVm.refresh();
  }

  Future<void> dispose() async {
    remindersVm.dispose();
    tagsVm.dispose();
    settingsVm.dispose();
    await testDb.dispose();
  }
}

// ---------------------------------------------------------------------------
// Debug helpers: not part of the test surface, but useful when a widget
// test prints a widget tree.
// ---------------------------------------------------------------------------
