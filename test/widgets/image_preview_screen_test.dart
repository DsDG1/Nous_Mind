// Smoke tests for [ImagePreviewScreen].
//
// The screen is pushed via the root navigator above the tab bar and is
// expected to:
//   * render the photo when given a readable file path,
//   * fall back to a "missing image" placeholder when the path is bad,
//   * close itself on a single tap.
//
// Note: PhotoView wraps the loading state in an indefinite spinner,
// so `pumpAndSettle` would time out. The tests below use fixed-duration
// `pump` calls instead.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_view/photo_view.dart';

import 'package:nousmind/widgets/image_preview_screen.dart';

// Smallest possible valid PNG: 1×1 transparent pixel.
final Uint8List _transparentPng = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // signature
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, // IHDR length + type
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, // 1×1
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, // bit depth, CRC
  0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, // IDAT length + type
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, // zlib data
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, // CRC
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, // IEND length + type
  0x42, 0x60, 0x82, // CRC
]);

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('flutter_image_preview_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<void> pumpForImageLoad(WidgetTester tester) async {
    // FileImage resolves on a microtask + one frame; pump enough frames
    // for the stream to fire without waiting on the indefinite spinner.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  testWidgets('renders the PhotoView when given a valid image file', (
    tester,
  ) async {
    final file = File('${tempDir.path}/valid.png')
      ..writeAsBytesSync(_transparentPng);

    await tester.pumpWidget(
      MaterialApp(
        home: ImagePreviewScreen(imagePath: file.path, heroTag: 'test-hero'),
      ),
    );
    await pumpForImageLoad(tester);

    expect(find.byType(ImagePreviewScreen), findsOneWidget);
    expect(find.byType(PhotoView), findsOneWidget);
  });

  testWidgets('renders missing-image placeholder for an unreadable path', (
    tester,
  ) async {
    // Path inside tempDir that does not exist; FileImage will fail.
    final missingPath = '${tempDir.path}/does_not_exist.jpg';

    await tester.pumpWidget(
      MaterialApp(
        home: ImagePreviewScreen(imagePath: missingPath, heroTag: 'test-hero'),
      ),
    );
    // FileImage resolves through the dart:ui Image pipeline which
    // requires real async file I/O; let tester.runAsync drive it
    // so the error stream fires and the errorBuilder swaps in the
    // placeholder.
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();

    expect(find.text('图片文件已被删除'), findsOneWidget);
    expect(find.text('关闭'), findsOneWidget);
    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
  });

  testWidgets('single tap pops the navigator', (tester) async {
    final file = File('${tempDir.path}/valid.png')
      ..writeAsBytesSync(_transparentPng);

    var popped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ImagePreviewScreen(
                        imagePath: file.path,
                        heroTag: 'test-hero',
                      ),
                    ),
                  );
                  popped = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await pumpForImageLoad(tester);
    expect(popped, isFalse, reason: 'should still be on preview screen');

    await tester.tap(find.byType(ImagePreviewScreen));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(popped, isTrue, reason: 'tap should pop back to root');
  });
}
