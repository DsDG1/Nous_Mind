import 'package:clock/clock.dart';

import '../viewmodels/settings_view_model.dart';

/// Outcome of an [AiUsageGuard.tryAcquire] check.
///
/// Modeled as a sealed class so callers can `switch` on the result and
/// surface a specific user-facing message ("冷却中" vs "已达上限")
/// without inspecting ad-hoc error codes.
sealed class AcquireResult {
  const AcquireResult();
}

/// Caller may proceed with the AI call. [remaining] is the count of
/// calls still allowed for today after this one — i.e. `limit - 1`.
/// `null` means the daily ceiling is disabled (the quota switch is
/// off), so callers should display "今日不限制" rather than a number.
final class AcquireAllowed extends AcquireResult {
  const AcquireAllowed({required this.remaining});
  final int? remaining;
}

/// Caller must wait [retryAfter] before retrying. Returned when a
/// previous successful call happened too recently.
final class AcquireCooldown extends AcquireResult {
  const AcquireCooldown({required this.retryAfter});
  final Duration retryAfter;
}

/// Caller has hit the daily ceiling. The next reset happens at
/// midnight in the device's local timezone.
final class AcquireDailyLimitReached extends AcquireResult {
  const AcquireDailyLimitReached({required this.limit});
  final int limit;
}

/// Centralizes the "may this user make an AI call right now?" check.
///
/// Two independent gates are enforced:
///   * **Cooldown** — a short in-process timer ([_defaultCooldown])
///     that prevents the same widget tree from firing two requests in
///     quick succession (covers the in-flight gap where
///     `_isAiAnalyzing` has not yet flipped to true). Always on.
///   * **Daily limit** — the persisted counter on [AppSettings] (see
///     [AppSettings.aiCallsToday] / [AppSettings.aiDailyLimit]), with
///     the day-rollover logic owned by [SettingsViewModel]. Only
///     enforced when [AppSettings.aiDailyLimitEnabled] is `true`;
///     when the user disables the switch, the guard short-circuits
///     to `AcquireAllowed` so they can run an unlimited number of
///     calls in a session without losing the in-process cooldown or
///     the analyzer-level input sanitization.
///
/// The guard is intentionally state-light: it does not own the
/// counter, it only reads/writes through the view model. This keeps
/// the source of truth in sqflite so a hot restart does not lose the
/// tally. The counter still increments even when the switch is off,
/// so re-enabling the switch mid-day restores the ceiling as if it
/// had never been off.
class AiUsageGuard {
  AiUsageGuard({
    required SettingsViewModel settings,
    Duration cooldown = _defaultCooldown,
  })  : _settings = settings,
        _cooldown = cooldown;

  static const Duration _defaultCooldown = Duration(seconds: 10);

  final SettingsViewModel _settings;
  final Duration _cooldown;

  /// Wall-clock instant of the last successful call inside this
  /// process. `null` until the first call lands. Cleared on a daily
  /// rollover so a previous-day timestamp cannot lock the user out
  /// across midnight. Reads through [clock.now] (from
  /// `package:clock`) so unit tests using `withClock` can advance
  /// time deterministically — `DateTime.now()` itself is a system
  /// call and is not intercepted by `fakeAsync`.
  DateTime? _lastCallAt;

  int get usedToday => _settings.aiCallsToday;
  int get dailyLimit => _settings.aiDailyLimit;
  int get remainingToday => _settings.aiCallsRemainingToday;

  /// Returns the verdict without mutating any state. Safe to call from
  /// `build` methods or button onPressed handlers.
  AcquireResult tryAcquire() {
    final now = clock.now();
    final last = _lastCallAt;
    if (last != null) {
      final elapsed = now.difference(last);
      if (elapsed < _cooldown) {
        return AcquireCooldown(retryAfter: _cooldown - elapsed);
      }
    }
    // The daily-limit switch short-circuits here. The cooldown above
    // already protects against immediate double-fires, and the
    // analyzer still sanitizes / truncates oversized input — the
    // switch only disables the per-day ceiling.
    if (!_settings.aiDailyLimitEnabled) {
      return const AcquireAllowed(remaining: null);
    }
    final used = _settings.aiCallsToday;
    final limit = _settings.aiDailyLimit;
    if (used >= limit) {
      return AcquireDailyLimitReached(limit: limit);
    }
    return AcquireAllowed(remaining: limit - used - 1);
  }

  /// Marks a successful call. Updates both the persisted counter (via
  /// the view model) and the in-process cooldown clock. Failures
  /// (network / parse / 4xx) should NOT call this — only the
  /// post-success path, so a retry after a 429 does not chew up the
  /// daily budget.
  Future<void> recordSuccess() async {
    _lastCallAt = clock.now();
    await _settings.incrementAiCallsToday();
  }

  /// Test-only hook to reset the in-process cooldown clock. The
  /// persisted counter is left intact because the unit tests already
  /// drive it through [SettingsViewModel].
  void resetCooldownForTest() {
    _lastCallAt = null;
  }
}