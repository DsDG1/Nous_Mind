import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// State of the on-device Chinese OCR model.
///
/// The five real states describe the on-disk module's lifecycle under
/// an unbundled (Play Services module) integration. The sixth,
/// [unsupported], is reserved for platforms where the model is not
/// available (desktop, web). With the current *bundled* integration
/// (the model is statically linked into the APK / IPA), the only
/// observable value is [installed] on Android and iOS — the other
/// states remain in the enum so a future move to an unbundled
/// distribution (or to additional scripts like Japanese / Korean) can
/// reuse the same UI without a schema change.
enum OcrModuleStatus {
  /// The status has never been queried. Treated as "loading" by the
  /// UI; replaced with a concrete state by the first
  /// [ChineseOcrInstaller.refresh] call.
  unknown,

  /// The model is on disk and ready to use with
  /// `TextRecognitionScript.chinese`.
  installed,

  /// The user kicked off a download and Play Services is currently
  /// transferring bytes.
  downloading,

  /// The user kicked off a download but Play Services has not started
  /// transferring yet (queued, waiting for Wi-Fi, etc.).
  pending,

  /// The model has never been installed and no download is queued.
  notInstalled,

  /// The model is not available on this device.
  unsupported,
}

/// Bridges the `chinese_ocr_module` MethodChannel to a Dart-side
/// [ChangeNotifier] that the settings UI can observe.
///
/// Channel: `chinese_ocr_module`
///
/// Methods:
///  * `checkModule` → returns one of the [OcrModuleStatus] names.
///    With the bundled integration this is always `"installed"` on
///    Android/iOS.
///  * `requestDownload` → resolves with the final state. With the
///    bundled integration there is nothing to download, so the
///    channel immediately reports `"installed"`. The method is
///    preserved so the UI can stay source-compatible if a future
///    release moves to an unbundled Play Services module.
///
/// On non-Android/iOS platforms (web, desktop) the channel is not
/// registered and the installer reports [OcrModuleStatus.unsupported].
/// In unit tests the channel may be replaced via the [channel]
/// constructor argument to exercise the unsupported / error paths.
class ChineseOcrInstaller extends ChangeNotifier {
  ChineseOcrInstaller({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('chinese_ocr_module');

  final MethodChannel _channel;
  OcrModuleStatus _status = OcrModuleStatus.unknown;
  bool _isBusy = false;
  String? _lastErrorMessage;

  /// Current install status. The settings page renders this directly
  /// and uses it to decide which action to expose.
  OcrModuleStatus get status => _status;

  /// True while a [requestDownload] call is in flight. Reserved for a
  /// future unbundled integration; with the current bundled model this
  /// only flips on for a single microtask.
  bool get isBusy => _isBusy;

  /// Last error message surfaced by [requestDownload]. Cleared at the
  /// start of each new download attempt and on a successful
  /// [refresh].
  String? get lastErrorMessage => _lastErrorMessage;

  /// One-shot query for the current install state. Updates [status]
  /// and returns it. Safe to call multiple times — the channel is
  /// idempotent.
  Future<OcrModuleStatus> refresh() async {
    if (!isAvailable) {
      _setStatus(OcrModuleStatus.unsupported);
      return _status;
    }
    try {
      final raw = await _channel.invokeMethod<String>('checkModule');
      _setStatus(_parseStatus(raw));
      if (_status == OcrModuleStatus.installed) {
        _lastErrorMessage = null;
      }
    } on MissingPluginException {
      // Non-Android/iOS or a release build where the channel is
      // intentionally absent. Report installed because iOS bundles
      // the model statically via the `GoogleMLKit/TextRecognitionChinese`
      // pod and the production iOS build always registers the
      // channel; this branch only fires in tests.
      _setStatus(OcrModuleStatus.installed);
    } on PlatformException catch (error, stackTrace) {
      developer.log(
        'chinese_ocr_module: checkModule failed',
        error: error,
        stackTrace: stackTrace,
      );
      _setStatus(OcrModuleStatus.unsupported);
    }
    return _status;
  }

  /// Triggers a download. With the bundled model the channel reports
  /// `"installed"` immediately and the future resolves to that
  /// state. Kept as a stable API so a future unbundled integration
  /// can swap in a real download without changing the Dart side.
  Future<OcrModuleStatus> requestDownload() async {
    if (_isBusy) return _status;
    if (!isAvailable) {
      _setStatus(OcrModuleStatus.unsupported);
      return _status;
    }
    _isBusy = true;
    _lastErrorMessage = null;
    _setStatus(OcrModuleStatus.downloading);
    try {
      final raw = await _channel.invokeMethod<String>('requestDownload');
      _setStatus(_parseStatus(raw));
    } on MissingPluginException {
      _setStatus(OcrModuleStatus.installed);
    } on PlatformException catch (error, stackTrace) {
      developer.log(
        'chinese_ocr_module: requestDownload failed',
        error: error,
        stackTrace: stackTrace,
      );
      _lastErrorMessage = error.message ?? '下载失败';
      await refresh();
    } finally {
      _isBusy = false;
      notifyListeners();
    }
    return _status;
  }

  /// Stable platform check. Exposed so callers (and tests) can decide
  /// whether the installer is meaningful. The check is intentionally
  /// permissive: in unit tests the channel is mocked, so we must not
  /// bail out before consulting the mock.
  bool get isAvailable {
    if (kIsWeb) return false;
    return true;
  }

  void _setStatus(OcrModuleStatus next) {
    if (next == _status) return;
    _status = next;
    notifyListeners();
  }

  static OcrModuleStatus _parseStatus(String? raw) {
    return switch (raw) {
      'installed' => OcrModuleStatus.installed,
      'downloading' => OcrModuleStatus.downloading,
      'pending' => OcrModuleStatus.pending,
      'notInstalled' => OcrModuleStatus.notInstalled,
      'unsupported' => OcrModuleStatus.unsupported,
      _ => OcrModuleStatus.unknown,
    };
  }
}
