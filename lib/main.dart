import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:nested/nested.dart';
import 'package:provider/provider.dart';

import 'package:nousmind/app/app_error_hooks.dart';
import 'package:nousmind/app/database_error_app.dart';
import 'package:nousmind/app/notification_action_router.dart';
import 'package:nousmind/models/app_settings.dart';
import 'package:nousmind/router.dart';
import 'package:nousmind/services/ai_analyzer.dart';
import 'package:nousmind/services/ai_usage_guard.dart';
import 'package:nousmind/services/backup_service.dart';
import 'package:nousmind/services/chinese_ocr_installer.dart';
import 'package:nousmind/services/database.dart';
import 'package:nousmind/services/error_log_service.dart';
import 'package:nousmind/services/inspiration_image_store.dart';
import 'package:nousmind/services/inspiration_repository.dart';
import 'package:nousmind/services/notification_service.dart';
import 'package:nousmind/services/quick_settings_tile_bridge.dart';
import 'package:nousmind/services/reminder_cleanup_service.dart';
import 'package:nousmind/services/reminder_repository.dart';
import 'package:nousmind/services/settings_repository.dart';
import 'package:nousmind/services/tag_repository.dart';
import 'package:nousmind/viewmodels/inspirations_view_model.dart';
import 'package:nousmind/viewmodels/reminders_view_model.dart';
import 'package:nousmind/viewmodels/settings_view_model.dart';
import 'package:nousmind/viewmodels/tags_view_model.dart';
import 'package:nousmind/widgets/reminder_popup.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  installAppErrorHooks();

  AppDatabase? database;
  try {
    database = await AppDatabase.open();
  } on Exception catch (error, stackTrace) {
    developer.log(
      'Failed to open database',
      error: error,
      stackTrace: stackTrace,
    );
    runApp(const DatabaseErrorApp());
    return;
  }
  final settingsRepository = SettingsRepository(database);
  final initialSettings = await settingsRepository.load();
  final reminderRepository = ReminderRepository(database);
  final inspirationRepository = InspirationRepository(database);
  final tagRepository = TagRepository(database);
  final imageStore = await InspirationImageStore.create();
  final notifications = NotificationService();
  const actionRouter = NotificationActionRouter();
  await notifications.init(
    onTapBody: () => router.go('/'),
    onAction: actionRouter.route,
  );
  final timezone = await _readTimezone();

  // Install the Quick Settings Tile bridge before runApp so the native
  // → Dart hot-path handler is registered in time for any click that
  // arrives via MainActivity.onNewIntent while the app is already
  // running. The cold-start case is handled by the post-frame
  // consumePending() below.
  QuickSettingsTileBridge.instance.init(onOpenCreate: navigateToQuickAddEditor);

  runApp(
    RemindersApp(
      settingsRepository: settingsRepository,
      initialSettings: initialSettings,
      reminderRepository: reminderRepository,
      inspirationRepository: inspirationRepository,
      tagRepository: tagRepository,
      imageStore: imageStore,
      notifications: notifications,
      aiAnalyzer: DeepSeekAnalyzer(),
      timezone: timezone,
    ),
  );

  // Drain any Quick Settings Tile click that landed before Dart was
  // alive. The post-frame callback ensures the router is mounted.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(QuickSettingsTileBridge.instance.consumePending());
  });
}

Future<String> _readTimezone() async {
  try {
    final info = await FlutterTimezone.getLocalTimezone();
    return info.identifier;
  } on Exception {
    return 'UTC';
  }
}

class RemindersApp extends StatefulWidget {
  const RemindersApp({
    super.key,
    required this.settingsRepository,
    required this.initialSettings,
    required this.reminderRepository,
    required this.inspirationRepository,
    required this.tagRepository,
    required this.imageStore,
    required this.notifications,
    required this.aiAnalyzer,
    required this.timezone,
  });

  final SettingsRepository settingsRepository;
  final AppSettings initialSettings;
  final ReminderRepository reminderRepository;
  final InspirationRepository inspirationRepository;
  final TagRepository tagRepository;
  final InspirationImageStore imageStore;
  final NotificationService notifications;
  final AiAnalyzer aiAnalyzer;
  final String timezone;

  @override
  State<RemindersApp> createState() => _RemindersAppState();
}

