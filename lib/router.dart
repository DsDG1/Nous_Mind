import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'models/inspiration.dart';
import 'models/reminder.dart';
import 'pages/app_shell.dart';
import 'pages/inspiration_editor_page.dart';
import 'pages/inspirations_home_page.dart';
import 'pages/reminder_editor_page.dart';
import 'pages/reminders_home_page.dart';
import 'pages/settings/appearance_settings_page.dart';
import 'pages/settings/notification_settings_page.dart';
import 'pages/settings_page.dart';

/// Navigator keys — separate per branch so each tab maintains its own
/// navigation history, plus a root key for full-screen overlays (editors).
final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'root',
);
final GlobalKey<NavigatorState> _remindersBranchKey = GlobalKey<NavigatorState>(
  debugLabel: 'reminders',
);
final GlobalKey<NavigatorState> _inspirationsBranchKey =
    GlobalKey<NavigatorState>(debugLabel: 'inspirations');
final GlobalKey<NavigatorState> _settingsBranchKey = GlobalKey<NavigatorState>(
  debugLabel: 'settings',
);

/// The application's [GoRouter]. Each tab gets its own [StatefulShellBranch]
/// so switching tabs preserves the per-tab Navigator stack (an open editor
/// stays open across tab switches).
final GoRouter router = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/',
  routes: <RouteBase>[
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          AppShell(navigationShell: navigationShell),
      branches: <StatefulShellBranch>[
        StatefulShellBranch(
          navigatorKey: _remindersBranchKey,
          routes: <RouteBase>[
            GoRoute(
              path: '/',
              builder: (context, state) => const RemindersHomePage(),
              routes: <RouteBase>[
                GoRoute(
                  path: 'editor',
                  parentNavigatorKey: _rootNavigatorKey,
                  builder: (context, state) =>
                      ReminderEditorPage(initial: state.extra as Reminder?),
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: _inspirationsBranchKey,
          routes: <RouteBase>[
            GoRoute(
              path: '/inspirations',
              builder: (context, state) => const InspirationsHomePage(),
              routes: <RouteBase>[
                GoRoute(
                  path: 'editor',
                  parentNavigatorKey: _rootNavigatorKey,
                  builder: (context, state) => InspirationEditorPage(
                    initial: state.extra as Inspiration?,
                  ),
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: _settingsBranchKey,
          routes: <RouteBase>[
            GoRoute(
              path: '/settings',
              builder: (context, state) => const SettingsPage(),
              routes: <RouteBase>[
                GoRoute(
                  path: 'appearance',
                  builder: (context, state) => const AppearanceSettingsPage(),
                ),
                GoRoute(
                  path: 'notification',
                  builder: (context, state) => const NotificationSettingsPage(),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  ],
);
