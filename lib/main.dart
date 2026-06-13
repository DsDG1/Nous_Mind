import 'package:flutter/material.dart';
import 'package:nested/nested.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'router.dart';
import 'services/inspiration_image_store.dart';
import 'services/inspiration_storage.dart';
import 'services/notification_service.dart';
import 'services/reminder_storage.dart';
import 'services/screenshot_service.dart';
import 'services/settings_storage.dart';
import 'viewmodels/inspirations_view_model.dart';
import 'viewmodels/reminders_view_model.dart';
import 'viewmodels/settings_view_model.dart';
import 'widgets/reminder_popup.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final reminderStorage = ReminderStorage(prefs);
  final inspirationStorage = InspirationStorage(prefs);
  final imageStore = await InspirationImageStore.create();
  final settingsStorage = SettingsStorage(prefs);
  final notifications = NotificationService();
  await notifications.init(onTapNotification: () => router.go('/'));
  final screenshotService = ScreenshotService(imageStore);
  runApp(
    RemindersApp(
      reminderStorage: reminderStorage,
      inspirationStorage: inspirationStorage,
      imageStore: imageStore,
      notifications: notifications,
      settingsStorage: settingsStorage,
      screenshotService: screenshotService,
    ),
  );
}

class RemindersApp extends StatelessWidget {
  const RemindersApp({
    super.key,
    required this.reminderStorage,
    required this.inspirationStorage,
    required this.imageStore,
    required this.notifications,
    required this.settingsStorage,
    required this.screenshotService,
  });

  final ReminderStorage reminderStorage;
  final InspirationStorage inspirationStorage;
  final InspirationImageStore imageStore;
  final NotificationService notifications;
  final SettingsStorage settingsStorage;
  final ScreenshotService screenshotService;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: <SingleChildWidget>[
        ChangeNotifierProvider<SettingsViewModel>(
          create: (_) => SettingsViewModel(settingsStorage),
        ),
        ChangeNotifierProvider<RemindersViewModel>(
          create: (context) {
            final vm = RemindersViewModel(
              reminderStorage,
              notifications,
              context.read<SettingsViewModel>(),
              imageStore,
            );
            vm.onReminderDue = (reminder) {
              final navigatorState = rootNavigatorKey.currentState;
              if (navigatorState == null) {
                return;
              }
              showReminderPopup(
                context: navigatorState.context,
                title: reminder.title,
                onSnooze: () => vm.snoozeReminder(
                  reminder.id,
                  const Duration(minutes: 5),
                ),
              );
            };
            return vm;
          },
        ),
        ChangeNotifierProvider<InspirationsViewModel>(
          create: (_) => InspirationsViewModel(inspirationStorage, imageStore),
        ),
        Provider<InspirationImageStore>.value(value: imageStore),
        Provider<NotificationService>.value(value: notifications),
        Provider<ScreenshotService>.value(value: screenshotService),
      ],
      child: _AppWithLifecycle(screenshotService: screenshotService),
    );
  }
}

/// Listens for app resume events to check for pending screenshots captured
/// by the native TileService / OverlayService flow.
class _AppWithLifecycle extends StatefulWidget {
  const _AppWithLifecycle({required this.screenshotService});

  final ScreenshotService screenshotService;

  @override
  State<_AppWithLifecycle> createState() => _AppWithLifecycleState();
}

class _AppWithLifecycleState extends State<_AppWithLifecycle>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.screenshotService.checkPendingScreenshot();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsViewModel>(
      builder: (context, vm, _) {
        final seed = vm.settings.seedColor.color;
        return MaterialApp.router(
          title: '提醒事项',
          themeMode: vm.settings.themeMode,
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
    );
  }
}
