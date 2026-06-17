// Smoke tests for [SettingsPage].
//
// The page renders a `Selector<SettingsViewModel, _SettingsForSubtitle>`
// list with five tiles plus a `SettingsStatsCard`, and dispatches each
// tile's tap through `context.push('/settings/...')`. The tests cover
// the render path and confirm each tile pushes to its sub-route via a
// [NavigatorObserver] that records route pushes.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:nousmind/pages/settings_page.dart';
import 'package:nousmind/services/backup_service.dart';
import 'package:nousmind/viewmodels/settings_view_model.dart';
import 'package:nousmind/viewmodels/tags_view_model.dart';
import 'package:nousmind/widgets/settings_section.dart';
import 'package:nousmind/widgets/settings_stats_card.dart';

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

void main() {
  late TestDatabase testDb;
  late SettingsViewModel settingsVm;
  late TagsViewModel tagsVm;
  late BackupService backupService;

  setUp(() async {
    testDb = await TestDatabase.create();
    settingsVm = makeSettingsVm();
    tagsVm = TagsViewModel(testDb.tagRepository);
    await tagsVm.refresh();
    backupService = testDb.backupService;
  });

  tearDown(() async {
    settingsVm.dispose();
    tagsVm.dispose();
    await testDb.dispose();
  });

  /// Wraps [SettingsPage] in the providers it requires.
  Widget wrap({required Widget child}) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsViewModel>.value(value: settingsVm),
        ChangeNotifierProvider<TagsViewModel>.value(value: tagsVm),
        Provider<BackupService>.value(value: backupService),
      ],
      child: child,
    );
  }

  testWidgets('renders the six settings tiles and the stats card', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(child: const MaterialApp(home: SettingsPage())),
    );

    expect(find.byType(SettingsStatsCard), findsOneWidget);
    expect(find.byType(SettingsSection), findsOneWidget);
    expect(find.text('外观'), findsOneWidget);
    expect(find.text('通知'), findsOneWidget);
    expect(find.text('数据'), findsOneWidget);
    expect(find.text('标签'), findsOneWidget);
    expect(find.text('AI 助手'), findsOneWidget);
    expect(find.text('关于'), findsOneWidget);
  });

  testWidgets('tapping each tile pushes its settings sub-route', (
    tester,
  ) async {
    final observer = _RecordingNavigatorObserver();
    // Use a GoRouter so `context.push` resolves. The observer is
    // installed on the router's parent navigator so it catches every
    // sub-route push.
    final router = GoRouter(
      initialLocation: '/',
      observers: <NavigatorObserver>[observer],
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (_, _) => wrap(child: const SettingsPage()),
        ),
        GoRoute(
          path: '/settings/appearance',
          builder: (_, _) =>
              const Scaffold(body: Center(child: Text('appearance'))),
        ),
        GoRoute(
          path: '/settings/notification',
          builder: (_, _) =>
              const Scaffold(body: Center(child: Text('notification'))),
        ),
        GoRoute(
          path: '/settings/data',
          builder: (_, _) => const Scaffold(body: Center(child: Text('data'))),
        ),
        GoRoute(
          path: '/settings/tags',
          builder: (_, _) => const Scaffold(body: Center(child: Text('tags'))),
        ),
        GoRoute(
          path: '/settings/ai',
          builder: (_, _) => const Scaffold(body: Center(child: Text('ai'))),
        ),
        GoRoute(
          path: '/settings/about',
          builder: (_, _) => const Scaffold(body: Center(child: Text('about'))),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    // Tap each tile; after every tap the pushed route's name should
    // appear in the observer's record.
    Future<void> tapAndExpect(String label, String subrouteText) async {
      final beforeCount = observer.pushed.length;
      // Scroll the target tile into view first — the page is
      // taller than the default 800×600 test viewport with six
      // tiles, and an off-screen tap silently misses.
      final tileFinder = find
          .ancestor(of: find.text(label), matching: find.byType(ListTile))
          .first;
      await tester.scrollUntilVisible(
        tileFinder,
        100,
        scrollable: find.byType(Scrollable).first,
      );
      // Tap the ListTile so we don't depend on which descendant catches
      // the gesture.
      await tester.tap(tileFinder);
      await tester.pumpAndSettle();
      expect(
        observer.pushed.length,
        greaterThan(beforeCount),
        reason: 'Tapping $label should push a route',
      );
      expect(find.text(subrouteText), findsOneWidget);
      // Go back so the next tile is reachable.
      router.pop();
      await tester.pumpAndSettle();
    }

    await tapAndExpect('外观', 'appearance');
    await tapAndExpect('通知', 'notification');
    await tapAndExpect('数据', 'data');
    await tapAndExpect('标签', 'tags');
    await tapAndExpect('AI 助手', 'ai');
    await tapAndExpect('关于', 'about');
  });
}
