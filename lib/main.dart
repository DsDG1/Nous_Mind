import 'dart:async';
import 'dart:developer' as developer;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:nested/nested.dart';
import 'package:provider/provider.dart';

import 'models/app_settings.dart';
import 'router.dart';
import 'services/ai_analyzer.dart';
import 'services/backup_service.dart';
import 'services/chinese_ocr_installer.dart';
import 'services/database.dart';
import 'services/error_log_service.dart';
import 'services/inspiration_image_store.dart';
import 'services/inspiration_repository.dart';
import 'services/notification_service.dart';
import 'services/quick_settings_tile_bridge.dart';
import 'services/reminder_repository.dart';
import 'services/settings_repository.dart';
import 'viewmodels/ai_assist_view_model.dart';
import 'viewmodels/inspirations_view_model.dart';
import 'viewmodels/reminders_view_model.dart';
import 'viewmodels/settings_view_model.dart';
import 'widgets/reminder_popup.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Capture uncaught framework and platform errors so the About page can
  // surface them. These handlers run outside the widget tree, hence the
  // global handle installed later in the Provider.
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    globalErrorLog?.record(
      source: 'FlutterError',
      error: details.exceptionAsString(),
      stackTrace: details.stack,
    );
  };
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    globalErrorLog?.record(
      source: 'PlatformDispatcher',
      error: error,
      stackTrace: stack,
    );
    return true;
  };

  AppDatabase? database;
  try {
    database = await AppDatabase.open();
  } on Exception catch (error, stackTrace) {
    developer.log(
      'Failed to open database',
      error: error,
      stackTrace: stackTrace,
    );
    runApp(const _DatabaseErrorApp());
    return;
  }
  final settingsRepository = SettingsRepository(database);
  final initialSettings = await settingsRepository.load();
  final reminderRepository = ReminderRepository(database);
  final inspirationRepository = InspirationRepository(database);
  final imageStore = await InspirationImageStore.create();
  final notifications = NotificationService();
  await notifications.init(
    onTapBody: () => router.go('/'),
    onAction: _handleNotificationAction,
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

/// Routes a notification action button press to the right
/// [RemindersViewModel] call. Snooze pushes the reminder's fire time
/// forward by the user's current [SnoozeDuration] and re-schedules;
/// complete soft-deletes the reminder so the user can still recover
/// it from the trash page if the press was a misclick.
///
/// The handler runs in two cases:
///  1. The app is in the foreground when the user taps the action.
///  2. The app was cold-launched by the action (handled inside
///     [NotificationService.init] via `getNotificationAppLaunchDetails`).
///
/// In both cases the Provider tree may or may not be mounted yet at
/// the very first frame; the helper gracefully no-ops if it cannot
/// find the view model.
void _handleNotificationAction(NotificationResponse response) {
  final action = response.actionId;
  final reminderId = response.payload;
  if (action == null || reminderId == null || reminderId.isEmpty) return;
  final navigatorContext = rootNavigatorKey.currentContext;
  if (navigatorContext == null) return;
  try {
    final reminders = Provider.of<RemindersViewModel>(
      navigatorContext,
      listen: false,
    );
    final settings = Provider.of<SettingsViewModel>(
      navigatorContext,
      listen: false,
    );
    final messenger = ScaffoldMessenger.of(navigatorContext);
    switch (action) {
      case NotificationService.kSnoozeActionId:
        unawaited(
          reminders.snoozeReminder(
            reminderId,
            settings.settings.snoozeDuration.duration,
          ),
        );
        break;
      case NotificationService.kCompleteActionId:
        unawaited(reminders.softDelete(reminderId));
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('已移入回收站')));
        break;
    }
  } on Exception catch (error, stackTrace) {
    developer.log(
      'Failed to handle notification action',
      error: error,
      stackTrace: stackTrace,
    );
  }
}

class RemindersApp extends StatefulWidget {
  const RemindersApp({
    super.key,
    required this.settingsRepository,
    required this.initialSettings,
    required this.reminderRepository,
    required this.inspirationRepository,
    required this.imageStore,
    required this.notifications,
    required this.aiAnalyzer,
    required this.timezone,
  });

  final SettingsRepository settingsRepository;
  final AppSettings initialSettings;
  final ReminderRepository reminderRepository;
  final InspirationRepository inspirationRepository;
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
        ChangeNotifierProvider<RemindersViewModel>(
          create: (context) {
            final settings = context.read<SettingsViewModel>();
            final vm = RemindersViewModel(
              widget.reminderRepository,
              widget.notifications,
              settings,
              widget.imageStore,
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
          create: (_) => InspirationsViewModel(
            widget.inspirationRepository,
            widget.imageStore,
          ),
        ),
        ChangeNotifierProvider<ErrorLogService>(
          create: (_) => attachGlobalErrorLog(ErrorLogService()),
        ),
        ChangeNotifierProvider<AiAssistViewModel>(
          create: (context) {
            // Wire the analyzer to the live settings view model so
            // toggling 中文 OCR in settings takes effect on the next
            // assistant invocation without rebuilding the singleton.
            widget.aiAnalyzer.setChineseOcrProvider(
              () =>
                  context.read<SettingsViewModel>().settings.chineseOcrEnabled,
            );
            return AiAssistViewModel(
              widget.aiAnalyzer,
              settings: context.read<SettingsViewModel>(),
              errorLog: context.read<ErrorLogService>(),
            );
          },
        ),
        ChangeNotifierProvider<ChineseOcrInstaller>(
          create: (_) => ChineseOcrInstaller(),
        ),
        Provider<AiAnalyzer>.value(value: widget.aiAnalyzer),
        Provider<InspirationImageStore>.value(value: widget.imageStore),
        Provider<NotificationService>.value(value: widget.notifications),
        Provider<BackupService>.value(value: _backup),
      ],
      child: Selector<SettingsViewModel, _ThemeTuple>(
        selector: (_, vm) => _ThemeTuple(
          mode: vm.settings.themeMode,
          seed: vm.settings.seedColor,
        ),
        builder: (context, selected, _) {
          final seed = selected.seed.color;
          return MaterialApp.router(
            title: '提醒事项',
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

class _DatabaseErrorApp extends StatelessWidget {
  const _DatabaseErrorApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '提醒事项',
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.storage, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text(
                  '数据库初始化失败',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 8),
                Text(
                  '请重启应用。如问题持续，请卸载后重新安装。',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
