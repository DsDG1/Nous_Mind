import 'package:flutter/material.dart';

/// Preset seed colors the user can pick for the app's Material 3
/// [ColorScheme]. The values are the canonical [Colors] tokens so the
/// generated palette matches the user's mental model of the color name.
enum AppSeedColor {
  blue(Colors.blue),
  green(Colors.green),
  orange(Colors.orange),
  red(Colors.red),
  pink(Colors.pink),
  purple(Colors.purple);

  const AppSeedColor(this.color);

  final Color color;
}

/// A pair of [TimeOfDay] values describing a "do not disturb" window.
///
/// [start] and [end] can straddle midnight (e.g. 22:00–08:00). When they
/// are equal the window is treated as empty and never suppresses.
class QuietHoursWindow {
  const QuietHoursWindow({
    this.start = const TimeOfDay(hour: 22, minute: 0),
    this.end = const TimeOfDay(hour: 8, minute: 0),
  });

  final TimeOfDay start;
  final TimeOfDay end;

  bool get isCrossDay {
    final startMinutes = start.hour * 60 + start.minute;
    final endMinutes = end.hour * 60 + end.minute;
    return startMinutes > endMinutes;
  }

  bool contains(TimeOfDay time) {
    final startMinutes = start.hour * 60 + start.minute;
    final endMinutes = end.hour * 60 + end.minute;
    final value = time.hour * 60 + time.minute;
    if (startMinutes == endMinutes) {
      return false;
    }
    if (startMinutes < endMinutes) {
      return value >= startMinutes && value < endMinutes;
    }
    return value >= startMinutes || value < endMinutes;
  }

  /// Returns the earliest window-end strictly after [target].
  ///
  /// Falls back to "tomorrow's end" when today's end has already passed.
  DateTime pushPast(DateTime target) {
    final today = DateTime(
      target.year,
      target.month,
      target.day,
      end.hour,
      end.minute,
    );
    if (today.isAfter(target)) {
      return today;
    }
    return today.add(const Duration(days: 1));
  }

  QuietHoursWindow copyWith({TimeOfDay? start, TimeOfDay? end}) {
    return QuietHoursWindow(start: start ?? this.start, end: end ?? this.end);
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'start_minutes': start.hour * 60 + start.minute,
    'end_minutes': end.hour * 60 + end.minute,
  };

  factory QuietHoursWindow.fromJson(Map<String, dynamic> json) {
    int minutesOf(Object? value) {
      if (value is int) {
        return value;
      }
      if (value is String) {
        return int.tryParse(value) ?? 0;
      }
      return 0;
    }

    final startMinutes = minutesOf(json['start_minutes']);
    final endMinutes = minutesOf(json['end_minutes']);
    return QuietHoursWindow(
      start: TimeOfDay(hour: startMinutes ~/ 60, minute: startMinutes % 60),
      end: TimeOfDay(hour: endMinutes ~/ 60, minute: endMinutes % 60),
    );
  }
}

/// Snooze duration buckets reserved for a future "snooze 10 min" action on
/// incoming notifications. The MVP only persists the value; the action
/// itself is not yet wired up.
enum SnoozePreset { fiveMinutes, tenMinutes, fifteenMinutes }

class SnoozeDuration {
  const SnoozeDuration({this.preset = SnoozePreset.tenMinutes});

  final SnoozePreset preset;

  Duration get duration {
    return switch (preset) {
      SnoozePreset.fiveMinutes => const Duration(minutes: 5),
      SnoozePreset.tenMinutes => const Duration(minutes: 10),
      SnoozePreset.fifteenMinutes => const Duration(minutes: 15),
    };
  }

  String get label => '${duration.inMinutes} 分钟';

  SnoozeDuration copyWith({SnoozePreset? preset}) {
    return SnoozeDuration(preset: preset ?? this.preset);
  }

  Map<String, dynamic> toJson() => <String, dynamic>{'preset': preset.name};

  factory SnoozeDuration.fromJson(Map<String, dynamic> json) {
    final presetName = json['preset'] as String?;
    final preset = SnoozePreset.values.firstWhere(
      (p) => p.name == presetName,
      orElse: () => SnoozePreset.tenMinutes,
    );
    return SnoozeDuration(preset: preset);
  }
}

