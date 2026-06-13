import 'package:flutter/material.dart';
import 'package:nested/nested.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'router.dart';
import 'services/inspiration_image_store.dart';
import 'services/inspiration_storage.dart';
import 'services/notification_service.dart';
import 'services/reminder_storage.dart';
import 'services/settings_storage.dart';
import 'viewmodels/inspirations_view_model.dart';
import 'viewmodels/reminders_view_model.dart';
import 'viewmodels/settings_view_model.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final reminderStorage = ReminderStorage(prefs);
  final inspirationStorage = InspirationStorage(prefs);
  final imageStore = await InspirationImageStore.create();
  final settingsStorage = SettingsStorage(prefs);
  final notifications = NotificationService();
  await notifications.init(onTapNotification: () => router.go('/'));
  runApp(
    RemindersApp(
      reminderStorage: reminderStorage,
      inspirationStorage: inspirationStorage,
      imageStore: imageStore,
      notifications: notifications,
      settingsStorage: settingsStorage,
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
  });

  final ReminderStorage reminderStorage;
  final InspirationStorage inspirationStorage;
  final InspirationImageStore imageStore;
  final NotificationService notifications;
  final SettingsStorage settingsStorage;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: <SingleChildWidget>[
        ChangeNotifierProvider<SettingsViewModel>(
          create: (_) => SettingsViewModel(settingsStorage),
        ),
        ChangeNotifierProvider<RemindersViewModel>(
          create: (context) => RemindersViewModel(
            reminderStorage,
            notifications,
            context.read<SettingsViewModel>(),
          ),
        ),
        ChangeNotifierProvider<InspirationsViewModel>(
          create: (_) => InspirationsViewModel(inspirationStorage, imageStore),
        ),
        Provider<InspirationImageStore>.value(value: imageStore),
        Provider<NotificationService>.value(value: notifications),
      ],
      child: Consumer<SettingsViewModel>(
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
      ),
    );
  }
}
