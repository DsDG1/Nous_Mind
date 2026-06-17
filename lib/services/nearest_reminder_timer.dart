import 'dart:async';

import 'package:nousmind/models/reminder.dart';

/// Fires the user's [onDue] callback at the nearest future
/// [Reminder.reminderTime] across a list. The class is intentionally
/// ignorant of persistence and `ChangeNotifier` so it can be reused
/// (and unit-tested) without dragging the view-model along.
///
/// Behaviour:
///   * `schedule(reminders)` cancels any pending timer, picks the
///     nearest future reminder, and arms a one-shot [Timer].
///   * When the timer fires, [onDue] is invoked exactly once and the
///     timer is cleared. Callers that want to keep firing (e.g. the
///     reminders view model) must call `schedule(reminders)` again
///     after handling the due reminder.
///   * Timer firing is best-effort — Android Doze and similar
///     platform-level delays may push the callback later than the
///     exact instant.
class NearestReminderTimer {
  NearestReminderTimer({required this.onDue, DateTime Function()? now})
    : _now = now ?? DateTime.now;

  /// Invoked once when the nearest reminder reaches its
  /// [Reminder.reminderTime]. Replaced by callers that need to swap
  /// the destination (typically tests or the view-model pop-up hook).
  void Function(Reminder) onDue;

  final DateTime Function() _now;
  Timer? _nearestTimer;

  /// Cancels any pending timer, then arms a fresh one for the
  /// nearest future reminder in [reminders]. No-op when the list has
  /// no future entries.
  void schedule(List<Reminder> reminders) {
    _nearestTimer?.cancel();
    _nearestTimer = null;
    final now = _now();
    Reminder? nearest;
    for (final reminder in reminders) {
      if (reminder.reminderTime.isAfter(now)) {
        if (nearest == null ||
            reminder.reminderTime.isBefore(nearest.reminderTime)) {
          nearest = reminder;
        }
      }
    }
    if (nearest == null) {
      return;
    }
    final delay = nearest.reminderTime.difference(now);
    if (delay <= Duration.zero) {
      return;
    }
    _nearestTimer = Timer(delay, () {
      _nearestTimer = null;
      onDue(nearest!);
    });
  }

  /// Cancels any pending timer. Safe to call multiple times.
  void cancel() {
    _nearestTimer?.cancel();
    _nearestTimer = null;
  }

  /// Cancels any pending timer. Call from the owning view model's
  /// `dispose` so a hanging Timer never fires after teardown.
  void dispose() {
    cancel();
  }
}
