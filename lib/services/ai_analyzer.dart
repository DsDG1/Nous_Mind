import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import '../models/reminder_draft.dart';

/// Abstract backend for the AI assistant. Implementations take free-form
/// text and/or a local image path and return a list of [ReminderDraft]
/// candidates the user can review.
///
/// The API key and the current `now` (used as "today" in the prompt) are
/// supplied per-call so the analyzer itself stays stateless and can be
/// re-used across settings changes.
abstract class AiAnalyzer {
  Future<List<ReminderDraft>> analyze({
    String? text,
    String? imagePath,
    required String apiKey,
    required String timezone,
    required DateTime now,
  });

  /// Releases any owned resources (HTTP clients, native recognizers).
  void dispose() {}
}

/// Sealed exception hierarchy. The UI maps each subtype to a user-facing
/// Chinese SnackBar message.
sealed class AiAnalysisException implements Exception {
  AiAnalysisException(this.message);
  final String message;
  @override
  String toString() => message;
}

class AiAuthException extends AiAnalysisException {
  AiAuthException(super.message);
}

class AiRateLimitException extends AiAnalysisException {
  AiRateLimitException(super.message);
}

class AiServerException extends AiAnalysisException {
  AiServerException(super.message);
}

class AiNetworkException extends AiAnalysisException {
  AiNetworkException(super.message);
}

class AiParseException extends AiAnalysisException {
  AiParseException(super.message);
}

class AiOcrException extends AiAnalysisException {
  AiOcrException(super.message);
}

