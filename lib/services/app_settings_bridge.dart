import 'dart:developer' as developer;

import 'package:flutter/services.dart';

/// Bridges a single native capability — jumping to the OS app-details
/// screen — through the `app_settings` MethodChannel registered in
/// `MainActivity.kt`.
///
/// Used today by the calendar "permission denied" SnackBar to give the
/// user a one-tap recovery path when the runtime calendar permission
/// was permanently denied (or never granted and the user dismissed the
/// system prompt).
class AppSettingsBridge {
  AppSettingsBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('app_settings');

  final MethodChannel _channel;

  /// Opens the OS app-details page for this application. Returns
  /// `true` when the system reported a successful launch, `false`
  /// otherwise (including no native handler registered — e.g. running
  /// on a non-Android platform).
  Future<bool> openAppSettings() async {
    try {
      final result = await _channel.invokeMethod<bool>('openAppSettings');
      return result ?? false;
    } on MissingPluginException catch (error, stackTrace) {
      developer.log(
        'app_settings channel not registered on this platform',
        error: error,
        stackTrace: stackTrace,
        name: 'AppSettingsBridge',
      );
      return false;
    } on PlatformException catch (error, stackTrace) {
      developer.log(
        'openAppSettings failed',
        error: error,
        stackTrace: stackTrace,
        name: 'AppSettingsBridge',
      );
      return false;
    }
  }
}
