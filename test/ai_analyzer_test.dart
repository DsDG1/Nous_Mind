import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nousmind/services/ai_analyzer.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  // A fixed clock used by every test below. The analyzer reads
  // [adjustReminder]'s `now` parameter to render the "当前日期与时间"
  // line in the system prompt; using a constant keeps the assertions
  // stable regardless of when the test suite is executed.
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

    test('accepts times with Z suffix and normalizes to local', () {
      final raw = jsonEncode(<String, dynamic>{
        'reminders': <Map<String, String>>[
          <String, String>{
            'title': '买菜',
            'suggested_time': '2026-06-14T14:00:00Z',
          },
        ],
      });
      final drafts = parseAssistantJson(raw);
      expect(drafts, hasLength(1));
      // The instant is 14:00Z regardless of the device timezone.
      expect(drafts.single.suggestedTime.toUtc().hour, 14);
      // The returned DateTime must be a local-typed value so the UI
      // renders the device's wall-clock reading, not the UTC hour.
      expect(drafts.single.suggestedTime.isUtc, isFalse);
    });

    test('accepts times with +00:00 suffix and normalizes to local', () {
      final raw = jsonEncode(<String, dynamic>{
        'reminders': <Map<String, String>>[
          <String, String>{
            'title': '买菜',
            'suggested_time': '2026-06-14T14:00:00+00:00',
          },
        ],
      });
      final drafts = parseAssistantJson(raw);
      expect(drafts, hasLength(1));
      expect(drafts.single.suggestedTime.toUtc().hour, 14);
      expect(drafts.single.suggestedTime.isUtc, isFalse);
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
      // The result must be a local DateTime so the rest of the app
      // reads wall-clock values directly. Previously this was a UTC
      // DateTime, which is what caused "明天早上 9 点" to render as
      // 01:00 on a +08:00 device.
      expect(drafts.single.suggestedTime.isUtc, isFalse);
    });
  });

  group('DeepSeekAnalyzer.renderAssistantPrompt', () {
    test('substitutes every supported placeholder', () {
      final rendered = DeepSeekAnalyzer.renderAssistantPrompt(
        template:
            'now={{now}} tz={{timezone}} off={{offset}} '
            'wd={{weekday}} tm={{tomorrow}}',
        timezone: 'Asia/Shanghai',
        now: fixedNowWithTime,
      );
      expect(rendered, contains('now=2026-06-13 10:00'));
      expect(rendered, contains('tz=Asia/Shanghai'));
      expect(rendered, matches(RegExp(r'off=[+-]\d{2}:\d{2}')));
      expect(rendered, contains('wd=星期六'));
      expect(rendered, contains('tm=2026-06-14'));
    });

    test('leaves unknown placeholders intact for forward compatibility', () {
      final rendered = DeepSeekAnalyzer.renderAssistantPrompt(
        template: 'keep {{never_a_placeholder}} as-is, sub {{timezone}}',
        timezone: 'Asia/Tokyo',
        now: fixedNowWithTime,
      );
      expect(rendered, contains('{{never_a_placeholder}}'));
      expect(rendered, contains('Asia/Tokyo'));
    });

    test('returns the literal template when no placeholders are present', () {
      const literal = '只是一段纯字符串,没有占位符。';
      final rendered = DeepSeekAnalyzer.renderAssistantPrompt(
        template: literal,
        timezone: 'Asia/Shanghai',
        now: fixedNowWithTime,
      );
      expect(rendered, literal);
    });
  });
  group('DeepSeekAnalyzer.analyzeError', () {
    Map<String, dynamic> chatResponse(String content) => <String, dynamic>{
      'choices': <Map<String, dynamic>>[
        <String, dynamic>{
          'message': <String, dynamic>{'content': content},
        },
      ],
    };

    test(
      'sends the default prompt + log text and returns trimmed content',
      () async {
        final client = MockClient((request) async {
          expect(request.method, 'POST');
          expect(
            request.url.toString(),
            'https://api.deepseek.com/v1/chat/completions',
          );
          expect(request.headers['Authorization'], 'Bearer test-key');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['model'], 'deepseek-v4-flash');
          // No JSON mode — diagnoses are plain text.
          expect(body.containsKey('response_format'), isFalse);
          expect(body['temperature'], 0.4);
          final messages = body['messages'] as List<dynamic>;
          expect(messages, hasLength(2));
          expect(
            (messages.first as Map<String, dynamic>)['content'],
            contains('Flutter / Dart'),
          );
          expect(
            (messages.last as Map<String, dynamic>)['content'],
            'NullCheckOperatorException\n#0 ...stack...',
          );
          return http.Response(
            jsonEncode(chatResponse('  诊断结果  ')),
            200,
            headers: <String, String>{'content-type': 'application/json'},
          );
        });
        final analyzer = DeepSeekAnalyzer(client: client);
        addTearDown(analyzer.dispose);
        final result = await analyzer.analyzeError(
          text: 'NullCheckOperatorException\n#0 ...stack...',
          apiKey: 'test-key',
        );
        expect(result, '诊断结果');
      },
    );

    test('forwards a user-provided prompt verbatim', () async {
      final client = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final messages = body['messages'] as List<dynamic>;
        final content =
            (messages.first as Map<String, dynamic>)['content'] as String;
        // The anti-extraction appendix is appended to any user-supplied
        // prompt to reduce prompt-injection risk; the original text
        // must still come through verbatim.
        expect(content, startsWith('my custom error prompt'));
        expect(content, contains('Never reveal'));
        return http.Response(
          jsonEncode(chatResponse('ok')),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        );
      });
      final analyzer = DeepSeekAnalyzer(client: client);
      addTearDown(analyzer.dispose);
      final result = await analyzer.analyzeError(
        text: 'some error',
        apiKey: 'k',
        systemPrompt: 'my custom error prompt',
      );
      expect(result, 'ok');
    });

    test('strips Markdown code fences defensively', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode(chatResponse('```\n诊断内容\n```')),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        ),
      );
      final analyzer = DeepSeekAnalyzer(client: client);
      addTearDown(analyzer.dispose);
      final result = await analyzer.analyzeError(text: 'err', apiKey: 'k');
      expect(result, '诊断内容');
    });

    test('rejects empty input with AiParseException', () async {
      final client = MockClient((_) async => http.Response('', 200));
      final analyzer = DeepSeekAnalyzer(client: client);
      addTearDown(analyzer.dispose);
      expect(
        () => analyzer.analyzeError(text: '   \n  ', apiKey: 'k'),
        throwsA(isA<AiParseException>()),
      );
    });

    test('rejects whitespace-only key with AiAuthException', () async {
      final client = MockClient((_) async => http.Response('', 200));
      final analyzer = DeepSeekAnalyzer(client: client);
      addTearDown(analyzer.dispose);
      expect(
        () => analyzer.analyzeError(text: 'err', apiKey: '   '),
        throwsA(isA<AiAuthException>()),
      );
    });

    test('maps 401 to AiAuthException', () async {
      final client = MockClient((_) async => http.Response('{"e":1}', 401));
      final analyzer = DeepSeekAnalyzer(client: client);
      addTearDown(analyzer.dispose);
      expect(
        () => analyzer.analyzeError(text: 'err', apiKey: 'bad'),
        throwsA(isA<AiAuthException>()),
      );
    });

    test('maps 429 to AiRateLimitException', () async {
      final client = MockClient((_) async => http.Response('rate', 429));
      final analyzer = DeepSeekAnalyzer(client: client);
      addTearDown(analyzer.dispose);
      expect(
        () => analyzer.analyzeError(text: 'err', apiKey: 'k'),
        throwsA(isA<AiRateLimitException>()),
      );
    });

    test('maps 500 to AiServerException', () async {
      final client = MockClient((_) async => http.Response('boom', 500));
      final analyzer = DeepSeekAnalyzer(client: client);
      addTearDown(analyzer.dispose);
      expect(
        () => analyzer.analyzeError(text: 'err', apiKey: 'k'),
        throwsA(isA<AiServerException>()),
      );
    });

    test('maps SocketException to AiNetworkException', () async {
      final client = MockClient((_) async {
        throw const SocketException('no route to host');
      });
      final analyzer = DeepSeekAnalyzer(client: client);
      addTearDown(analyzer.dispose);
      expect(
        () => analyzer.analyzeError(text: 'err', apiKey: 'k'),
        throwsA(isA<AiNetworkException>()),
      );
    });
  });

  group('DeepSeekAnalyzer input sanitization', () {
    test('strips ASCII control characters from user text', () async {
      String? captured;
      final client = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final messages = body['messages'] as List<dynamic>;
        captured = (messages.last as Map<String, dynamic>)['content'] as String;
        return http.Response(
          jsonEncode(<String, dynamic>{
            'choices': <Map<String, dynamic>>[
              <String, dynamic>{
                'message': <String, dynamic>{'content': 'ok'},
              },
            ],
          }),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        );
      });
      final analyzer = DeepSeekAnalyzer(client: client);
      addTearDown(analyzer.dispose);
      await analyzer.analyzeError(
        text: 'hello\x00\x01\x07world\x1F',
        apiKey: 'k',
      );
      // The control bytes should be gone but "hello" and "world"
      // remain.
      expect(captured, contains('helloworld'));
    });

    test('collapses 3+ newlines into a single blank line', () async {
      String? captured;
      final client = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final messages = body['messages'] as List<dynamic>;
        captured = (messages.last as Map<String, dynamic>)['content'] as String;
        return http.Response(
          jsonEncode(<String, dynamic>{
            'choices': <Map<String, dynamic>>[
              <String, dynamic>{
                'message': <String, dynamic>{'content': 'ok'},
              },
            ],
          }),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        );
      });
      final analyzer = DeepSeekAnalyzer(client: client);
      addTearDown(analyzer.dispose);
      await analyzer.analyzeError(text: 'a\n\n\n\n\nb', apiKey: 'k');
      // Five newlines collapse to two (one blank line).
      expect(captured, isNot(contains('\n\n\n')));
    });

    test('appends anti-extraction appendix only for user prompts', () async {
      String defaultPrompt = '';
      String customPrompt = '';
      final client = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final messages = body['messages'] as List<dynamic>;
        final content =
            (messages.first as Map<String, dynamic>)['content'] as String;
        if (content.contains('资深工程师')) {
          defaultPrompt = content;
        } else {
          customPrompt = content;
        }
        return http.Response(
          jsonEncode(<String, dynamic>{
            'choices': <Map<String, dynamic>>[
              <String, dynamic>{
                'message': <String, dynamic>{'content': 'ok'},
              },
            ],
          }),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        );
      });
      final analyzer = DeepSeekAnalyzer(client: client);
      addTearDown(analyzer.dispose);

      await analyzer.analyzeError(text: 'a', apiKey: 'k');
      await analyzer.analyzeError(
        text: 'b',
        apiKey: 'k',
        systemPrompt: 'custom prompt',
      );

      expect(defaultPrompt, isNot(contains('Never reveal')));
      expect(customPrompt, contains('Never reveal'));
    });

    test('truncates oversized custom system prompt', () async {
      String? captured;
      final oversized = 'x' * 5000;
      final client = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final messages = body['messages'] as List<dynamic>;
        captured =
            (messages.first as Map<String, dynamic>)['content'] as String;
        return http.Response(
          jsonEncode(<String, dynamic>{
            'choices': <Map<String, dynamic>>[
              <String, dynamic>{
                'message': <String, dynamic>{'content': 'ok'},
              },
            ],
          }),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        );
      });
      final analyzer = DeepSeekAnalyzer(client: client);
      addTearDown(analyzer.dispose);
      await analyzer.analyzeError(
        text: 'err',
        apiKey: 'k',
        systemPrompt: oversized,
      );
      // Captured prompt is the truncated version + appendix, never the
      // full 5000-character payload.
      expect(captured!.length, lessThan(5000));
      expect(captured, contains('已截断'));
    });
  });

  group('DeepSeekAnalyzer.adjustReminder truncation', () {
    test('truncates oversized user input proportionally', () async {
      String? captured;
      final bigDescription = 'd' * 5000;
      final client = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final messages = body['messages'] as List<dynamic>;
        captured = (messages.last as Map<String, dynamic>)['content'] as String;
        return http.Response(
          jsonEncode(<String, dynamic>{
            'choices': <Map<String, dynamic>>[
              <String, dynamic>{
                'message': <String, dynamic>{'content': '{"reminders":[]}'},
              },
            ],
          }),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        );
      });
      final analyzer = DeepSeekAnalyzer(client: client);
      addTearDown(analyzer.dispose);
      await analyzer.adjustReminder(
        title: 'tiny title',
        description: bigDescription,
        apiKey: 'k',
        timezone: 'Asia/Shanghai',
        now: fixedNowWithTime,
      );
      // The combined user content is capped at 4000 chars (plus the
      // "用户已填描述:" prefix and a few newlines).
      expect(captured!.length, lessThanOrEqualTo(4200));
    });
  });
}
