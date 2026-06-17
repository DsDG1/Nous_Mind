import 'dart:convert';
import 'dart:math';

import 'package:nousmind/models/reminder_draft.dart';
import 'package:nousmind/models/tag.dart';
import 'package:nousmind/services/ai/ai_exceptions.dart';

/// Pure parser shared by [DeepSeekAnalyzer] and the unit tests. Strips
/// optional Markdown code fences before decoding and validates the
/// expected schema. Throws [AiParseException] for every malformed
/// input — the caller decides whether to surface the message
/// verbatim or wrap it in a recovery flow.
///
/// [validTagIds] (when non-null) is the allow-list used to validate
/// the per-entry `tag_id` field. An incoming id not in the set is
/// silently dropped (`tagId = null` on the resulting draft) — the
/// model can hallucinate ids for tags the user does not have, and
/// the editor would render an empty chip for those, so dropping is
/// the safer default. Pass `null` to accept any string.
List<ReminderDraft> parseAssistantJson(String raw, {Set<String>? validTagIds}) {
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
    final descRaw = map['description'];
    final description = descRaw is String && descRaw.trim().isNotEmpty
        ? descRaw.trim()
        : null;
    final tagIdRaw = map['tag_id'];
    String? tagId;
    if (tagIdRaw is String && tagIdRaw.trim().isNotEmpty) {
      final candidate = tagIdRaw.trim();
      if (validTagIds == null ||
          validTagIds.contains(candidate) ||
          candidate == kCompletedTagId) {
        tagId = candidate;
      }
      // else: hallucinated id — drop silently.
    }
    drafts.add(
      ReminderDraft(
        id: _generateId(),
        title: title.trim(),
        suggestedTime: localTime,
        reason: reason,
        description: description,
        tagId: tagId,
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
