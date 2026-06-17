import 'package:flutter/material.dart';

/// Shows a [SnackBar] after first hiding any currently-visible one,
/// preventing the well-known stack-up bug when actions fire in quick
/// succession.
///
/// Two overloads:
/// - On [BuildContext]: the ergonomic shape used when there is no
///   `await` between capture and show.
/// - On [ScaffoldMessengerState]: the shape to use after an `await`,
///   where the messenger has been captured beforehand to keep a
///   stable reference independent of the (possibly unmounted) context.
///
/// Callers are still responsible for any required `mounted` /
/// `context.mounted` check before invoking — this helper only
/// hides-then-shows.
extension ShowAppSnackBarX on BuildContext {
  void showAppSnackBar(
    String message, {
    Duration? duration,
    SnackBarAction? action,
  }) {
    ScaffoldMessenger.of(
      this,
    ).showAppSnackBar(message, duration: duration, action: action);
  }
}

extension ShowAppSnackBarOnMessengerX on ScaffoldMessengerState {
  void showAppSnackBar(
    String message, {
    Duration? duration,
    SnackBarAction? action,
  }) {
    this
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: duration ?? const Duration(milliseconds: 4000),
          action: action,
        ),
      );
  }
}
