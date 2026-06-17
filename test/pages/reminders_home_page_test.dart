// Smoke tests for [RemindersHomePage].
//
// The page renders either a spinner (when [RemindersViewModel.isLoaded]
// is false), an empty state, or a list of [ReminderListItem]s. The FAB
// pushes `/editor`. Swiping a list row soft-deletes the reminder and
// shows an undo SnackBar.
//
// Setup notes:
//   * Uses [TestRemindersContext] so the FFI database, fake
//     notification service, settings VM, and image store are all wired
//     correctly without touching real plugins.
//   * Reminders are seeded with `reminderTime` in the past so the
//     bootstrap path skips OS notification scheduling (which would
//     otherwise need a MethodChannel mock).
//   * `pumpAndSettle` is intentionally avoided during the bootstrap
//     window because the loading spinner schedules frames forever;
//     the tests pump a fixed number of frames after the VM's bootstrap
//     completes instead.
//   * A [NavigatorObserver] records every push so the FAB / tile tests
//     can assert on the destination without depending on
//     [GoRouter.routerDelegate] internals, which can be racy under
//     the test async clock.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:nousmind/models/reminder.dart';
import 'package:nousmind/pages/reminders_home_page.dart';
import 'package:nousmind/viewmodels/reminders_view_model.dart';
import 'package:nousmind/viewmodels/settings_view_model.dart';
import 'package:nousmind/viewmodels/tags_view_model.dart';
import 'package:nousmind/widgets/empty_state.dart';
import 'package:nousmind/widgets/reminder_list_item.dart';

import '../helpers/fakes.dart';

/// Records every route push so the test can assert on the destination
/// without depending on [GoRouter] internals.
class _RecordingNavigatorObserver extends NavigatorObserver {
  final List<Route<dynamic>> pushed = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
    super.didPush(route, previousRoute);
  }
}

GoRouter _makeRouter({required Widget home, NavigatorObserver? observer}) {
  return GoRouter(
    initialLocation: '/',
    observers: observer == null ? const <NavigatorObserver>[] : [observer],
    routes: <RouteBase>[
      GoRoute(path: '/', builder: (_, _) => home),
      GoRoute(
        path: '/editor',
        builder: (_, _) => const Scaffold(body: Center(child: Text('editor'))),
      ),
    ],
  );
}

Widget _wrapForRemindersPage({
  required RemindersViewModel remindersVm,
  required SettingsViewModel settingsVm,
  required TagsViewModel tagsVm,
  required Widget child,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<RemindersViewModel>.value(value: remindersVm),
      ChangeNotifierProvider<SettingsViewModel>.value(value: settingsVm),
      ChangeNotifierProvider<TagsViewModel>.value(value: tagsVm),
    ],
    child: child,
  );
}

/// Pumps the home page and lets the VM bootstrap complete. Uses
/// [WidgetTester.runAsync] to drive real I/O (sqflite_common_ffi runs
/// on the host event loop, not the fake test clock), then a regular
/// pump to flush the rebuild.
Future<void> pumpHomeAfterBootstrap(
  WidgetTester tester,
  TestRemindersContext ctx,
) async {
  // Real async work — FFI sqflite and ChangeNotifier plumbing.
  await tester.runAsync(() async {
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (!ctx.remindersVm.isLoaded && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  });
  // Flush the rebuild triggered by notifyListeners.
  await tester.pump();
}

void main() {
  late TestRemindersContext ctx;

  setUp(() async {
    ctx = await TestRemindersContext.create();
  });

  tearDown(() async {
    await ctx.dispose();
  });

  Future<void> pumpHome(WidgetTester tester, {GoRouter? router}) async {
    final widget = router == null
        ? MaterialApp(
            home: _wrapForRemindersPage(
              remindersVm: ctx.remindersVm,
              settingsVm: ctx.settingsVm,
              tagsVm: ctx.tagsVm,
              child: const RemindersHomePage(),
            ),
          )
        : MaterialApp.router(routerConfig: router);
    await tester.pumpWidget(widget);
    await pumpHomeAfterBootstrap(tester, ctx);
  }

  testWidgets('renders the empty state when no reminders exist', (
    tester,
  ) async {
    await pumpHome(tester);

    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text('还没有提醒'), findsOneWidget);
    expect(find.byType(ReminderListItem), findsNothing);
  });

  testWidgets('renders one ReminderListItem per reminder', (tester) async {
    // The VM constructor already started a bootstrap in setUp; the
    // first runAsync in pumpHomeAfterBootstrap will finish it (it
    // sees an empty DB at that point). To verify that seeded rows
    // appear, we seed *and* re-bootstrap in one runAsync block, then
    // pump the widget so the second bootstrap's notifyListeners
    // rebuilds the list.
    await tester.runAsync(() async {
      await ctx.testDb.seedReminders(<Reminder>[
        Reminder(
          id: 'r-1',
          title: 'Buy milk',
          reminderTime: DateTime.now().subtract(const Duration(hours: 1)),
        ),
        Reminder(
          id: 'r-2',
          title: 'Walk the dog',
          reminderTime: DateTime.now().subtract(const Duration(hours: 2)),
        ),
      ]);
      await ctx.remindersVm.refresh();
    });
    await pumpHome(tester);

    expect(find.byType(ReminderListItem), findsNWidgets(2));
    expect(find.text('Buy milk'), findsOneWidget);
    expect(find.text('Walk the dog'), findsOneWidget);
  });

  testWidgets('tapping the FAB pushes /editor', (tester) async {
    final observer = _RecordingNavigatorObserver();
    final router = _makeRouter(
      home: _wrapForRemindersPage(
        remindersVm: ctx.remindersVm,
        settingsVm: ctx.settingsVm,
        tagsVm: ctx.tagsVm,
        child: const RemindersHomePage(),
      ),
      observer: observer,
    );
    await pumpHome(tester, router: router);

    expect(find.byType(FloatingActionButton), findsOneWidget);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(observer.pushed, isNotEmpty, reason: 'FAB tap should push a route');
    expect(find.text('editor'), findsOneWidget);
  });

  testWidgets('softDelete removes the row from the active list', (
    tester,
  ) async {
    // Note: triggering the Dismissible's swipe-to-delete from a
    // widget test is unreliable — the Dismissible widget's
    // horizontal-drag gesture handler competes with the inner
    // ListTile's tap recognizer, and the synthetic gesture timing
    // does not always cross the dismiss threshold. The swipe itself
    // is exercised manually on device; here we verify the VM-side
    // contract the swipe handler relies on.
    await tester.runAsync(() async {
      await ctx.testDb.seedReminders(<Reminder>[
        Reminder(
          id: 'r-1',
          title: 'Buy milk',
          reminderTime: DateTime.now().subtract(const Duration(hours: 1)),
        ),
      ]);
      await ctx.remindersVm.refresh();
    });
    await pumpHome(tester);

    expect(find.byType(ReminderListItem), findsOneWidget);
    expect(ctx.remindersVm.reminders, hasLength(1));

    await tester.runAsync(() async {
      await ctx.remindersVm.softDelete('r-1');
    });

    expect(
      ctx.remindersVm.reminders,
      isEmpty,
      reason: 'softDelete should have removed the row from the VM',
    );
    expect(
      ctx.remindersVm.trashCount,
      1,
      reason: 'softDelete should have incremented the trash count',
    );
  });
}
