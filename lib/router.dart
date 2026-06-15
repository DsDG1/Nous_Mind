import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:nousmind/models/inspiration.dart';
import 'package:nousmind/models/reminder.dart';
import 'package:nousmind/pages/app_shell.dart';
import 'package:nousmind/pages/inspiration_editor_page.dart';
import 'package:nousmind/pages/inspirations_home_page.dart';
import 'package:nousmind/pages/reminder_editor_page.dart';
import 'package:nousmind/pages/reminders_home_page.dart';
import 'package:nousmind/pages/settings/ai_prompts_settings_page.dart';
import 'package:nousmind/pages/settings/ai_settings_page.dart';
import 'package:nousmind/pages/settings/appearance_settings_page.dart';
import 'package:nousmind/pages/settings/changelog_page.dart';
import 'package:nousmind/pages/settings/deepseek_settings_page.dart';
import 'package:nousmind/pages/settings/data_settings_page.dart';
import 'package:nousmind/pages/settings/local_ocr_settings_page.dart';
import 'package:nousmind/pages/settings/notification_settings_page.dart';
import 'package:nousmind/pages/settings/about_settings_page.dart';
import 'package:nousmind/pages/settings/privacy_policy_page.dart';
import 'package:nousmind/pages/settings/trash_page.dart';
import 'package:nousmind/pages/settings/user_agreement_page.dart';
import 'package:nousmind/pages/settings_page.dart';
import 'package:nousmind/widgets/circular_reveal_clip.dart';

/// Navigator keys — separate per branch so each tab maintains its own
/// navigation history, plus a root key for full-screen overlays (editors).
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>(
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
  navigatorKey: rootNavigatorKey,
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
                  parentNavigatorKey: rootNavigatorKey,
                  pageBuilder: (context, state) {
                    final extra = state.extra as (Reminder?, Offset?);
                    final reminder = extra.$1;
                    final center = extra.$2;

                    if (center != null) {
                      return CustomTransitionPage(
                        key: state.pageKey,
                        child: ReminderEditorPage(initial: reminder),
                        transitionsBuilder:
                            (context, animation, secondaryAnimation, child) {
                              return CircularRevealTransition(
                                animation: animation,
                                center: center,
                                child: child,
                              );
                            },
                      );
                    }

                    return CustomTransitionPage(
                      key: state.pageKey,
                      child: ReminderEditorPage(initial: reminder),
                      transitionDuration: const Duration(milliseconds: 300),
                      reverseTransitionDuration: const Duration(
                        milliseconds: 300,
                      ),
                      transitionsBuilder:
                          (context, animation, secondaryAnimation, child) {
                            final curved = CurvedAnimation(
                              parent: animation,
                              curve: Curves.easeOutCubic,
                            );
                            return FadeTransition(
                              opacity: curved,
                              child: SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(0, 0.08),
                                  end: Offset.zero,
                                ).animate(curved),
                                child: child,
                              ),
                            );
                          },
                    );
                  },
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
                  parentNavigatorKey: rootNavigatorKey,
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
                GoRoute(
                  path: 'data',
                  builder: (context, state) => const DataSettingsPage(),
                  routes: <RouteBase>[
                    GoRoute(
                      path: 'trash',
                      builder: (context, state) => const TrashPage(),
                    ),
                  ],
                ),
                GoRoute(
                  path: 'ai',
                  builder: (context, state) => const AiSettingsPage(),
                  routes: <RouteBase>[
                    GoRoute(
                      path: 'deepseek',
                      builder: (context, state) => const DeepSeekSettingsPage(),
                    ),
                    GoRoute(
                      path: 'local-ocr',
                      builder: (context, state) => const LocalOcrSettingsPage(),
                    ),
                    GoRoute(
                      path: 'prompts',
                      builder: (context, state) =>
                          const AiPromptsSettingsPage(),
                    ),
                  ],
                ),
                GoRoute(
                  path: 'changelog',
                  builder: (context, state) => const ChangelogPage(),
                  routes: <RouteBase>[
                    GoRoute(
                      path: 'history',
                      builder: (context, state) => const ChangelogHistoryPage(),
                    ),
                  ],
                ),
                GoRoute(
                  path: 'about',
                  builder: (context, state) => const AboutSettingsPage(),
                  routes: <RouteBase>[
                    GoRoute(
                      path: 'privacy',
                      builder: (context, state) => const PrivacyPolicyPage(),
                    ),
                    GoRoute(
                      path: 'user-agreement',
                      builder: (context, state) => const UserAgreementPage(),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  ],
);
