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
    return QuietHoursWindow(
      start: start ?? this.start,
      end: end ?? this.end,
    );
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
      start: TimeOfDay(
        hour: startMinutes ~/ 60,
        minute: startMinutes % 60,
      ),
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
/// through [copyWith] and round-trip through JSON for [SettingsStorage].
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.seedColor = AppSeedColor.blue,
    this.vibrationEnabled = true,
    this.quietHoursEnabled = false,
    this.quietHours = const QuietHoursWindow(),
    this.snoozeDuration = const SnoozeDuration(),
  });

  final ThemeMode themeMode;
  final AppSeedColor seedColor;
  final bool vibrationEnabled;
  final bool quietHoursEnabled;
  final QuietHoursWindow quietHours;
  final SnoozeDuration snoozeDuration;

  AppSettings copyWith({
    ThemeMode? themeMode,
    AppSeedColor? seedColor,
    bool? vibrationEnabled,
    bool? quietHoursEnabled,
    QuietHoursWindow? quietHours,
    SnoozeDuration? snoozeDuration,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      seedColor: seedColor ?? this.seedColor,
      vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
      quietHoursEnabled: quietHoursEnabled ?? this.quietHoursEnabled,
      quietHours: quietHours ?? this.quietHours,
      snoozeDuration: snoozeDuration ?? this.snoozeDuration,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'theme_mode': themeMode.name,
    'seed_color': seedColor.name,
    'vibration_enabled': vibrationEnabled,
    'quiet_hours_enabled': quietHoursEnabled,
    'quiet_hours': quietHours.toJson(),
    'snooze_duration': snoozeDuration.toJson(),
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
    );
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
