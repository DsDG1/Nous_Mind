import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/models/app_settings.dart';
import 'package:flutter_application_1/models/reminder_draft.dart';
import 'package:flutter_application_1/services/ai_analyzer.dart';
import 'package:flutter_application_1/services/settings_repository.dart';
import 'package:flutter_application_1/viewmodels/ai_assist_view_model.dart';
import 'package:flutter_application_1/viewmodels/settings_view_model.dart';

class _FakeRepo implements SettingsRepository {
  @override
  Future<AppSettings> load() async => const AppSettings();

  @override
  Future<void> save(AppSettings settings) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ScriptedAnalyzer implements AiAnalyzer {
  _ScriptedAnalyzer(this._responses);

  final List<Object> _responses;
  int _index = 0;
  int callCount = 0;

  @override
  Future<List<ReminderDraft>> analyze({
    String? text,
    String? imagePath,
    required String apiKey,
    required String timezone,
    required DateTime now,
  }) async {
    callCount++;
    if (_index >= _responses.length) {
      throw StateError('No scripted response for call #$_index');
    }
    final response = _responses[_index++];
    if (response is List<ReminderDraft>) return response;
    if (response is Exception) throw response;
    throw StateError('Unsupported scripted response: $response');
  }

  @override
  void dispose() {}

  @override
  void setChineseOcrProvider(bool Function() provider) {}
}

List<ReminderDraft> _okDrafts() => <ReminderDraft>[
  ReminderDraft(id: 'a', title: 'A', suggestedTime: DateTime(2026, 1, 1)),
];

({SettingsViewModel settings, _FakeRepo repo}) _makeBootSync() {
  final repo = _FakeRepo();
  const initial = AppSettings(aiAssistantEnabled: true, aiApiKey: 'sk-test');
  final vm = SettingsViewModel(repository: repo, initialSettings: initial);
  return (settings: vm, repo: repo);
}

void main() {
  // Step between analyze() calls for the auth lockout tests. Must be
  // larger than [AiAssistViewModel.clickWindow] so the throttle never
  // masks the auth-failure counting we are exercising.
  const authStep = Duration(seconds: 4);

  group('AiAssistViewModel — auth lockout', () {
    test('locks after three consecutive AiAuthException failures', () async {
      final boot = _makeBootSync();
      final analyzer = _ScriptedAnalyzer(<Object>[
        AiAuthException('nope'),
        AiAuthException('nope'),
        AiAuthException('nope'),
      ]);
      final vm = AiAssistViewModel(analyzer, settings: boot.settings);

      for (var i = 0; i < 3; i++) {
        await vm.analyze(
          apiKey: 'sk-test',
          timezone: 'UTC',
          now: DateTime(2026, 6, 14, 12, 0, i * authStep.inSeconds),
          text: 'hi',
        );
      }
      expect(vm.consecutiveAuthFailures, 3);
      expect(vm.isLockedDueToAuth, isTrue);
      expect(analyzer.callCount, 3);
    });

    test('non-auth exceptions do not advance the failure counter', () async {
      // Mix one auth failure with two non-auth failures; the counter
      // should stay at 1 (no auth failures beyond the first).
      final boot = _makeBootSync();
      final analyzer = _ScriptedAnalyzer(<Object>[
        AiAuthException('nope'),
        AiServerException('boom'),
        AiServerException('boom'),
      ]);
      final vm = AiAssistViewModel(analyzer, settings: boot.settings);

      for (var i = 0; i < 3; i++) {
        await vm.analyze(
          apiKey: 'sk-test',
          timezone: 'UTC',
          now: DateTime(2026, 6, 14, 12, 0, i * authStep.inSeconds),
          text: 'hi',
        );
      }
      expect(vm.consecutiveAuthFailures, 1);
      expect(vm.isLockedDueToAuth, isFalse);
    });

    test('a successful analyze does not clear the lockout', () async {
      final boot = _makeBootSync();
      final analyzer = _ScriptedAnalyzer(<Object>[
        AiAuthException('nope'),
        AiAuthException('nope'),
        AiAuthException('nope'),
        _okDrafts(),
      ]);
      final vm = AiAssistViewModel(analyzer, settings: boot.settings);

      for (var i = 0; i < 3; i++) {
        await vm.analyze(
          apiKey: 'sk-test',
          timezone: 'UTC',
          now: DateTime(2026, 6, 14, 12, 0, i * authStep.inSeconds),
          text: 'hi',
        );
      }
      expect(vm.isLockedDueToAuth, isTrue);

      await vm.analyze(
        apiKey: 'sk-test',
        timezone: 'UTC',
        now: DateTime(2026, 6, 14, 12, 1, 0),
        text: 'hi',
      );
      expect(vm.isLockedDueToAuth, isTrue);
      expect(analyzer.callCount, 3);
    });

    test('analyze is a no-op while locked', () async {
      final boot = _makeBootSync();
      final analyzer = _ScriptedAnalyzer(<Object>[
        AiAuthException('nope'),
        AiAuthException('nope'),
        AiAuthException('nope'),
        _okDrafts(),
      ]);
      final vm = AiAssistViewModel(analyzer, settings: boot.settings);
      for (var i = 0; i < 3; i++) {
        await vm.analyze(
          apiKey: 'sk-test',
          timezone: 'UTC',
          now: DateTime(2026, 6, 14, 12, 0, i * authStep.inSeconds),
          text: 'hi',
        );
      }
      expect(vm.isLockedDueToAuth, isTrue);
      final callsBefore = analyzer.callCount;

      await vm.analyze(
        apiKey: 'sk-test',
        timezone: 'UTC',
        now: DateTime(2026, 6, 14, 12, 1, 0),
        text: 'hi',
      );
      expect(analyzer.callCount, callsBefore);
    });

    test('changing the API key clears the lockout', () async {
      final boot = _makeBootSync();
      final analyzer = _ScriptedAnalyzer(<Object>[
        AiAuthException('nope'),
        AiAuthException('nope'),
        AiAuthException('nope'),
        _okDrafts(),
        _okDrafts(),
      ]);
      final vm = AiAssistViewModel(analyzer, settings: boot.settings);
      for (var i = 0; i < 3; i++) {
        await vm.analyze(
          apiKey: 'sk-test',
          timezone: 'UTC',
          now: DateTime(2026, 6, 14, 12, 0, i * authStep.inSeconds),
          text: 'hi',
        );
      }
      expect(vm.isLockedDueToAuth, isTrue);

      await boot.settings.setAiApiKey('sk-new');

      expect(vm.isLockedDueToAuth, isFalse);
      expect(vm.consecutiveAuthFailures, 0);

      await vm.analyze(
        apiKey: 'sk-new',
        timezone: 'UTC',
        now: DateTime(2026, 6, 14, 12, 1, 0),
        text: 'hi',
      );
      expect(vm.status, AiAssistStatus.success);
      expect(analyzer.callCount, 4);
    });
  });

  group('AiAssistViewModel — click throttle', () {
    test(
      'three clicks in the window flips throttle on and blocks the third',
      () {
        fakeAsync((async) {
          final boot = _makeBootSync();
          final analyzer = _ScriptedAnalyzer(<Object>[
            _okDrafts(),
            _okDrafts(),
          ]);
          final vm = AiAssistViewModel(analyzer, settings: boot.settings);

          void tap() {
            // Pass the fake clock so the internal `DateTime.now()`
            // comparisons agree with the window timestamps.
            vm
                .analyze(
                  apiKey: 'sk-test',
                  timezone: 'UTC',
                  now: DateTime.now(),
                  text: 'hi',
                )
                .then((_) {});
            async.flushMicrotasks();
          }

          tap();
          async.elapse(const Duration(milliseconds: 500));
          tap();
          async.elapse(const Duration(milliseconds: 500));
          tap();
          async.flushMicrotasks();

          expect(vm.isThrottled, isTrue);
          expect(vm.throttleRemainingSeconds, greaterThan(0));
          expect(vm.throttleRemainingSeconds, lessThanOrEqualTo(10));
          // Two requests actually fired before the third was short-circuited.
          expect(analyzer.callCount, 2);
        });
      },
    );

    test('throttle clears after the duration elapses', () {
      fakeAsync((async) {
        final boot = _makeBootSync();
        final analyzer = _ScriptedAnalyzer(<Object>[_okDrafts()]);
        final vm = AiAssistViewModel(analyzer, settings: boot.settings);

        void tap() {
          vm
              .analyze(
                apiKey: 'sk-test',
                timezone: 'UTC',
                now: DateTime.now(),
                text: 'hi',
              )
              .then((_) {});
          async.flushMicrotasks();
        }

        tap();
        async.elapse(const Duration(milliseconds: 500));
        tap();
        async.elapse(const Duration(milliseconds: 500));
        tap();
        async.flushMicrotasks();

        expect(vm.isThrottled, isTrue);

        async.elapse(const Duration(seconds: 11));
        expect(vm.isThrottled, isFalse);
        expect(vm.throttleRemainingSeconds, 0);
      });
    });

    test('throttleRemainingSeconds counts down monotonically', () {
      fakeAsync((async) {
        final boot = _makeBootSync();
        final analyzer = _ScriptedAnalyzer(<Object>[_okDrafts()]);
        final vm = AiAssistViewModel(analyzer, settings: boot.settings);

        void tap() {
          vm
              .analyze(
                apiKey: 'sk-test',
                timezone: 'UTC',
                now: DateTime.now(),
                text: 'hi',
              )
              .then((_) {});
          async.flushMicrotasks();
        }

        tap();
        async.elapse(const Duration(milliseconds: 500));
        tap();
        async.elapse(const Duration(milliseconds: 500));
        tap();
        async.flushMicrotasks();

        final first = vm.throttleRemainingSeconds;
        async.elapse(const Duration(seconds: 2));
        final second = vm.throttleRemainingSeconds;
        expect(second, lessThan(first));
        async.elapse(const Duration(seconds: 10));
        expect(vm.throttleRemainingSeconds, 0);
      });
    });

    test('analyze is rejected while throttled', () {
      fakeAsync((async) {
        final boot = _makeBootSync();
        final analyzer = _ScriptedAnalyzer(<Object>[_okDrafts()]);
        final vm = AiAssistViewModel(analyzer, settings: boot.settings);

        void tap() {
          vm
              .analyze(
                apiKey: 'sk-test',
                timezone: 'UTC',
                now: DateTime.now(),
                text: 'hi',
              )
              .then((_) {});
          async.flushMicrotasks();
        }

        tap();
        async.elapse(const Duration(milliseconds: 500));
        tap();
        async.elapse(const Duration(milliseconds: 500));
        tap();
        async.flushMicrotasks();

        final callsBefore = analyzer.callCount;
        async.elapse(const Duration(seconds: 1));
        tap();
        async.flushMicrotasks();
        expect(analyzer.callCount, callsBefore);
        expect(vm.isThrottled, isTrue);
      });
    });
  });
}
