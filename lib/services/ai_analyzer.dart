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
  /// Extracts reminder candidates from [text] / [imagePath].
  ///
  /// [systemPromptTemplate] lets the caller override the built-in system
  /// prompt. The template may contain the placeholders `{{now}}`,
  /// `{{timezone}}`, `{{offset}}`, `{{weekday}}`, `{{tomorrow}}` which
  /// are substituted at call time. When `null`, the built-in default
  /// (see [DeepSeekAnalyzer.defaultAssistantPromptTemplate]) is used.
  Future<List<ReminderDraft>> analyze({
    String? text,
    String? imagePath,
    required String apiKey,
    required String timezone,
    required DateTime now,
    String? systemPromptTemplate,
  });

  /// Rewrites [text] into a more readable, well-structured form while
  /// preserving the original meaning. Used by the reminder editor's
  /// "AI 一键润色" affordance. Implementations may be lossy on edge
  /// cases (e.g. server outage); the editor surfaces failures through
  /// the same [AiAnalysisException] hierarchy as [analyze] so the UX
  /// stays consistent.
  ///
  /// [systemPrompt] overrides the built-in polish prompt; pass `null`
  /// to use the default (see [DeepSeekAnalyzer.defaultPolishPrompt]).
  Future<String> polishText({
    required String text,
    required String apiKey,
    String? systemPrompt,
  });

  /// Analyses a free-form error log entry (timestamp + source + message
  /// + stack trace) and returns a plain-text Chinese diagnosis. The
  /// settings page exposes the "错误日志 → AI 分析" action that drives
  /// this call. [systemPrompt] overrides the built-in prompt; pass
  /// `null` to use [DeepSeekAnalyzer.defaultErrorAnalysisPrompt].
  Future<String> analyzeError({
    required String text,
    required String apiKey,
    String? systemPrompt,
  });

  /// Releases any owned resources (HTTP clients, native recognizers).
  void dispose() {}

  /// Wires the analyzer to a live source of the user's
  /// `chineseOcrEnabled` preference. The default implementation is a
  /// no-op so analyzers that ignore the flag do not have to override
  /// it; the [DeepSeekAnalyzer] uses this to keep its OCR script
  /// choice in sync with [AppSettings] without rebuilding the
  /// singleton.
  void setChineseOcrProvider(bool Function() provider) {}
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
  DeepSeekAnalyzer({http.Client? client, bool chineseOcrEnabled = false})
    : _client = client ?? http.Client(),
      _seedChineseOcr = chineseOcrEnabled;

  final http.Client _client;
  bool Function()? _chineseOcrProvider;
  static const String _endpoint =
      'https://api.deepseek.com/v1/chat/completions';
  static const String _model = 'deepseek-v4-flash';
  static const Duration _timeout = Duration(seconds: 30);
  static const int _maxImageEdgePx = 2048;

  /// Default system prompt for [polishText]. Surfaced publicly so the
  /// settings page can pre-fill its editor with the built-in value and
  /// reset to it when the user clears the field.
  static const String defaultPolishPrompt = '''
你是中文写作润色助手。直接对用户文本做以下优化:
1. 修正错别字、标点、口语化表达,使之更可读
2. 在保留原意的前提下,适当重组句式或使用列表/分段,提升条理
3. 可以轻微润色措辞,但不改变事实、不添加信息、不替用户决策

严禁输出引号、说明、提示语、Markdown 围栏。只返回润色后的纯文本。
''';

  /// Default system prompt for [analyzeError]. Output is plain Chinese
  /// text (no Markdown fences); the user-facing sheet renders it as
  /// selectable text.
  static const String defaultErrorAnalysisPrompt = '''
你是一位 Flutter / Dart 资深工程师,负责给应用日志里出现的错误做诊断。
读完用户提供的错误信息和堆栈后,用简体中文按下面结构回答,小标题加粗:
1. **可能原因**:1-3 条最有可能的根因,按可能性排序
2. **排查建议**:可立即执行的下一步动作(检查哪一行代码、加什么日志、查什么配置)
3. **类似情况**(可选):常见误判、相关 issue 关键词或官方文档锚点

只输出纯文本,不要输出 Markdown 代码围栏。回答应当聚焦、可操作,避免空话。
''';

  /// Default system-prompt template for [analyze]. Contains template
  /// placeholders that are substituted by [renderAssistantPrompt] at
  /// call time:
  ///
  /// - `{{now}}`       — wall-clock "YYYY-MM-DD HH:mm"
  /// - `{{timezone}}`  — IANA zone, e.g. "Asia/Shanghai"
  /// - `{{offset}}`    — UTC offset suffix, e.g. "+08:00"
  /// - `{{weekday}}`   — 中文星期, e.g. "星期一"
  /// - `{{tomorrow}}`  — "YYYY-MM-DD" for tomorrow
  ///
  /// Users editing this template via the settings page may remove any
  /// placeholder; the renderer leaves unknown tokens intact.
  static const String defaultAssistantPromptTemplate = '''
你是日程助理，从用户文本中提取提醒事项。
输入可能包含 OCR 文字（含少量错字），请理解语义后提取。

【时间规则】
所有时间都是 {{timezone}} 时区的本地时间，即墙上钟表的读数，不是 UTC。
格式：ISO 8601，末尾固定携带偏移 {{offset}}。
"2点"就是该日期的 02:00 / 14:00，"3点"就是 03:00 / 15:00，钟表显示几点就写几点。

示例：
"明天下午2点去上海" → {"reminders":[{"title":"去上海","suggested_time":"{{tomorrow}}T14:00:00{{offset}}","reason":"明天下午2点"}]}
"明天下午3点开会" → {"reminders":[{"title":"开会","suggested_time":"{{tomorrow}}T15:00:00{{offset}}","reason":"明天下午3点"}]}

当前时间：{{now}} ({{weekday}})
时区：{{timezone}}

【输出】只输出纯 JSON，勿用 Markdown 代码块。
{"reminders":[{"title":"简短标题","suggested_time":"ISO8601+偏移","reason":"简短依据"}]}

【规则】
1. 只提取未来、明确的提醒；无则返回 {"reminders": []}
2. "今天X点"若已早于当前时刻则改为"明天X点"；缺少年份默认今年
3. 标题简洁（≤30字），如"买菜"、"回电话给张三"
''';

  /// Substitutes the `{{now}} {{timezone}} {{offset}} {{weekday}}
  /// {{tomorrow}}` placeholders inside [template] with the current
  /// runtime values. Unknown tokens are left intact so user-edited
  /// templates degrade gracefully.
  static String renderAssistantPrompt({
    required String template,
    required String timezone,
    required DateTime now,
  }) {
    return template
        .replaceAll('{{now}}', _formatDateTime(now))
        .replaceAll('{{timezone}}', timezone)
        .replaceAll('{{offset}}', _formatOffset(now))
        .replaceAll('{{weekday}}', _weekdayLabel(now.weekday))
        .replaceAll(
          '{{tomorrow}}',
          _formatDate(now.add(const Duration(days: 1))),
        );
  }

  /// Wires the analyzer to read the user's
  /// [AppSettings.chineseOcrEnabled] preference on every [analyze]
  /// call. The provider is invoked at call time, not attach time, so
  /// toggling the switch in settings takes effect on the very next
  /// assistant invocation. The constructor's [chineseOcrEnabled]
  /// flag is honored as the initial value when the provider is
  /// absent (e.g. unit tests).
  @override
  void setChineseOcrProvider(bool Function() provider) {
    _chineseOcrProvider = provider;
  }

  /// Convenience setter for tests and the initial seed when no
  /// provider is wired. Production code uses [setChineseOcrProvider]
  /// so live settings changes take effect without rebuilding the
  /// analyzer.
  set chineseOcrEnabled(bool value) {
    _chineseOcrProvider = null;
    _seedChineseOcr = value;
  }

  bool _seedChineseOcr = false;
  bool get _useChinese => _chineseOcrProvider?.call() ?? _seedChineseOcr;

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
    String? systemPromptTemplate,
  }) async {
    final trimmedKey = apiKey.trim();
    if (trimmedKey.isEmpty) {
      throw AiAuthException('API 密钥无效,请到 设置 → AI 助手 检查');
    }

    final ocrText = imagePath != null ? await _runOcr(imagePath) : '';
    final combined = _composeUserContent(userText: text, ocrText: ocrText);
    final systemContent = renderAssistantPrompt(
      template: systemPromptTemplate ?? defaultAssistantPromptTemplate,
      timezone: timezone,
      now: now,
    );

    final body = <String, dynamic>{
      'model': _model,
      'messages': <Map<String, String>>[
        <String, String>{'role': 'system', 'content': systemContent},
        <String, String>{'role': 'user', 'content': combined},
      ],
      'response_format': <String, String>{'type': 'json_object'},
      'thinking': <String, String>{'type': 'disabled'},
      'temperature': 0.2,
      'max_tokens': 1024,
    };

    final content = await _chatCompletion(trimmedKey: trimmedKey, body: body);
    return parseAssistantJson(content);
  }

  /// Polish a free-form Chinese text. The result is returned verbatim
  /// (the model is asked to return plain text without Markdown fences or
  /// explanations), trimmed of leading/trailing whitespace. Errors
  /// mirror the [analyze] flow so the editor can render SnackBar
  /// messages with the same `AiAnalysisException` mapping.
  @override
  Future<String> polishText({
    required String text,
    required String apiKey,
    String? systemPrompt,
  }) async {
    final trimmedKey = apiKey.trim();
    if (trimmedKey.isEmpty) {
      throw AiAuthException('API 密钥无效,请到 设置 → AI 助手 检查');
    }
    if (text.trim().isEmpty) {
      throw AiParseException('描述为空,无需润色');
    }

    final body = <String, dynamic>{
      'model': _model,
      'messages': <Map<String, String>>[
        <String, String>{
          'role': 'system',
          'content': systemPrompt ?? defaultPolishPrompt,
        },
        <String, String>{'role': 'user', 'content': text},
      ],
      // Plain text response — explicitly NOT json_object, otherwise the
      // model will wrap the answer in `{"reply": "..."}`.
      'temperature': 0.7,
      'max_tokens': 1024,
    };

    final raw = await _chatCompletion(trimmedKey: trimmedKey, body: body);
    return _stripCodeFences(raw).trim();
  }

  /// Analyses an error-log entry (timestamp + source + message + stack
  /// trace) and returns a plain-text Chinese diagnosis. Reuses the same
  /// HTTP / exception machinery as [polishText] so the calling sheet
  /// can map failures consistently. The model temperature is held low
  /// (0.4) because reproducible diagnoses are more useful than creative
  /// prose for stack traces.
  @override
  Future<String> analyzeError({
    required String text,
    required String apiKey,
    String? systemPrompt,
  }) async {
    final trimmedKey = apiKey.trim();
    if (trimmedKey.isEmpty) {
      throw AiAuthException('API 密钥无效,请到 设置 → AI 助手 检查');
    }
    if (text.trim().isEmpty) {
      throw AiParseException('日志为空,无法分析');
    }

    final body = <String, dynamic>{
      'model': _model,
      'messages': <Map<String, String>>[
        <String, String>{
          'role': 'system',
          'content': systemPrompt ?? defaultErrorAnalysisPrompt,
        },
        <String, String>{'role': 'user', 'content': text},
      ],
      'temperature': 0.4,
      'max_tokens': 1024,
    };

    final raw = await _chatCompletion(trimmedKey: trimmedKey, body: body);
    return _stripCodeFences(raw).trim();
  }

  /// Sends a chat-completions POST and returns the
  /// `choices[0].message.content` string. Maps network / status errors
  /// onto the [AiAnalysisException] hierarchy so every caller surfaces
  /// the same Chinese SnackBar copy regardless of which endpoint it
  /// hits.
  Future<String> _chatCompletion({
    required String trimmedKey,
    required Map<String, dynamic> body,
  }) async {
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
      return raw;
    } on FormatException {
      throw AiParseException('AI 返回格式无法解析');
    }
  }

  /// Runs on-device OCR on [imagePath] and returns the recognized
  /// text. When [chineseOcrEnabled] is true the Chinese script is
  /// attempted first; on any failure (model not downloaded, native
  /// `NoClassDefFoundError` on a stripped-down Play Services build,
  /// or simply a script that returns empty text) the analyzer
  /// transparently retries with the Latin script so the user is
  /// never stranded by a missing model.
  /// The image is pre-resized so the longest edge is at most
  /// [_maxImageEdgePx] to keep ML Kit's memory usage bounded on large
  /// screenshots.
  Future<String> _runOcr(String imagePath) async {
    if (_useChinese) {
      try {
        return await _runOcrWithScript(
          imagePath,
          TextRecognitionScript.chinese,
        );
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
  /// model has not been downloaded, so the caller in [_runOcr] wraps
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
        'OCR failed for $imagePath (script=${script.name})',
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
    if (!_hasExplicitOffset(timeRaw)) {
      throw AiParseException(
        '某条提醒的时间必须包含显式的时区偏移(如 +08:00 或 Z),'
        '不要省略偏移',
      );
    }
    // Always normalize to the device's local clock. [DateTime.tryParse]
    // returns a UTC-typed [DateTime] for any string carrying an offset,
    // which the rest of the app would otherwise render as the UTC wall
    // time — on a Asia/Shanghai device that turned "明天早上 9 点" into
    // a reminder displayed as 01:00. Converting here keeps the result
    // consistent with every other code path (editor, list, notification
    // scheduler) that assumes [Reminder.reminderTime] is local.
    final localTime = parsedTime.toLocal();
    final reasonRaw = map['reason'];
    final reason = reasonRaw is String && reasonRaw.trim().isNotEmpty
        ? reasonRaw.trim()
        : null;
    drafts.add(
      ReminderDraft(
        id: _generateId(),
        title: title.trim(),
        suggestedTime: localTime,
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

/// Returns true when [iso] carries an explicit timezone designator —
/// either `Z` or a `±HH:MM` suffix. Bare local-time strings like
/// `2026-06-14T14:00:00` are rejected because they are ambiguous
/// across timezones. Accepting `Z` / `+00:00` here (previously
/// rejected) keeps the door open for users whose device is genuinely
/// in UTC; the parser still anchors the moment via
/// [DateTime.tryParse] and then normalizes to the device's local
/// clock before handing the value to the UI.
bool _hasExplicitOffset(String iso) {
  if (iso.endsWith('Z')) return true;
  return RegExp(r'[+-]\d{2}:\d{2}$').hasMatch(iso);
}

String _generateId() {
  return '${DateTime.now().microsecondsSinceEpoch}_'
      '${Random.secure().nextInt(1 << 32).toRadixString(16)}';
}
