import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:http/http.dart' as http;

import 'package:nousmind/models/reminder_draft.dart';
import 'package:nousmind/services/ai/ai_exceptions.dart';
import 'package:nousmind/services/ai/ai_image_ocr.dart';
import 'package:nousmind/services/ai/ai_prompts.dart' as prompts;
import 'package:nousmind/services/ai/ai_response_parser.dart';

// Re-exports preserve the public surface that existed before the
// refactor — callers (test file, view models, widgets) can keep
// importing everything from this single entry point.
export 'package:nousmind/services/ai/ai_exceptions.dart';
export 'package:nousmind/services/ai/ai_response_parser.dart'
    show parseAssistantJson;

/// Abstract backend for the AI assistant. Implementations take free-form
/// text and/or a local image path and return a list of [ReminderDraft]
/// candidates the user can review.
///
/// The API key and the current `now` (used as "today" in the prompt) are
/// supplied per-call so the analyzer itself stays stateless and can be
/// re-used across settings changes.
abstract class AiAnalyzer {
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

  /// Adjusts an in-progress reminder by filling in / refining its title,
  /// description, and suggested time based on OCR text from an attached
  /// image and whatever the user has already typed.
  ///
  /// Returns a single-element list containing the adjusted draft, or an
  /// empty list when the model has nothing to contribute.
  ///
  /// [systemPromptTemplate] overrides the built-in adjust prompt; pass
  /// `null` to use the default
  /// (see [DeepSeekAnalyzer.defaultAdjustPromptTemplate]).
  ///
  /// [availableTags] is the set of [Tag]s the user has configured.
  /// When non-empty, the prompt's `{{tags}}` placeholder is
  /// substituted with a bullet list of ids/names, and the model is
  /// expected to pick a `tag_id` for every draft it emits. The
  /// parser validates the returned id against this set; hallucinated
  /// ids are silently dropped. Pass an empty list to skip the tag
  /// step entirely (the prompt keeps the `{{tags}}` placeholder
  /// intact and the model has no tag list to choose from).
  Future<List<ReminderDraft>> adjustReminder({
    required String? title,
    required String? description,
    String? imagePath,
    required String apiKey,
    required String timezone,
    required DateTime now,
    String? systemPromptTemplate,
    List<({String id, String name})> availableTags =
        const <({String id, String name})>[],
  });