/// DeepSeek implementation. Runs on-device Chinese OCR over any picked
/// image, concatenates the result with the user's typed text, and sends
/// the combined string to the DeepSeek chat completions endpoint with
/// JSON mode enabled. The model is `deepseek-v4-flash` (the new name;
/// `deepseek-chat` is being retired on 2026-07-24).
class DeepSeekAnalyzer implements AiAnalyzer {
  DeepSeekAnalyzer({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const String _endpoint =
      'https://api.deepseek.com/v1/chat/completions';
  static const String _model = 'deepseek-v4-flash';
  static const Duration _timeout = Duration(seconds: 30);
  static const int _maxImageEdgePx = 2048;

  @override
  void dispose() {
    _client.close();
  }

  @override
  Future<List<ReminderDraft>> analyze({
    String? text,
    String? imagePath,
    required String apiKey,
    required String timezone,
    required DateTime now,
  }) async {
    final trimmedKey = apiKey.trim();
    if (trimmedKey.isEmpty) {
      throw AiAuthException('API 密钥无效,请到 设置 → AI 助手 检查');
    }

    final ocrText = imagePath != null ? await _runOcr(imagePath) : '';
    final combined = _composeUserContent(userText: text, ocrText: ocrText);

    final body = <String, dynamic>{
      'model': _model,
      'messages': <Map<String, String>>[
        <String, String>{
          'role': 'system',
          'content': _systemPrompt(timezone: timezone, now: now),
        },
        <String, String>{'role': 'user', 'content': combined},
      ],
      'response_format': <String, String>{'type': 'json_object'},
      'thinking': <String, String>{'type': 'disabled'},
      'temperature': 0.2,
      'max_tokens': 1024,
    };

    final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse(_endpoint),
            headers: <String, String>{
              'Authorization': 'Bearer $trimmedKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw AiNetworkException('请求超时,请检查网络后重试');
    } on SocketException {
      throw AiNetworkException('网络异常,请检查连接后重试');
    } on http.ClientException {
      throw AiNetworkException('网络异常,请检查连接后重试');
    }

    final status = response.statusCode;
    if (status == 401 || status == 403) {
      throw AiAuthException('API 密钥无效,请到 设置 → AI 助手 检查');
    }
    if (status == 429) {
      throw AiRateLimitException('请求过于频繁,请稍后再试');
    }
    if (status >= 500) {
      throw AiServerException('AI 服务暂时不可用 ($status)');
    }
    if (status != 200) {
      throw AiServerException('AI 服务返回异常 ($status)');
    }

    final String content;
    try {
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final choices = decoded['choices'] as List<dynamic>?;
      if (choices == null || choices.isEmpty) {
        throw const FormatException('Missing choices');
      }
      final first = choices.first as Map<String, dynamic>;
      final message = first['message'] as Map<String, dynamic>?;
      final raw = message?['content'];
      if (raw is! String) {
        throw const FormatException('Missing content');
      }
      content = raw;
    } on FormatException {
      throw AiParseException('AI 返回格式无法解析');
    }

    return parseAssistantJson(content);
  }

  /// Runs on-device OCR on [imagePath] and returns the recognized
  /// text. Uses Latin script which is universally available (Chinese
  /// model requires Google Play Services downloadable module that may
  /// not be present on all devices and causes a NoClassDefFoundError
  /// native crash).
  /// The image is pre-resized so the longest edge is at most
  /// [_maxImageEdgePx] to keep ML Kit's memory usage bounded on large
  /// screenshots.
  Future<String> _runOcr(String imagePath) async {
    TextRecognizer? recognizer;
    try {
      recognizer = TextRecognizer();
      final processedPath = await _shrinkImage(imagePath);
      final input = InputImage.fromFilePath(processedPath);
      final recognized = await recognizer.processImage(input);
      return recognized.text;
    } catch (error, stackTrace) {
      developer.log(
        'OCR failed for $imagePath',
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

  static String _composeUserContent({
    required String? userText,
    required String ocrText,
  }) {
    final buffer = StringBuffer();
    if (userText != null && userText.trim().isNotEmpty) {
      buffer.writeln('用户输入文本:');
      buffer.writeln(userText.trim());
      buffer.writeln();
    }
    if (ocrText.isNotEmpty) {
      buffer.writeln('截图 OCR 文本(可能含错字):');
      buffer.writeln(ocrText);
      buffer.writeln();
    }
    if (buffer.isEmpty) {
      buffer.write('(无内容)');
    }
    return buffer.toString();
  }

  static String _systemPrompt({
    required String timezone,
    required DateTime now,
  }) {
    final weekday = _weekdayLabel(now.weekday);
    final offset = _formatOffset(now);
    final tomorrow = _formatDate(now.add(const Duration(days: 1)));
    return '''
你是日程助理，从用户文本中提取提醒事项。
输入可能包含 OCR 文字（含少量错字），请理解语义后提取。

【时间规则】
所有时间都是 $timezone 时区的本地时间，即墙上钟表的读数，不是 UTC。
格式：ISO 8601，末尾固定携带偏移 $offset。
"2点"就是该日期的 02:00 / 14:00，"3点"就是 03:00 / 15:00，钟表显示几点就写几点。

示例：
"明天下午2点去上海" → {"reminders":[{"title":"去上海","suggested_time":"${tomorrow}T14:00:00$offset","reason":"明天下午2点"}]}
"明天下午3点开会" → {"reminders":[{"title":"开会","suggested_time":"${tomorrow}T15:00:00$offset","reason":"明天下午3点"}]}

当前时间：${_formatDateTime(now)} ($weekday)
时区：$timezone

【输出】只输出纯 JSON，勿用 Markdown 代码块。
{"reminders":[{"title":"简短标题","suggested_time":"ISO8601+偏移","reason":"简短依据"}]}

【规则】
1. 只提取未来、明确的提醒；无则返回 {"reminders": []}
2. "今天X点"若已早于当前时刻则改为"明天X点"；缺少年份默认今年
3. 标题简洁（≤30字），如"买菜"、"回电话给张三"
''';
  }

  /// Formats as `YYYY-MM-DD` (date only, no time).
  static String _formatDate(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)}';
  }

  /// Formats the local clock as `YYYY-MM-DD HH:mm` (24h) so the model
  /// sees the same date+time the user sees on their device.
  static String _formatDateTime(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}';
  }

  /// Formats the device's current UTC offset as `+HH:MM` / `-HH:MM`,
  /// matching the suffix DeepSeek should append to every ISO 8601 time
  /// it returns. Falls back to `+00:00` only when the device itself
  /// is genuinely in UTC; in that case the prompt shows `+00:00`
  /// examples and the parser accepts them.
  static String _formatOffset(DateTime dt) {
    final Duration offset = dt.timeZoneOffset;
    final String sign = offset.isNegative ? '-' : '+';
    final Duration abs = offset.abs();
    final String h = abs.inHours.toString().padLeft(2, '0');
    final String m = (abs.inMinutes % 60).toString().padLeft(2, '0');
    return '$sign$h:$m';
  }

  static String _weekdayLabel(int weekday) {
    return switch (weekday) {
      DateTime.monday => '星期一',
      DateTime.tuesday => '星期二',
      DateTime.wednesday => '星期三',
      DateTime.thursday => '星期四',
      DateTime.friday => '星期五',
      DateTime.saturday => '星期六',
      DateTime.sunday => '星期日',
      _ => '',
    };
  }
}

/// Pure parser shared by [DeepSeekAnalyzer] and the unit tests. Strips
/// optional Markdown code fences before decoding and validates the
/// expected schema.
List<ReminderDraft> parseAssistantJson(String raw) {
  final cleaned = _stripCodeFences(raw.trim());
  final dynamic decoded;
  try {
    decoded = jsonDecode(cleaned);
  } on FormatException {
    throw AiParseException('AI 返回内容不是合法 JSON');
  }
  if (decoded is! Map<String, dynamic>) {
    throw AiParseException('AI 返回 JSON 顶层不是对象');
  }
  final dynamic remindersRaw = decoded['reminders'];
  if (remindersRaw is! List) {
    throw AiParseException('AI 返回 JSON 缺少 reminders 列表');
  }

  final drafts = <ReminderDraft>[];
  for (final entry in remindersRaw) {
    if (entry is! Map) {
      throw AiParseException('reminders 列表中存在非对象元素');
    }
    final map = entry.cast<String, dynamic>();
    final title = map['title'];
    if (title is! String || title.trim().isEmpty) {
      throw AiParseException('某条提醒缺少有效标题');
    }
    final timeRaw = map['suggested_time'];
    if (timeRaw is! String) {
      throw AiParseException('某条提醒缺少 suggested_time');
    }
    final parsedTime = DateTime.tryParse(timeRaw);
    if (parsedTime == null) {
      throw AiParseException('某条提醒的时间不是合法 ISO8601');
    }
    if (!_hasExplicitNonUtcOffset(timeRaw)) {
      throw AiParseException(
        '某条提醒的时间必须包含显式的本地时区偏移(如 +08:00),'
        '不要使用 Z 或省略偏移',
      );
    }
    final reasonRaw = map['reason'];
    final reason = reasonRaw is String && reasonRaw.trim().isNotEmpty
        ? reasonRaw.trim()
        : null;
    drafts.add(
      ReminderDraft(
        id: _generateId(),
        title: title.trim(),
        suggestedTime: parsedTime,
        reason: reason,
      ),
    );
  }
  return drafts;
}

String _stripCodeFences(String input) {
  if (!input.startsWith('```')) return input;
  final lines = input.split('\n');
  if (lines.length < 2) return input;
  final first = lines.first.trim();
  if (!first.startsWith('```')) return input;
  // Drop the first fence line and the last ``` line if present.
  final rest = lines.sublist(1);
  if (rest.isNotEmpty && rest.last.trim() == '```') {
    rest.removeLast();
  }
  return rest.join('\n').trim();
}

/// Returns true only when [iso] ends in a non-zero ±HH:MM offset.
/// Rejects UTC (`Z`), explicit `+00:00`, and bare local-time strings
/// (e.g. `2026-06-14T14:00:00`). The model is required to always emit
/// the device's local offset; silently accepting the others would
/// cause reminders to fire 8 hours early on Asia/Shanghai devices.
bool _hasExplicitNonUtcOffset(String iso) {
  final bool offsetMatch = RegExp(r'[+-]\d{2}:\d{2}$').hasMatch(iso);
  if (!offsetMatch) return false;
  return !iso.endsWith('+00:00');
}

String _generateId() {
  return '${DateTime.now().microsecondsSinceEpoch}_'
      '${Random.secure().nextInt(1 << 32).toRadixString(16)}';
}
