import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nousmind/services/ai_usage_guard.dart';

import 'helpers/fakes.dart';

void main() {
  group('AiUsageGuard.tryAcquire', () {
    test('returns allowed when under the limit and never called', () {
      final vm = makeSettingsVm(aiDailyLimit: 3, aiCallsToday: 0);
      final guard = AiUsageGuard(settings: vm);

      final result = guard.tryAcquire();
      expect(result, isA<AcquireAllowed>());
      expect((result as AcquireAllowed).remaining, 2);
    });

    test('returns cooldown inside the in-process window', () {
      final vm = makeSettingsVm(aiDailyLimit: 3);
      final guard = AiUsageGuard(
        settings: vm,
        cooldown: const Duration(seconds: 10),
      );

      withClock(Clock.fixed(DateTime(2026, 6, 15, 10, 0, 0)), () {
        expect(guard.tryAcquire(), isA<AcquireAllowed>());

        // Simulate a successful call landing at the same instant.
        guard.recordSuccess();

        // Immediately after, another tryAcquire must report cooldown.
        final verdict = guard.tryAcquire();
        expect(verdict, isA<AcquireCooldown>());
        expect((verdict as AcquireCooldown).retryAfter.inSeconds, 10);
      });
    });

    test('cooldown clears once the window elapses', () {
      final vm = makeSettingsVm(aiDailyLimit: 3);
      final guard = AiUsageGuard(
        settings: vm,
        cooldown: const Duration(seconds: 10),
      );

      var now = DateTime(2026, 6, 15, 10, 0, 0);
      withClock(Clock.fixed(now), () {
        guard.recordSuccess();
      });
      now = now.add(const Duration(seconds: 11));
      withClock(Clock.fixed(now), () {
        expect(guard.tryAcquire(), isA<AcquireAllowed>());
      });
    });

    test('returns daily limit when usage reaches the ceiling', () {
      final vm = makeSettingsVm(aiDailyLimit: 2, aiCallsToday: 2);
      final guard = AiUsageGuard(settings: vm);

      final verdict = guard.tryAcquire();
      expect(verdict, isA<AcquireDailyLimitReached>());
      expect((verdict as AcquireDailyLimitReached).limit, 2);
    });

    test('treats a stale resetAt from a previous day as zero', () {
      // Stored "yesterday" but the counter says 5 used. Guard must
      // pretend today is fresh and allow the call.
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final vm = makeSettingsVm(
        aiDailyLimit: 3,
        aiCallsToday: 5,
        aiCallsResetAt: yesterday,
      );
      final guard = AiUsageGuard(settings: vm);

      // The view model's getter applies the rollover for the read;
      // the guard delegates to it via tryAcquire.
      expect(guard.tryAcquire(), isA<AcquireAllowed>());
    });

    test('skips the ceiling check when the quota switch is off', () {
      final vm = makeSettingsVm(
        aiDailyLimit: 50,
        aiDailyLimitEnabled: false,
        aiCallsToday: 999,
      );
      final guard = AiUsageGuard(settings: vm);

      final result = guard.tryAcquire();
      expect(result, isA<AcquireAllowed>());
      // The remaining field must be null so the UI can render
      // "今日不限制" instead of "-1".
      expect((result as AcquireAllowed).remaining, isNull);
    });

    test('ceiling kicks in again when the switch flips back on', () async {
      final vm = makeSettingsVm(
        aiDailyLimit: 50,
        aiDailyLimitEnabled: false,
        aiCallsToday: 999,
      );
      final guard = AiUsageGuard(settings: vm);

      expect(guard.tryAcquire(), isA<AcquireAllowed>());
      await vm.setAiDailyLimitEnabled(true);
      expect(guard.tryAcquire(), isA<AcquireDailyLimitReached>());
    });
  });

  group('AiUsageGuard.recordSuccess', () {
    test('increments the persisted counter via the view model', () async {
      final vm = makeSettingsVm(aiDailyLimit: 3, aiCallsToday: 0);
      final guard = AiUsageGuard(settings: vm);

      await guard.recordSuccess();

      expect(vm.settings.aiCallsToday, 1);
      expect(vm.settings.aiCallsResetAt, isNotNull);
    });

    test('reset to 1 on a stale resetAt instead of incrementing', () async {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final vm = makeSettingsVm(
        aiDailyLimit: 3,
        aiCallsToday: 7,
        aiCallsResetAt: yesterday,
      );
      final guard = AiUsageGuard(settings: vm);

      await guard.recordSuccess();

      expect(vm.settings.aiCallsToday, 1);
    });
  });

  group('AiUsageGuard + resetAiUsage', () {
    test('reset clears the counter regardless of switch state', () async {
      final vm = makeSettingsVm(
        aiDailyLimit: 50,
        aiDailyLimitEnabled: false,
        aiCallsToday: 7,
      );
      final guard = AiUsageGuard(settings: vm);

      // Switch is off, but the user can still wipe the count if they
      // re-enable the switch and want to start over.
      await vm.resetAiUsage();

      expect(vm.settings.aiCallsToday, 0);
      expect(vm.settings.aiCallsResetAt, isNull);
      expect(guard.tryAcquire(), isA<AcquireAllowed>());
    });
  });
}