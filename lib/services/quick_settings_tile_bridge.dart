import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'package:nousmind/router.dart';

/// Bidirectional bridge between Dart and the Android Quick Settings Tile.
///
/// Native side: `MainActivity` and `QuickAddTileService` in
/// `android/app/src/main/kotlin/com/dsdogs/nousmind/`.
/// Channel name: `quick_settings_tile`.
///
/// Two events can flow into Dart:
///
/// 1. **Cold start** — `MainActivity.onCreate` / `onNewIntent` sets a
///    static `pendingQuickAdd` flag. Once the Flutter engine is up and
///    the first frame has painted, [consumePending] asks the native
///    side whether a tile click is queued and triggers [onOpenCreate]
///    if so.
///
/// 2. **Hot start** — `MainActivity.onNewIntent` actively invokes
///    `openCreateReminder` on the channel while the engine is alive;
///    the registered handler calls [onOpenCreate] immediately.
///
/// Both paths invoke the same callback, which by default navigates to
/// the existing `/editor` route in create mode.
class QuickSettingsTileBridge {
  QuickSettingsTileBridge._();

  static final QuickSettingsTileBridge instance = QuickSettingsTileBridge._();

  static const MethodChannel _channel = MethodChannel('quick_settings_tile');

  void Function()? _onOpenCreate;

  /// Idempotent. Install the native → Dart handler and remember the
  /// callback used by both the hot-path and the cold-start drain.
  void init({void Function()? onOpenCreate}) {
    _onOpenCreate = onOpenCreate;
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  /// Asks the native side whether a tile click is queued. Should be
  /// called exactly once after [init], after the first frame, so the
  /// router is mounted. No-op on non-Android platforms.
  Future<void> consumePending() async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'consumePendingQuickAdd',
      );
      if (result == true) {
        _onOpenCreate?.call();
      }
    } on MissingPluginException {
      // Non-Android or channel unavailable — nothing to do.
    } on PlatformException catch (error, stack) {
      developer.log(
        'quick_settings_tile: consumePendingQuickAdd failed',
        error: error,
        stackTrace: stack,
      );
    }
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'openCreateReminder':
        _onOpenCreate?.call();
        return null;
      default:
        throw MissingPluginException(
          'quick_settings_tile: unknown method ${call.method}',
        );
    }
  }
}

/// Shared handler registered with [QuickSettingsTileBridge]. Navigates to
/// the in-app reminder editor in "create" mode (initial = null), reusing
/// the existing `go_router` route at `/editor`.
///
/// The bridge's [QuickSettingsTileBridge.consumePending] is already
/// invoked from a post-frame callback in `main.dart`, so by the time
/// this handler runs the router is mounted. We still defer one more
/// frame defensively in case a future caller invokes it earlier.
void navigateToQuickAddEditor() {
  developer.log('quick_settings_tile: navigating to /editor');
  WidgetsBinding.instance.addPostFrameCallback((_) {
    router.go('/editor', extra: (null, _defaultEditorCenter()));
  });
}

/// Best-effort "center" point for the editor's circular-reveal
/// transition. Falls back to a 30%-from-top center when the platform
/// view isn't available.
Offset _defaultEditorCenter() {
  final view = WidgetsBinding.instance.platformDispatcher.views.firstOrNull;
  if (view == null) {
    return const Offset(180, 240);
  }
  final size = view.physicalSize / view.devicePixelRatio;
  return Offset(size.width / 2, size.height * 0.3);
}
