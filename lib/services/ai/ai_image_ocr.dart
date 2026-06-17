import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;

import 'package:nousmind/services/ai/ai_exceptions.dart';

/// Hard cap on the longest edge of an image handed to ML Kit, in pixels.
/// Larger screenshots are downscaled before OCR so the recognizer's
/// memory usage stays bounded on Android.
const int _maxImageEdgePx = 2048;

/// Runs on-device OCR on [imagePath] and returns the recognized text.
/// When [useChinese] is true the Chinese script is attempted first;
/// on any failure (model not downloaded, native `NoClassDefFoundError`
/// on a stripped-down Play Services build, or simply a script that
/// returns empty text) the analyzer transparently retries with the
/// Latin script so the user is never stranded by a missing model.
///
/// The image is pre-resized so the longest edge is at most
/// [_maxImageEdgePx] to keep ML Kit's memory usage bounded on large
/// screenshots.
Future<String> runOcr({
  required String imagePath,
  required bool useChinese,
}) async {
  if (useChinese) {
    try {
      return await _runOcrWithScript(imagePath, TextRecognitionScript.chinese);
    } on AiOcrException catch (error, stackTrace) {
      developer.log(
        'Chinese OCR failed, falling back to Latin',
        error: error,
        stackTrace: stackTrace,
      );
      // Fall through to Latin below.
    }
  }
  return _runOcrWithScript(imagePath, TextRecognitionScript.latin);
}

/// Runs OCR with an explicit [script]. The Chinese script can throw
/// `NoClassDefFoundError` (or any other native failure) when the
/// model has not been downloaded, so the caller in [runOcr] wraps
/// the Chinese call in a try/catch and falls back to Latin.
Future<String> _runOcrWithScript(
  String imagePath,
  TextRecognitionScript script,
) async {
  TextRecognizer? recognizer;
  try {
    recognizer = TextRecognizer(script: script);
    final processedPath = await _shrinkImage(imagePath);
    final input = InputImage.fromFilePath(processedPath);
    final recognized = await recognizer.processImage(input);
    return recognized.text;
  } catch (error, stackTrace) {
    developer.log(
      'OCR failed for $imagePath '
      '(script=${script.name}, errorType=${error.runtimeType})',
      error: error,
      stackTrace: stackTrace,
    );
    throw AiOcrException('截图识别失败,请尝试更清晰的图片');
  } finally {
    await recognizer?.close();
  }
}

/// Returns a path to a resized copy of [sourcePath] when the source is
/// larger than [_maxImageEdgePx] on its longest edge. Returns the
/// original path otherwise. The temporary file is written to the
/// system temp directory and is intentionally not cleaned up here —
/// ML Kit reads it synchronously and the OS reclaims temp space.
Future<String> _shrinkImage(String sourcePath) async {
  final file = File(sourcePath);
  if (!await file.exists()) return sourcePath;
  try {
    final bytes = await file.readAsBytes();
    final image = img.decodeImage(bytes);
    if (image == null) return sourcePath;
    final w = image.width;
    final h = image.height;
    final longest = w > h ? w : h;
    if (longest <= _maxImageEdgePx) {
      image.clear();
      return sourcePath;
    }
    final scale = _maxImageEdgePx / longest;
    final resized = img.copyResize(
      image,
      width: (w * scale).round(),
      height: (h * scale).round(),
      interpolation: img.Interpolation.linear,
    );
    final resizedBytes = img.encodeJpg(resized, quality: 85);
    image.clear();
    resized.clear();
    final tmp = File(
      '${Directory.systemTemp.path}/ai_ocr_${_generateId()}.jpg',
    );
    await tmp.writeAsBytes(resizedBytes, flush: true);
    return tmp.path;
  } catch (error, stackTrace) {
    developer.log(
      'Image resize failed for $sourcePath, using original',
      error: error,
      stackTrace: stackTrace,
    );
    return sourcePath;
  }
}

String _generateId() {
  return '${DateTime.now().microsecondsSinceEpoch}_'
      '${Random.secure().nextInt(1 << 32).toRadixString(16)}';
}