  /// Runs batch analysis on a list of selected inspirations.
  Future<Map<String, dynamic>> analyzeInspirations({
    required List<String> texts,
    required List<String> ocrTexts,
    required List<DateTime> dates,
    required List<String> enabledFunctions,
    required String apiKey,
    required String timezone,
    required DateTime now,
    String? systemPromptTemplate,
    List<({String id, String name})> availableTags =
        const <({String id, String name})>[],
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

  /// Hard cap on the combined user-side input length (title + description
  /// + OCR text, in characters). Anything beyond this gets truncated
  /// proportionally so a single call cannot inflate token usage by
  /// accident. 4000 chars ≈ 1k–1.3k tokens depending on language mix,
  /// which keeps the input comfortably under the 1024-output budget.
  static const int _maxUserInputChars = 4000;

  /// Hard cap on a user-supplied system prompt length. Defensive — the
  /// settings page already caps at 2000 chars, but a hand-edited
  /// sqflite row should not be able to break the request either.
  static const int _maxCustomPromptChars = 4000;

  /// Default system prompt for [analyzeError]. Re-exported as a
  /// top-level constant in `ai_prompts.dart`; the value here is the
  /// alias so callers using `DeepSeekAnalyzer.defaultErrorAnalysisPrompt`
  /// keep working.
  static const String defaultErrorAnalysisPrompt =
      prompts.defaultErrorAnalysisPrompt;

  /// Default system-prompt template for [adjustReminder]. See
  /// `ai_prompts.dart` for the canonical definition.
  static const String defaultAdjustPromptTemplate =
      prompts.defaultAdjustPromptTemplate;

  /// Default system-prompt template for inspiration analysis.
  static const String defaultInspirationAnalysisPromptTemplate =
      prompts.defaultInspirationAnalysisPromptTemplate;

  /// Substitutes the `{{...}}` placeholders inside [template].
  /// Delegates to [prompts.renderAssistantPrompt] so callers can pick
  /// either the namespaced or the top-level form. Pass [tagsBlock]
  /// to fill the `{{tags}}` placeholder.
  static String renderAssistantPrompt({
    required String template,
    required String timezone,
    required DateTime now,
    String? tagsBlock,
  }) {
    return prompts.renderAssistantPrompt(
      template: template,
      timezone: timezone,
      now: now,
      tagsBlock: tagsBlock,
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

  /// Composes the user-side message for [adjustReminder] from the
  /// labeled pieces, capping the total length at
  /// [_maxUserInputChars]. Each piece is sanitized (control characters
  /// stripped) and, when the combined input exceeds the cap, the
  /// pieces are scaled down proportionally with the last piece (OCR
  /// text) absorbing the remainder first. A `developer.log` line is
  /// emitted whenever truncation happens so the user can correlate
  /// the slice with the device log.
  String _composeUserContent(List<(String label, String body)> pieces) {
    if (pieces.isEmpty) return '(无内容)';

    final buffer = StringBuffer();
    final sanitized = pieces.map((p) {
      final cleaned = _sanitizeForPrompt(p.$2);
      return (label: p.$1, body: cleaned, length: cleaned.length);
    }).toList();

    final totalLength = sanitized.fold<int>(0, (sum, p) => sum + p.length);

    if (totalLength <= _maxUserInputChars) {
      for (final p in sanitized) {
        buffer.writeln('${p.label}:');
        buffer.writeln(p.body);
        buffer.writeln();
      }
      return buffer.toString();
    }

    // Scale proportionally so longer pieces absorb less per-character
    // budget than shorter ones — the title is usually short and the
    // OCR text is usually long, so trimming the OCR keeps the user's
    // typed text intact where possible.
    final budget = _maxUserInputChars;
    var remaining = budget;
    final scaled = <(String, String, int)>[];
    for (var i = 0; i < sanitized.length; i++) {
      final p = sanitized[i];
      final isLast = i == sanitized.length - 1;
      final share = isLast ? remaining : (p.length * budget ~/ totalLength);
      final kept = share.clamp(0, p.length);
      scaled.add((p.label, p.body.substring(0, kept), kept));
      remaining -= kept;
    }
    developer.log(
      'ai user input truncated: '
      'origChars=$totalLength, keptChars=$budget',
      name: 'DeepSeekAnalyzer',
    );
    for (final p in scaled) {
      buffer.writeln('${p.$1}:');
      buffer.writeln(p.$2);
      buffer.writeln();
    }
    return buffer.toString();
  }

  /// Picks the system prompt that should actually go on the wire:
  /// either the user-supplied override (sanitized + capped +
  /// anti-extraction appendix appended) or the built-in default.
  String _resolveSystemPrompt({
    String? provided,
    required String fallback,
    String? timezone,
    DateTime? now,
    String? tagsBlock,
  }) {
    if (provided == null || provided.trim().isEmpty) {
      if (timezone != null && now != null) {
        return prompts.renderAssistantPrompt(
          template: fallback,
          timezone: timezone,
          now: now,
          tagsBlock: tagsBlock,
        );
      }
      return fallback;
    }
    final trimmed = provided.trim();
    if (trimmed.length > _maxCustomPromptChars) {
      developer.log(
        'ai custom prompt truncated: '
        'origChars=${trimmed.length}, max=$_maxCustomPromptChars',
        name: 'DeepSeekAnalyzer',
      );
    }
    final capped = trimmed.length > _maxCustomPromptChars
        ? '${trimmed.substring(0, _maxCustomPromptChars)}\n…(已截断)'
        : trimmed;
    final rendered = (timezone != null && now != null)
        ? prompts.renderAssistantPrompt(
            template: capped,
            timezone: timezone,
            now: now,
            tagsBlock: tagsBlock,
          )
        : capped;
    return '$rendered\n\n${prompts.antiExtractionAppendix}';
  }

  /// Strips ASCII control characters (excluding `\n` and `\t`) and
  /// collapses runs of three or more blank lines into a single one.
  /// Cheap insurance against prompt-injection payloads that try to
  /// hide an instruction inside whitespace padding.
  static String _sanitizeForPrompt(String input) {
    final stripped = input.replaceAll(RegExp(r'[\x00-\x08\x0B-\x1F\x7F]'), '');
    return stripped.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }

  /// Analyses an error-log entry (timestamp + source + message + stack
  /// trace) and returns a plain-text Chinese diagnosis. The model
  /// temperature is held low (0.4) because reproducible diagnoses are
  /// more useful than creative prose for stack traces.
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
    final cleanedText = _sanitizeForPrompt(text);
    if (cleanedText.isEmpty) {
      throw AiParseException('日志为空,无法分析');
    }
    final effectivePrompt = _resolveSystemPrompt(
      provided: systemPrompt,
      fallback: defaultErrorAnalysisPrompt,
    );

    final body = <String, dynamic>{
      'model': _model,
      'messages': <Map<String, String>>[
        <String, String>{'role': 'system', 'content': effectivePrompt},
        <String, String>{'role': 'user', 'content': cleanedText},
      ],
      'temperature': 0.4,
      'max_tokens': 1024,
    };

    final raw = await _chatCompletion(trimmedKey: trimmedKey, body: body);
    return _stripCodeFences(raw).trim();
  }

  @override
  Future<List<ReminderDraft>> adjustReminder({
    required String? title,
    required String? description,
    String? imagePath,
    required String apiKey,
    required String timezone,
    required DateTime now,
    String? systemPromptTemplate,
    List<({String id, String name})> availableTags =
        const <({String id, String name})>[],
  }) async {
    final trimmedKey = apiKey.trim();
    if (trimmedKey.isEmpty) {
      throw AiAuthException('API 密钥无效,请到 设置 → AI 助手 检查');
    }

    final ocrText = imagePath != null
        ? await runOcr(imagePath: imagePath, useChinese: _useChinese)
        : '';

    final pieces = <(String, String)>[];
    if (title != null && title.trim().isNotEmpty) {
      pieces.add(('用户已填标题', title.trim()));
    }
    if (description != null && description.trim().isNotEmpty) {
      pieces.add(('用户已填描述', description.trim()));
    }
    if (ocrText.isNotEmpty) {
      pieces.add(('截图 OCR 文本(可能含错字)', ocrText));
    }
    final userContent = _composeUserContent(pieces);

    final tagsBlock = availableTags.isEmpty
        ? null
        : prompts.renderTagsBlock(availableTags);
    final effectivePrompt = _resolveSystemPrompt(
      provided: systemPromptTemplate,
      fallback: defaultAdjustPromptTemplate,
      timezone: timezone,
      now: now,
      tagsBlock: tagsBlock,
    );

    final body = <String, dynamic>{
      'model': _model,
      'messages': <Map<String, String>>[
        <String, String>{'role': 'system', 'content': effectivePrompt},
        <String, String>{'role': 'user', 'content': userContent},
      ],
      'response_format': <String, String>{'type': 'json_object'},
      'thinking': <String, String>{'type': 'disabled'},
      'temperature': 0.2,
      'max_tokens': 1024,
    };

    final content = await _chatCompletion(trimmedKey: trimmedKey, body: body);
    return parseAssistantJson(
      content,
      validTagIds: availableTags.isEmpty
          ? null
          : availableTags.map((t) => t.id).toSet(),
    );
  }

  @override
  Future<Map<String, dynamic>> analyzeInspirations({
    required List<String> texts,
    required List<String> ocrTexts,
    required List<DateTime> dates,
    required List<String> enabledFunctions,
    required String apiKey,
    required String timezone,
    required DateTime now,
    String? systemPromptTemplate,
    List<({String id, String name})> availableTags =
        const <({String id, String name})>[],
  }) async {
    final trimmedKey = apiKey.trim();
    if (trimmedKey.isEmpty) {
      throw AiAuthException('API 密钥无效,请到 设置 → AI 助手 检查');
    }

    final buffer = StringBuffer();
    for (var i = 0; i < texts.length; i++) {
      buffer.writeln(
        '- [${dates[i].toIso8601String().substring(0, 10)}] ${texts[i]}',
      );
      if (ocrTexts[i].isNotEmpty) {
        buffer.writeln('  (图片OCR文本: ${ocrTexts[i]})');
      }
    }
    final userContent =
        '【待分析灵感】\n${buffer.toString()}\n\n【分析要求】\n只需分析以下要求的维度,其他维度返回空/空数组:\n${enabledFunctions.map((f) => '- $f').join('\n')}';

    final tagsBlock = availableTags.isEmpty
        ? null
        : prompts.renderTagsBlock(availableTags);
    final effectivePrompt = _resolveSystemPrompt(
      provided: systemPromptTemplate,
      fallback: prompts.defaultInspirationAnalysisPromptTemplate,
      timezone: timezone,
      now: now,
      tagsBlock: tagsBlock,
    );

    final body = <String, dynamic>{
      'model': _model,
      'messages': <Map<String, String>>[
        <String, String>{'role': 'system', 'content': effectivePrompt},
        <String, String>{'role': 'user', 'content': userContent},
      ],
      'response_format': <String, String>{'type': 'json_object'},
      'thinking': <String, String>{'type': 'disabled'},
      'temperature': 0.3,
      'max_tokens': 1536,
    };

    final content = await _chatCompletion(trimmedKey: trimmedKey, body: body);
    try {
      return jsonDecode(content) as Map<String, dynamic>;
    } catch (e) {
      throw AiParseException('AI 返回的 JSON 格式无法解析');
    }
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
}

/// Defensive Markdown-fence stripper used by [DeepSeekAnalyzer.analyzeError].
/// Identical logic to the private helper in `ai_response_parser.dart`; kept
/// here because `analyzeError` returns plain text and must not surface
/// stray fences even when the model "helpfully" wraps a non-code reply.
String _stripCodeFences(String input) {
  if (!input.startsWith('```')) return input;
  final lines = input.split('\n');
  if (lines.length < 2) return input;
  final first = lines.first.trim();
  if (!first.startsWith('```')) return input;
  final rest = lines.sublist(1);
  if (rest.isNotEmpty && rest.last.trim() == '```') {
    rest.removeLast();
  }
  return rest.join('\n').trim();
}