/// Immutable snapshot of the user's preferences. Mutations are funneled
/// through [copyWith] and round-trip through JSON for the database.
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.seedColor = AppSeedColor.blue,
    this.vibrationEnabled = true,
    this.quietHoursEnabled = false,
    this.quietHours = const QuietHoursWindow(),
    this.snoozeDuration = const SnoozeDuration(),
    this.autoDeleteAfter24h = true,
    this.aiAssistantEnabled = false,
    this.aiApiKey,
    this.chineseOcrEnabled = true,
    this.aiErrorAnalysisPrompt,
    this.aiAdjustPrompt,
    this.aiInspirationPrompt,
    this.aiDailyLimit = _defaultAiDailyLimit,
    this.aiDailyLimitEnabled = true,
    this.aiCallsToday = 0,
    this.aiCallsResetAt,
    this.aiConsentAcceptedAt,
  });

  /// Default ceiling on AI calls per local-day. The guard refuses new
  /// calls once `aiCallsToday` reaches this number; the user can lower
  /// or raise it from the AI settings page.
  static const int _defaultAiDailyLimit = 50;

  final ThemeMode themeMode;
  final AppSeedColor seedColor;
  final bool vibrationEnabled;
  final bool quietHoursEnabled;
  final QuietHoursWindow quietHours;
  final SnoozeDuration snoozeDuration;

  /// When `true`, reminders whose [Reminder.reminderTime] is more than 24
  /// hours in the past are removed on app start and on every foreground
  /// resume. Anchored to scheduled time, not creation or fire time.
  final bool autoDeleteAfter24h;

  /// Whether the user has opted in to using the AI assistant. Independent
  /// of [aiApiKey]: a key may still be stored while this is `false`, in
  /// which case the AI flows treat the assistant as unconfigured. The
  /// field defaults to `false` for new users and for old databases that
  /// pre-date this field, with no implicit migration from "has key".
  final bool aiAssistantEnabled;

  /// API key for the AI assistant backend. `null` when the user has not
  /// configured one. Whitespace-only values are normalized to `null` at
  /// both write time and read time, so the storage layer never sees a
  /// blank string.
  final String? aiApiKey;

  /// Whether the user has opted in to on-device Chinese OCR for
  /// screenshot parsing. The Chinese model itself is fetched via
  /// Google Play Services (Android) or bundled in the IPA (iOS); this
  /// flag is purely the user's "I want 中文 OCR" preference and is
  /// independent of whether the model is currently on disk. The
  /// analyzer falls back to the always-available Latin script when
  /// the Chinese model is missing or fails.
  final bool chineseOcrEnabled;

  /// User-customized system prompt for the "错误日志 → AI 分析" flow.
  /// `null` means use `DeepSeekAnalyzer.defaultErrorAnalysisPrompt`.
  /// No template variables — sent verbatim.
  final String? aiErrorAnalysisPrompt;

  /// User-customized system prompt template for the "AI 自动调整"
  /// flow in the reminder editor. `null` means use the built-in
  /// template (`DeepSeekAnalyzer.defaultAdjustPromptTemplate`).
  /// Supports the same `{{now}}`, `{{timezone}}`, `{{offset}}`,
  /// `{{weekday}}` placeholders as [aiAssistantPrompt].
  final String? aiAdjustPrompt;

  /// User-customized system prompt template for the "灵感分析"
  /// flow. `null` means use the built-in template
  /// (`DeepSeekAnalyzer.defaultInspirationAnalysisPromptTemplate`).
  final String? aiInspirationPrompt;

  /// Hard ceiling on AI calls per local-day. Used by [AiUsageGuard] to
  /// refuse new calls once [aiCallsToday] reaches this value. The user
  /// can adjust it from the AI settings page; anything outside the
  /// 1..999 range is clamped on write so the guard can never block
  /// permanently on a typo.
  final int aiDailyLimit;

  /// Whether [aiDailyLimit] is actually enforced. Defaults to `true`
  /// for new installs and old rows that pre-date the switch (the
  /// `fromJson` reader fills in `true` when the key is absent). When
  /// `false`, [AiUsageGuard] skips the ceiling check entirely — the
  /// in-process cooldown and the analyzer-level input sanitization
  /// still apply, but no call count is refused on quota grounds.
  final bool aiDailyLimitEnabled;

  /// Number of successful AI calls counted in the current local-day
  /// window (defined by [aiCallsResetAt]). Reset to 0 by
  /// [SettingsViewModel.incrementAiCallsToday] when the date rolls
  /// over.
  final int aiCallsToday;

  /// Wall-clock instant the daily counter was last (re)initialised.
  /// `null` means "no calls have been recorded yet", which the guard
  /// treats as a cold-start that initialises the counter to 1 on the
  /// first success.
  final DateTime? aiCallsResetAt;

  /// Wall-clock instant the user accepted the AI assistant consent
  /// dialog (User Agreement + Privacy Policy). `null` means the user
  /// has not yet opted in, so the next time the AI assistant is
  /// enabled the settings page will show the consent dialog. The
  /// field is set once and never cleared, so the dialog only appears
  /// the first time.
  final DateTime? aiConsentAcceptedAt;

  AppSettings copyWith({
    ThemeMode? themeMode,
    AppSeedColor? seedColor,
    bool? vibrationEnabled,
    bool? quietHoursEnabled,
    QuietHoursWindow? quietHours,
    SnoozeDuration? snoozeDuration,
    bool? autoDeleteAfter24h,
    bool? aiAssistantEnabled,
    String? aiApiKey,
    bool? chineseOcrEnabled,
    String? aiErrorAnalysisPrompt,
    bool clearAiErrorAnalysisPrompt = false,
    String? aiAdjustPrompt,
    bool clearAiAdjustPrompt = false,
    String? aiInspirationPrompt,
    bool clearAiInspirationPrompt = false,
    int? aiDailyLimit,
    bool? aiDailyLimitEnabled,
    int? aiCallsToday,
    DateTime? aiCallsResetAt,
    bool clearAiCallsResetAt = false,
    DateTime? aiConsentAcceptedAt,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      seedColor: seedColor ?? this.seedColor,
      vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
      quietHoursEnabled: quietHoursEnabled ?? this.quietHoursEnabled,
      quietHours: quietHours ?? this.quietHours,
      snoozeDuration: snoozeDuration ?? this.snoozeDuration,
      autoDeleteAfter24h: autoDeleteAfter24h ?? this.autoDeleteAfter24h,
      aiAssistantEnabled: aiAssistantEnabled ?? this.aiAssistantEnabled,
      aiApiKey: aiApiKey ?? this.aiApiKey,
      chineseOcrEnabled: chineseOcrEnabled ?? this.chineseOcrEnabled,
      aiErrorAnalysisPrompt: clearAiErrorAnalysisPrompt
          ? null
          : (aiErrorAnalysisPrompt ?? this.aiErrorAnalysisPrompt),
      aiAdjustPrompt: clearAiAdjustPrompt
          ? null
          : (aiAdjustPrompt ?? this.aiAdjustPrompt),
      aiInspirationPrompt: clearAiInspirationPrompt
          ? null
          : (aiInspirationPrompt ?? this.aiInspirationPrompt),
      aiDailyLimit: _normalizeDailyLimit(aiDailyLimit ?? this.aiDailyLimit),
      aiDailyLimitEnabled: aiDailyLimitEnabled ?? this.aiDailyLimitEnabled,
      aiCallsToday: aiCallsToday ?? this.aiCallsToday,
      aiCallsResetAt: clearAiCallsResetAt
          ? null
          : (aiCallsResetAt ?? this.aiCallsResetAt),
      aiConsentAcceptedAt: aiConsentAcceptedAt ?? this.aiConsentAcceptedAt,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'theme_mode': themeMode.name,
    'seed_color': seedColor.name,
    'vibration_enabled': vibrationEnabled,
    'quiet_hours_enabled': quietHoursEnabled,
    'quiet_hours': quietHours.toJson(),
    'snooze_duration': snoozeDuration.toJson(),
    'auto_delete_after_24h': autoDeleteAfter24h,
    'ai_assistant_enabled': aiAssistantEnabled,
    if (aiApiKey != null) 'ai_api_key': aiApiKey,
    'chinese_ocr_enabled': chineseOcrEnabled,
    if (aiErrorAnalysisPrompt != null)
      'ai_error_analysis_prompt': aiErrorAnalysisPrompt,
    if (aiAdjustPrompt != null) 'ai_adjust_prompt': aiAdjustPrompt,
    if (aiInspirationPrompt != null)
      'ai_inspiration_prompt': aiInspirationPrompt,
    'ai_daily_limit': aiDailyLimit,
    'ai_daily_limit_enabled': aiDailyLimitEnabled,
    'ai_calls_today': aiCallsToday,
    if (aiCallsResetAt != null)
      'ai_calls_reset_at': aiCallsResetAt!.toIso8601String(),
    if (aiConsentAcceptedAt != null)
      'ai_consent_accepted_at': aiConsentAcceptedAt!.toIso8601String(),
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    ThemeMode parseThemeMode(Object? value) {
      if (value is String) {
        return ThemeMode.values.firstWhere(
          (m) => m.name == value,
          orElse: () => ThemeMode.system,
        );
      }
      return ThemeMode.system;
    }

    AppSeedColor parseSeed(Object? value) {
      if (value is String) {
        return AppSeedColor.values.firstWhere(
          (c) => c.name == value,
          orElse: () => AppSeedColor.blue,
        );
      }
      return AppSeedColor.blue;
    }

    return AppSettings(
      themeMode: parseThemeMode(json['theme_mode']),
      seedColor: parseSeed(json['seed_color']),
      vibrationEnabled: (json['vibration_enabled'] as bool?) ?? true,
      quietHoursEnabled: (json['quiet_hours_enabled'] as bool?) ?? false,
      quietHours: QuietHoursWindow.fromJson(
        (json['quiet_hours'] as Map<String, dynamic>?) ??
            const <String, dynamic>{},
      ),
      snoozeDuration: SnoozeDuration.fromJson(
        (json['snooze_duration'] as Map<String, dynamic>?) ??
            const <String, dynamic>{},
      ),
      autoDeleteAfter24h: (json['auto_delete_after_24h'] as bool?) ?? true,
      aiAssistantEnabled: (json['ai_assistant_enabled'] as bool?) ?? false,
      aiApiKey: _normalizeOptionalString(json['ai_api_key']),
      chineseOcrEnabled: (json['chinese_ocr_enabled'] as bool?) ?? true,
      aiErrorAnalysisPrompt: _normalizeOptionalString(
        json['ai_error_analysis_prompt'],
      ),
      aiAdjustPrompt: _normalizeOptionalString(json['ai_adjust_prompt']),
      aiInspirationPrompt: _normalizeOptionalString(
        json['ai_inspiration_prompt'],
      ),
      aiDailyLimit: _normalizeDailyLimit(
        (json['ai_daily_limit'] as int?) ?? _defaultAiDailyLimit,
      ),
      aiDailyLimitEnabled: (json['ai_daily_limit_enabled'] as bool?) ?? true,
      aiCallsToday: _normalizeCallsToday(json['ai_calls_today']),
      aiCallsResetAt: _parseResetAt(json['ai_calls_reset_at']),
      aiConsentAcceptedAt: _parseResetAt(json['ai_consent_accepted_at']),
    );
  }

  static String? _normalizeOptionalString(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Clamps the user-configurable daily limit into a sane range so a
  /// hand-edited sqflite row can never wedge the guard.
  static int _normalizeDailyLimit(int value) {
    if (value < 1) return 1;
    if (value > 999) return 999;
    return value;
  }

  static int _normalizeCallsToday(Object? value) {
    if (value is! int) return 0;
    if (value < 0) return 0;
    return value;
  }

  static DateTime? _parseResetAt(Object? value) {
    if (value is! String) return null;
    return DateTime.tryParse(value);
  }
}

/// Human-readable label for a [ThemeMode]. Kept here so both the settings
/// home page and the appearance subpage can share the same wording.
String themeModeLabel(ThemeMode mode) {
  return switch (mode) {
    ThemeMode.system => '跟随系统',
    ThemeMode.light => '浅色',
    ThemeMode.dark => '深色',
  };
}

/// Human-readable label for an [AppSeedColor].
String appSeedColorLabel(AppSeedColor color) {
  return switch (color) {
    AppSeedColor.blue => '蓝色',
    AppSeedColor.green => '绿色',
    AppSeedColor.orange => '橙色',
    AppSeedColor.red => '红色',
    AppSeedColor.pink => '粉色',
    AppSeedColor.purple => '紫色',
  };
}

/// Short label suitable for dense subtitles.
String appSeedColorShortLabel(AppSeedColor color) {
  return switch (color) {
    AppSeedColor.blue => '蓝',
    AppSeedColor.green => '绿',
    AppSeedColor.orange => '橙',
    AppSeedColor.red => '红',
    AppSeedColor.pink => '粉',
    AppSeedColor.purple => '紫',
  };
}
