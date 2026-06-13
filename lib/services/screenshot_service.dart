import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../router.dart';
import 'inspiration_image_store.dart';

/// Bridges Flutter and the native Android screenshot tile / overlay services.
///
/// After the native [ScreenshotCaptureActivity] saves a screenshot the
/// floating [ScreenshotOverlayService] shows it. When the user taps
/// "保存到提醒" the native side writes the image path to SharedPreferences
/// and launches the Flutter activity. This service polls that pref on
/// app resume and forwards the image to the reminder editor.
class ScreenshotService {
  ScreenshotService(this._imageStore);

  static const String _channelName = 'screenshot_service';

  final InspirationImageStore _imageStore;
  final MethodChannel _channel = const MethodChannel(_channelName);

  /// Call this after the engine is ready, e.g. in [main] or via
  /// [WidgetsBindingObserver.didChangeAppLifecycleState] on resume.
  Future<void> checkPendingScreenshot() async {
    final rawPath = await _channel.invokeMethod<String>('checkPendingScreenshot');
    if (rawPath == null || rawPath.isEmpty) return;

    final sourceFile = File(rawPath);
    if (!await sourceFile.exists()) {
      await _channel.invokeMethod('clearPendingScreenshot');
      return;
    }

    // Copy the screenshot into the managed image store so it survives
    // cache cleanup.
    final savedPath = await _imageStore.save(
      inspirationId: 'screenshot_${DateTime.now().microsecondsSinceEpoch}',
      source: XFile(rawPath),
    );

    await _channel.invokeMethod('clearPendingScreenshot');

    // Try to delete the temporary file in the cache.
    try {
      await sourceFile.delete();
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Failed to delete temp screenshot',
        error: error,
        stackTrace: stackTrace,
      );
    }

    // Navigate to the reminder editor with the image pre-filled.
    final context = rootNavigatorKey.currentState?.context;
    if (context != null) {
      // ignore: use_build_context_synchronously
      context.push('/editor', extra: (null, Offset.zero, savedPath));
    }
  }

  /// Returns whether the app currently has the overlay draw permission.
  Future<bool> hasOverlayPermission() async {
    final result = await _channel.invokeMethod<bool>('hasOverlayPermission');
    return result ?? false;
  }

  /// Opens the system settings page for "display over other apps".
  Future<void> requestOverlayPermission() async {
    await _channel.invokeMethod('requestOverlayPermission');
  }
}
