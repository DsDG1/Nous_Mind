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
import 'package:nousmind/pages/settings/tag_settings_page.dart';
import 'package:nousmind/pages/settings/trash_page.dart';
import 'package:nousmind/pages/settings/user_agreement_page.dart';
import 'package:nousmind/pages/settings/tutorial_page.dart';
import 'package:nousmind/pages/settings_page.dart';
import 'package:nousmind/pages/inspirations_ai_page.dart';
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

/// Wraps a settings sub-page in a [PopScope] so the Android 14+ predictive
/// back gesture only pops the topmost route, not the entire
/// [StatefulShellRoute.indexedStack] branch. This works around a known
/// interaction between go_router's `StatefulShellRoute` and Flutter's
/// `PredictiveBackNavigator` where a single back gesture from a deep
/// sub-route would otherwise pop every nested settings page at once.
Page<T> _settingsPage<T>({required LocalKey key, required Widget child}) {
  return MaterialPage<T>(
    key: key,
    child: Builder(
      builder: (context) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) {
            context.pop();
          }
        },
        child: child,
      ),
    ),
  );
}

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
                GoRoute(
                  path: 'ai',
                  parentNavigatorKey: rootNavigatorKey,
                  builder: (context, state) => const InspirationsAiPage(),
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
              pageBuilder: (context, state) => _settingsPage<void>(
                key: state.pageKey,
                child: const SettingsPage(),
              ),
              routes: <RouteBase>[
                GoRoute(
                  path: 'appearance',
                  pageBuilder: (context, state) => _settingsPage<void>(
                    key: state.pageKey,
                    child: const AppearanceSettingsPage(),
                  ),
                ),
                GoRoute(
                  path: 'notification',
                  pageBuilder: (context, state) => _settingsPage<void>(
                    key: state.pageKey,
                    child: const NotificationSettingsPage(),
                  ),
                ),
                GoRoute(
                  path: 'data',
                  pageBuilder: (context, state) => _settingsPage<void>(
                    key: state.pageKey,
                    child: const DataSettingsPage(),
                  ),
                  routes: <RouteBase>[
                    GoRoute(
                      path: 'trash',
                      pageBuilder: (context, state) => _settingsPage<void>(
                        key: state.pageKey,
                        child: const TrashPage(),
                      ),
                    ),
                  ],
                ),
                GoRoute(
                  path: 'tags',
                  pageBuilder: (context, state) => _settingsPage<void>(
                    key: state.pageKey,
                    child: const TagSettingsPage(),
                  ),
                ),
                GoRoute(
                  path: 'ai',
                  pageBuilder: (context, state) => _settingsPage<void>(
                    key: state.pageKey,
                    child: const AiSettingsPage(),
                  ),
                  routes: <RouteBase>[
                    GoRoute(
                      path: 'deepseek',
                      pageBuilder: (context, state) => _settingsPage<void>(
                        key: state.pageKey,
                        child: const DeepSeekSettingsPage(),
                      ),
                    ),
                    GoRoute(
                      path: 'local-ocr',
                      pageBuilder: (context, state) => _settingsPage<void>(
                        key: state.pageKey,
                        child: const LocalOcrSettingsPage(),
                      ),
                    ),
                    GoRoute(
                      path: 'prompts',
                      pageBuilder: (context, state) => _settingsPage<void>(
                        key: state.pageKey,
                        child: const AiPromptsSettingsPage(),
                      ),
                    ),
                  ],
                ),
                GoRoute(
                  path: 'changelog',
                  pageBuilder: (context, state) => _settingsPage<void>(
                    key: state.pageKey,
                    child: const ChangelogPage(),
                  ),
                  routes: <RouteBase>[
                    GoRoute(
                      path: 'history',
                      pageBuilder: (context, state) => _settingsPage<void>(
                        key: state.pageKey,
                        child: const ChangelogHistoryPage(),
                      ),
                    ),
                  ],
                ),
                GoRoute(
                  path: 'about',
                  pageBuilder: (context, state) => _settingsPage<void>(
                    key: state.pageKey,
                    child: const AboutSettingsPage(),
                  ),
                  routes: <RouteBase>[
                    GoRoute(
                      path: 'privacy',
                      pageBuilder: (context, state) => _settingsPage<void>(
                        key: state.pageKey,
                        child: const PrivacyPolicyPage(),
                      ),
                    ),
                    GoRoute(
                      path: 'user-agreement',
                      pageBuilder: (context, state) => _settingsPage<void>(
                        key: state.pageKey,
                        child: const UserAgreementPage(),
                      ),
                    ),
                    GoRoute(
                      path: 'tutorial',
                      pageBuilder: (context, state) => _settingsPage<void>(
                        key: state.pageKey,
                        child: const TutorialPage(),
                      ),
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