class _RemindersAppState extends State<RemindersApp>
    with WidgetsBindingObserver {
  late final BackupService _backup;

  @override
  void initState() {
    super.initState();
    _backup = BackupService(
      reminderRepository: widget.reminderRepository,
      inspirationRepository: widget.inspirationRepository,
      settingsRepository: widget.settingsRepository,
      imageStore: widget.imageStore,
    );
    // Tag view model warm-up mirrors the backup stats call above:
    // a single async read of the `tags` table so the editor,
    // home page, and settings subpage can paint real tag data on
    // first entry instead of the empty placeholder. The provider
    // is lazy (it boots on first `context.read/watch`), so this is
    // purely about the cold-start timing.
    // ignore: unawaited_futures
    widget.tagRepository.getAll();
    // Warm the stats cache so the settings page can paint real numbers
    // on its first entry instead of the dash placeholder.
    unawaited(_backup.refreshStats());
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _backup.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      return;
    }
    final navigatorContext = rootNavigatorKey.currentContext;
    if (navigatorContext == null) {
      return;
    }
    Provider.of<RemindersViewModel>(
      navigatorContext,
      listen: false,
    ).onAppResumed();
    Provider.of<InspirationsViewModel>(
      navigatorContext,
      listen: false,
    ).onAppResumed();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: <SingleChildWidget>[
        ChangeNotifierProvider<SettingsViewModel>(
          create: (_) => SettingsViewModel(
            repository: widget.settingsRepository,
            initialSettings: widget.initialSettings,
          ),
        ),
        // Wraps the AI usage quota + cooldown clock. Reads through the
        // SettingsViewModel above; the provider's `create` callback
        // runs lazily on first `context.watch/read`, so the dependency
        // is satisfied even though `ChangeNotifierProvider` builds its
        // instance independently.
        Provider<AiUsageGuard>(
          create: (context) =>
              AiUsageGuard(settings: context.read<SettingsViewModel>()),
        ),
        ChangeNotifierProvider<RemindersViewModel>(
          create: (context) {
            final settings = context.read<SettingsViewModel>();
            final cleanup = ReminderCleanupService(
              repository: widget.reminderRepository,
              notifications: widget.notifications,
              imageStore: widget.imageStore,
              settings: settings,
            );
            final vm = RemindersViewModel(
              widget.reminderRepository,
              widget.notifications,
              settings,
              widget.imageStore,
              cleanup,
            );
            vm.onReminderDue = (reminder) {
              final navigatorState = rootNavigatorKey.currentState;
              if (navigatorState == null) {
                return;
              }
              showReminderPopup(
                context: navigatorState.context,
                title: reminder.title,
                description: reminder.description,
                snoozeLabel: '稍后提醒（${settings.settings.snoozeDuration.label}）',
                onSnooze: () => vm.snoozeReminder(
                  reminder.id,
                  settings.settings.snoozeDuration.duration,
                ),
              );
            };
            return vm;
          },
        ),
        ChangeNotifierProvider<InspirationsViewModel>(
          create: (context) => InspirationsViewModel(
            widget.inspirationRepository,
            widget.imageStore,
            context.read<SettingsViewModel>(),
          ),
        ),
        // Tags live in their own view model so the editor, home
        // page, and settings subpage can all `context.watch` the
        // same in-memory list. Inserted before the AI provider so
        // the AI controller (which is created lazily by the
        // editor's local provider) can read tags via
        // `context.read<TagsViewModel>()`.
        ChangeNotifierProvider<TagsViewModel>(
          create: (_) => TagsViewModel(widget.tagRepository),
        ),
        ChangeNotifierProvider<ErrorLogService>(
          create: (_) => attachGlobalErrorLog(ErrorLogService()),
        ),
        ChangeNotifierProvider<ChineseOcrInstaller>(
          create: (_) => ChineseOcrInstaller(),
        ),
        Provider<AiAnalyzer>(
          create: (context) {
            widget.aiAnalyzer.setChineseOcrProvider(
              () =>
                  context.read<SettingsViewModel>().settings.chineseOcrEnabled,
            );
            return widget.aiAnalyzer;
          },
        ),
        Provider<InspirationImageStore>.value(value: widget.imageStore),
        Provider<NotificationService>.value(value: widget.notifications),
        Provider<BackupService>.value(value: _backup),
        Provider<TagRepository>.value(value: widget.tagRepository),
      ],
      child: Selector<SettingsViewModel, _ThemeTuple>(
        selector: (_, vm) => _ThemeTuple(
          mode: vm.settings.themeMode,
          seed: vm.settings.seedColor,
        ),
        builder: (context, selected, _) {
          final seed = selected.seed.color;
          return MaterialApp.router(
            title: 'NousMind',
            themeMode: selected.mode,
            theme: ThemeData(
              useMaterial3: true,
              colorScheme: ColorScheme.fromSeed(seedColor: seed),
            ),
            darkTheme: ThemeData(
              useMaterial3: true,
              colorScheme: ColorScheme.fromSeed(
                seedColor: seed,
                brightness: Brightness.dark,
              ),
            ),
            routerConfig: router,
          );
        },
      ),
    );
  }
}

/// Selector key used by the outer [MaterialApp.router] so only theme-relevant
/// changes from [SettingsViewModel] rebuild the entire app shell.
class _ThemeTuple {
  const _ThemeTuple({required this.mode, required this.seed});

  final ThemeMode mode;
  final AppSeedColor seed;

  @override
  bool operator ==(Object other) =>
      other is _ThemeTuple && other.mode == mode && other.seed == seed;

  @override
  int get hashCode => Object.hash(mode, seed);
}
