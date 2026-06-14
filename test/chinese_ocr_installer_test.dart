import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/services/chinese_ocr_installer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('chinese_ocr_module');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('ChineseOcrInstaller', () {
    test('refresh maps "installed" to installed and notifies once', () async {
      var calls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'checkModule');
            calls++;
            return 'installed';
          });

      final installer = ChineseOcrInstaller();
      var notifications = 0;
      installer.addListener(() => notifications++);

      final status = await installer.refresh();
      expect(status, OcrModuleStatus.installed);
      expect(installer.status, OcrModuleStatus.installed);
      expect(installer.isBusy, isFalse);
      expect(calls, 1);
      expect(notifications, 1);
    });

    test('refresh maps each known string to the expected enum value', () async {
      final mapping = <String, OcrModuleStatus>{
        'installed': OcrModuleStatus.installed,
        'downloading': OcrModuleStatus.downloading,
        'pending': OcrModuleStatus.pending,
        'notInstalled': OcrModuleStatus.notInstalled,
        'unsupported': OcrModuleStatus.unsupported,
      };

      for (final entry in mapping.entries) {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async => entry.key);
        final installer = ChineseOcrInstaller();
        final status = await installer.refresh();
        expect(status, entry.value, reason: 'raw=${entry.key}');
      }
    });

    test('refresh falls back to unsupported on PlatformException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            throw PlatformException(code: 'BOOM', message: 'no play services');
          });

      final installer = ChineseOcrInstaller();
      final status = await installer.refresh();
      expect(status, OcrModuleStatus.unsupported);
      expect(installer.status, OcrModuleStatus.unsupported);
    });

    test('refresh treats MissingPluginException as installed', () async {
      // Routed through an unregistered ephemeral channel to simulate
      // the iOS-no-handler case (production iOS always registers a
      // handler that returns "installed" for the bundled model).
      const ephemeral = MethodChannel('chinese_ocr_module_ephemeral');
      final installer = ChineseOcrInstaller(channel: ephemeral);
      final status = await installer.refresh();
      expect(status, OcrModuleStatus.installed);
    });

    test('refresh is a no-op when status does not change', () async {
      var calls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls++;
            return 'installed';
          });

      final installer = ChineseOcrInstaller();
      var notifications = 0;
      installer.addListener(() => notifications++);

      await installer.refresh();
      // Second refresh observes the same status and must not notify.
      await installer.refresh();
      expect(calls, 2);
      expect(notifications, 1);
    });

    test(
      'requestDownload resolves to installed on the bundled channel',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              if (call.method == 'requestDownload') return 'installed';
              return null;
            });

        final installer = ChineseOcrInstaller();
        final status = await installer.requestDownload();
        expect(status, OcrModuleStatus.installed);
        expect(installer.isBusy, isFalse);
      },
    );
  });
}
