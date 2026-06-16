// Shared widget-test helpers. Centralises the [MaterialApp]/router
// wrapping pattern so individual tests focus on the widget under test.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Pumps [child] inside a [MaterialApp] (or [MaterialApp.router] when
/// [router] is supplied). Returns when the first frame is built; callers
/// should `pumpAndSettle()` themselves if they need to wait for async
/// work (e.g. the RemindersViewModel bootstrap).
Future<void> pumpPage(
  WidgetTester tester,
  Widget child, {
  GoRouter? router,
}) async {
  final widget = router != null
      ? MaterialApp.router(routerConfig: router)
      : MaterialApp(home: child);

  await tester.pumpWidget(widget);
}

/// A minimal [GoRouter] that exposes a single catch-all route. Useful
/// for tests that exercise [GoRouter.push] without needing the full
/// app router.
GoRouter makeTestRouter({required String initialLocation}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: Text('root')),
      ),
      GoRoute(
        path: '/editor',
        builder: (_, state) =>
            Scaffold(body: Text('editor: ${state.extra}')),
      ),
      GoRoute(
        path: '/settings/appearance',
        builder: (_, _) =>
            const Scaffold(body: Text('appearance')),
      ),
      GoRoute(
        path: '/settings/notification',
        builder: (_, _) =>
            const Scaffold(body: Text('notification')),
      ),
      GoRoute(
        path: '/settings/data',
        builder: (_, _) => const Scaffold(body: Text('data')),
      ),
      GoRoute(
        path: '/settings/ai',
        builder: (_, _) => const Scaffold(body: Text('ai')),
      ),
      GoRoute(
        path: '/settings/about',
        builder: (_, _) => const Scaffold(body: Text('about')),
      ),
    ],
  );
}
