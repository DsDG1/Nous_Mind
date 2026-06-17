import 'package:flutter/foundation.dart';

import 'package:nousmind/services/error_log_service.dart';

/// Captures uncaught framework and platform errors so the About page can
/// surface them via [globalErrorLog]. Idempotent — calling more than
/// once simply overwrites the previous hooks with equivalent handlers.
///
/// These hooks run outside the widget tree, hence the global handle
/// installed later in the Provider.
void installAppErrorHooks() {
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    globalErrorLog?.record(
      source: 'FlutterError',
      error: details.exceptionAsString(),
      stackTrace: details.stack,
    );
  };
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    globalErrorLog?.record(
      source: 'PlatformDispatcher',
      error: error,
      stackTrace: stack,
    );
    return true;
  };
}
