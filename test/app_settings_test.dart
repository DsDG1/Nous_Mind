import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/models/app_settings.dart';

void main() {
  group('AppSettings migration policy', () {
    test('defaults aiAssistantEnabled to false when key is absent', () {
      final parsed = AppSettings.fromJson(const <String, dynamic>{});
      expect(parsed.aiAssistantEnabled, isFalse);
    });

    test('keeps aiAssistantEnabled false when only an api key is stored', () {
      final parsed = AppSettings.fromJson(const <String, dynamic>{
        'ai_api_key': 'sk-old-user',
      });
      expect(parsed.aiAssistantEnabled, isFalse);
      expect(parsed.aiApiKey, 'sk-old-user');
    });

    test('round-trips enabled and key together', () {
      const original = AppSettings(aiAssistantEnabled: true, aiApiKey: 'sk-x');
      final restored = AppSettings.fromJson(original.toJson());
      expect(restored.aiAssistantEnabled, isTrue);
      expect(restored.aiApiKey, 'sk-x');
    });
  });
}
