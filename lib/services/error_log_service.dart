import 'package:flutter/foundation.dart';

/// A single captured error, suitable for display and clipboard export.
@immutable
class ErrorLogEntry {
  const ErrorLogEntry({
    required this.timestamp,
    required this.source,
    required this.message,
    this.stackTrace,
  });

  final DateTime timestamp;
  final String source;
  final String message;
  final String? stackTrace;

  /// Human-readable form used by the "copy log" action.
  String format() {
    final base = '[$timestamp] $source: $message';
    if (stackTrace == null) return base;
    return '$base\n$stackTrace';
  }
}

/// In-memory ring buffer of [ErrorLogEntry]s surfaced on the About page.
///
/// Bounded to [maxEntries] (newest first). Listeners are notified after each
/// mutation so widgets can rebuild without polling.
class ErrorLogService extends ChangeNotifier {
  ErrorLogService({this.maxEntries = 200});

  final int maxEntries;

  final List<ErrorLogEntry> _entries = <ErrorLogEntry>[];

  /// Read-only view, ordered newest → oldest.
  List<ErrorLogEntry> get entries => List.unmodifiable(_entries);

  int get count => _entries.length;
  bool get isEmpty => _entries.isEmpty;

  /// Records a new entry at the head of the buffer.
  void record({
    required String source,
    required Object error,
    StackTrace? stackTrace,
  }) {
    _entries.insert(
      0,
      ErrorLogEntry(
        timestamp: DateTime.now(),
        source: source,
        message: error.toString(),
        stackTrace: stackTrace?.toString(),
      ),
    );
    if (_entries.length > maxEntries) {
      _entries.removeRange(maxEntries, _entries.length);
    }
    notifyListeners();
  }

  /// Empties the buffer.
  void clear() {
    if (_entries.isEmpty) return;
    _entries.clear();
    notifyListeners();
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Global handle used by framework-level error handlers that run before
// (or outside of) the widget tree.
// ─────────────────────────────────────────────────────────────────────────

ErrorLogService? _globalErrorLogRef;

/// Returns the service attached by [attachGlobalErrorLog], or `null` if
/// the app has not initialised one yet (e.g. during very early startup).
ErrorLogService? get globalErrorLog => _globalErrorLogRef;

/// Stashes [service] as the global instance and returns it. Called once
/// from `main.dart` when the Provider is created.
ErrorLogService attachGlobalErrorLog(ErrorLogService service) {
  _globalErrorLogRef = service;
  return service;
}
