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

    test('defaults chineseOcrEnabled to true when key is absent', () {
      // Changed in 1.3.1: new installs opt in to the bundled Chinese OCR
      // by default. Existing users keep whatever was already in their
      // JSON blob (the persisted `false` survives because `fromJson` only
      // applies the default when the key is missing).
      final parsed = AppSettings.fromJson(const <String, dynamic>{});
      expect(parsed.chineseOcrEnabled, isTrue);
    });

    test(
      'preserves chineseOcrEnabled=false from older settings blobs',
      () {
        // Round-trip a pre-1.3.1 settings JSON that explicitly stored
        // the old default. The new default must NOT override the
        // user's saved value.
        final parsed = AppSettings.fromJson(const <String, dynamic>{
          'chinese_ocr_enabled': false,
        });
        expect(parsed.chineseOcrEnabled, isFalse);
      },
    );

    test('round-trips chineseOcrEnabled with the rest of the settings', () {
      const original = AppSettings(
        aiAssistantEnabled: true,
        aiApiKey: 'sk-x',
        chineseOcrEnabled: true,
      );
      final restored = AppSettings.fromJson(original.toJson());
      expect(restored.chineseOcrEnabled, isTrue);
      expect(restored.aiAssistantEnabled, isTrue);
      expect(restored.aiApiKey, 'sk-x');
    });

    test('copyWith only touches chineseOcrEnabled when asked', () {
      const original = AppSettings(aiAssistantEnabled: true, aiApiKey: 'sk-x');
      final updated = original.copyWith(chineseOcrEnabled: true);
      expect(updated.chineseOcrEnabled, isTrue);
      expect(updated.aiAssistantEnabled, original.aiAssistantEnabled);
      expect(updated.aiApiKey, original.aiApiKey);
    });
  });
}
