import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/services/ai_analyzer.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  // A fixed clock used by every test below. The analyzer only reads
  // [AiAnalyzer.analyze]'s `now` parameter to render the "当前日期与时间"
  // line in the system prompt; using a constant keeps the assertions
  // stable regardless of when the test suite is executed.
  final DateTime fixedNow = DateTime(2026, 6, 13);
  final DateTime fixedNowWithTime = DateTime(2026, 6, 13, 10, 0);

  group('parseAssistantJson', () {
    test('parses a valid payload with two reminders', () {
      final raw = jsonEncode(<String, dynamic>{
        'reminders': <Map<String, String>>[
          <String, String>{
            'title': '买菜',
            'suggested_time': '2026-06-15T18:30:00+08:00',
            'reason': '原文提到傍晚去买菜',
          },
          <String, String>{
            'title': '回电话',
            'suggested_time': '2026-06-16T10:00:00+08:00',
          },
        ],
      });

      final drafts = parseAssistantJson(raw);
      expect(drafts, hasLength(2));
      expect(drafts[0].title, '买菜');
      // 18:30 in Asia/Shanghai (UTC+8) is 10:30Z.
      expect(
        drafts[0].suggestedTime.toUtc().toIso8601String(),
        '2026-06-15T10:30:00.000Z',
      );
      expect(drafts[0].reason, '原文提到傍晚去买菜');
      expect(drafts[0].selected, isTrue);
      expect(drafts[1].title, '回电话');
      expect(drafts[1].reason, isNull);
    });

    test('accepts Markdown-fenced JSON', () {
      final raw = '''
```json
{"reminders":[]}
```
''';
      expect(parseAssistantJson(raw), isEmpty);
    });

    test('returns empty list for explicit empty reminders', () {
      final drafts = parseAssistantJson('{"reminders":[]}');
      expect(drafts, isEmpty);
    });

    test('rejects missing reminders key', () {
      expect(() => parseAssistantJson('{}'), throwsA(isA<AiParseException>()));
    });

    test('rejects non-object JSON', () {
      expect(() => parseAssistantJson('[]'), throwsA(isA<AiParseException>()));
    });

    test('rejects malformed JSON', () {
      expect(
        () => parseAssistantJson('not json'),
        throwsA(isA<AiParseException>()),
      );
    });

    test('rejects entries without a title', () {
      final raw = jsonEncode(<String, dynamic>{
        'reminders': <Map<String, dynamic>>[
          <String, dynamic>{'suggested_time': '2026-06-15T18:30:00+08:00'},
        ],
      });
      expect(() => parseAssistantJson(raw), throwsA(isA<AiParseException>()));
    });

    test('rejects entries with non-ISO suggested_time', () {
      final raw = jsonEncode(<String, dynamic>{
        'reminders': <Map<String, String>>[
          <String, String>{'title': '买菜', 'suggested_time': 'not a date'},
        ],
      });
      expect(() => parseAssistantJson(raw), throwsA(isA<AiParseException>()));
    });

    test('ignores unknown trailing keys', () {
      final raw = jsonEncode(<String, dynamic>{
        'reminders': <Map<String, dynamic>>[
          <String, dynamic>{
            'title': '买菜',
            'suggested_time': '2026-06-15T18:30:00+08:00',
            'confidence': 0.9,
            'tags': <String>['shopping'],
          },
        ],
        'model': 'deepseek-v4-flash',
      });
      final drafts = parseAssistantJson(raw);
      expect(drafts, hasLength(1));
      expect(drafts.single.title, '买菜');
    });

    test('rejects times with Z suffix', () {
      final raw = jsonEncode(<String, dynamic>{
        'reminders': <Map<String, String>>[
          <String, String>{
            'title': '买菜',
            'suggested_time': '2026-06-14T14:00:00Z',
          },
        ],
      });
      expect(() => parseAssistantJson(raw), throwsA(isA<AiParseException>()));
    });

    test('rejects times with +00:00 suffix', () {
      final raw = jsonEncode(<String, dynamic>{
        'reminders': <Map<String, String>>[
          <String, String>{
            'title': '买菜',
            'suggested_time': '2026-06-14T14:00:00+00:00',
          },
        ],
      });
      expect(() => parseAssistantJson(raw), throwsA(isA<AiParseException>()));
    });

    test('rejects times with no offset', () {
      final raw = jsonEncode(<String, dynamic>{
        'reminders': <Map<String, String>>[
          <String, String>{
            'title': '买菜',
            'suggested_time': '2026-06-14T14:00:00',
          },
        ],
      });
      expect(() => parseAssistantJson(raw), throwsA(isA<AiParseException>()));
    });

    test('accepts times with explicit non-UTC offset', () {
      final raw = jsonEncode(<String, dynamic>{
        'reminders': <Map<String, String>>[
          <String, String>{
            'title': '买菜',
            'suggested_time': '2026-06-14T14:00:00+08:00',
          },
        ],
      });
      final drafts = parseAssistantJson(raw);
      expect(drafts, hasLength(1));
      // 14:00 +08:00 == 06:00 UTC.
      expect(drafts.single.suggestedTime.toUtc().hour, 6);
    });
  });

  group('DeepSeekAnalyzer HTTP contract', () {
    test('returns parsed drafts on 200 response (no image path)', () async {
      final canned = <String, dynamic>{
        'choices': <Map<String, dynamic>>[
          <String, dynamic>{
            'message': <String, dynamic>{
              'content': jsonEncode(<String, dynamic>{
                'reminders': <Map<String, String>>[
                  <String, String>{
                    'title': '开会',
                    'suggested_time': '2026-06-15T15:00:00+08:00',
                  },
                ],
              }),
            },
          },
        ],
      };
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(
          request.url.toString(),
          'https://api.deepseek.com/v1/chat/completions',
        );
        expect(request.headers['Authorization'], 'Bearer test-key');
        expect(request.headers['Content-Type'], contains('application/json'));
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['model'], 'deepseek-v4-flash');
        expect(body['response_format'], <String, String>{
          'type': 'json_object',
        });
        expect(body['thinking'], <String, String>{'type': 'disabled'});
        final messages = body['messages'] as List<dynamic>;
        expect(messages, hasLength(2));
        expect((messages.first as Map<String, dynamic>)['role'], 'system');
        final systemPrompt =
            ((messages.first as Map<String, dynamic>)['content'] as String);
        // System prompt must include today's date, time of day, and
        // weekday so the model can resolve relative references like
        // "明天" or "下午3点" against the user's actual local clock.
        expect(systemPrompt, contains('2026-06-13 10:00'));
        expect(systemPrompt, contains('星期六'));
        expect(systemPrompt, contains('Asia/Shanghai'));
        // The prompt must contain a timezone contract section, a
        // concrete example with the dynamic tomorrow date, and the
        // device's current time rendered as wall-clock local time.
        expect(systemPrompt, contains('【时间规则】'));
        expect(
          systemPrompt,
          contains('2026-06-14'),
        ); // tomorrow from fixedNowWithTime
        expect(systemPrompt, contains('明天下午2点去上海'));
        expect(systemPrompt, contains('不是 UTC'));
        // The placeholder token must be fully substituted at runtime,
        // and the substituted offset must look like ±HH:MM.
        expect(systemPrompt, isNot(contains('[TZ_OFFSET]')));
        expect(systemPrompt, matches(RegExp(r'[+-]\d{2}:\d{2}')));
        return http.Response(
          jsonEncode(canned),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        );
      });

      final analyzer = DeepSeekAnalyzer(client: client);
      addTearDown(analyzer.dispose);
      final drafts = await analyzer.analyze(
        text: '明天下午 3 点开会',
        apiKey: 'test-key',
        timezone: 'Asia/Shanghai',
        now: fixedNowWithTime,
      );
      expect(drafts, hasLength(1));
      expect(drafts.single.title, '开会');
    });

    test('maps 401 to AiAuthException', () async {
      final client = MockClient((_) async => http.Response('{"err":1}', 401));
      final analyzer = DeepSeekAnalyzer(client: client);
      expect(
        () => analyzer.analyze(
          text: 'x',
          apiKey: 'bad',
          timezone: 'Asia/Shanghai',
          now: fixedNow,
        ),
        throwsA(isA<AiAuthException>()),
      );
    });

    test('maps 403 to AiAuthException', () async {
      final client = MockClient((_) async => http.Response('forbidden', 403));
      final analyzer = DeepSeekAnalyzer(client: client);
      expect(
        () => analyzer.analyze(
          text: 'x',
          apiKey: 'bad',
          timezone: 'Asia/Shanghai',
          now: fixedNow,
        ),
        throwsA(isA<AiAuthException>()),
      );
    });

    test('maps 429 to AiRateLimitException', () async {
      final client = MockClient((_) async => http.Response('rate', 429));
      final analyzer = DeepSeekAnalyzer(client: client);
      expect(
        () => analyzer.analyze(
          text: 'x',
          apiKey: 'k',
          timezone: 'Asia/Shanghai',
          now: fixedNow,
        ),
        throwsA(isA<AiRateLimitException>()),
      );
    });

    test('maps 500 to AiServerException', () async {
      final client = MockClient((_) async => http.Response('boom', 500));
      final analyzer = DeepSeekAnalyzer(client: client);
      expect(
        () => analyzer.analyze(
          text: 'x',
          apiKey: 'k',
          timezone: 'Asia/Shanghai',
          now: fixedNow,
        ),
        throwsA(isA<AiServerException>()),
      );
    });

    test('maps malformed body to AiParseException', () async {
      final client = MockClient((_) async => http.Response('not json', 200));
      final analyzer = DeepSeekAnalyzer(client: client);
      expect(
        () => analyzer.analyze(
          text: 'x',
          apiKey: 'k',
          timezone: 'Asia/Shanghai',
          now: fixedNow,
        ),
        throwsA(isA<AiParseException>()),
      );
    });

    test('maps SocketException to AiNetworkException', () async {
      final client = MockClient((_) async {
        throw const SocketException('no route to host');
      });
      final analyzer = DeepSeekAnalyzer(client: client);
      expect(
        () => analyzer.analyze(
          text: 'x',
          apiKey: 'k',
          timezone: 'Asia/Shanghai',
          now: fixedNow,
        ),
        throwsA(isA<AiNetworkException>()),
      );
    });

    test('maps TimeoutException to AiNetworkException', () async {
      final client = MockClient((_) async {
        throw TimeoutException('slow');
      });
      final analyzer = DeepSeekAnalyzer(client: client);
      expect(
        () => analyzer.analyze(
          text: 'x',
          apiKey: 'k',
          timezone: 'Asia/Shanghai',
          now: fixedNow,
        ),
        throwsA(isA<AiNetworkException>()),
      );
    });

    test('rejects whitespace-only key with AiAuthException', () async {
      final client = MockClient((_) async => http.Response('', 200));
      final analyzer = DeepSeekAnalyzer(client: client);
      expect(
        () => analyzer.analyze(
          text: 'x',
          apiKey: '   ',
          timezone: 'Asia/Shanghai',
          now: fixedNow,
        ),
        throwsA(isA<AiAuthException>()),
      );
    });
  });
}
