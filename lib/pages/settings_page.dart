import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:nousmind/models/app_settings.dart';
import 'package:nousmind/viewmodels/settings_view_model.dart';
import 'package:nousmind/widgets/settings_section.dart';
import 'package:nousmind/widgets/settings_stats_card.dart';

/// Home of the settings tab. Renders a grouped list with one tile per
/// settings subpage plus a high-level summary that mirrors the current
/// preferences. Subpages own their own UI; this page is just an index.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: SafeArea(
        child: Selector<SettingsViewModel, _SettingsForSubtitle>(
          selector: (_, vm) => _SettingsForSubtitle.from(vm.settings),
          builder: (context, settings, _) {
            return ListView(
              children: <Widget>[
                const SettingsStatsCard(),
                SettingsSection(
                  title: '偏好',
                  icon: Icons.tune,
                  children: <Widget>[
                    SettingsTile(
                      title: '外观',
                      subtitle: _appearanceSubtitle(settings),
                      leading: _SeedColorLeading(
                        color: settings.seedColor.color,
                      ),
                      onTap: () => context.push('/settings/appearance'),
                    ),
                    SettingsTile(
                      title: '通知',
                      subtitle: _notificationSubtitle(settings),
                      leading: const Icon(Icons.notifications_outlined),
                      onTap: () => context.push('/settings/notification'),
                    ),
                    SettingsTile(
                      title: '数据',
                      subtitle: '备份、恢复与清理',
                      leading: const Icon(Icons.storage_outlined),
                      onTap: () => context.push('/settings/data'),
                    ),
                    SettingsTile(
                      title: 'AI 助手',
                      subtitle: _aiSubtitle(settings),
                      leading: const Icon(Icons.auto_awesome_outlined),
                      onTap: () => context.push('/settings/ai'),
                    ),
                    SettingsTile(
                      title: '关于',
                      subtitle: 'Nous 记事',
                      leading: const Icon(Icons.info_outline),
                      onTap: () => context.push('/settings/about'),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  static String _appearanceSubtitle(_SettingsForSubtitle settings) {
    return '${themeModeLabel(settings.themeMode)} · '
        '${appSeedColorShortLabel(settings.seedColor)}';
  }

  static String _notificationSubtitle(_SettingsForSubtitle settings) {
    final parts = <String>[];
    if (settings.vibrationEnabled) {
      parts.add('震动');
    }
    if (settings.quietHoursEnabled) {
      parts.add('免打扰');
    }
    parts.add('贪睡 ${settings.snoozeDuration.duration.inMinutes} 分钟');
    return parts.join(' · ');
  }

  static String _aiSubtitle(_SettingsForSubtitle settings) {
    if (!settings.aiAssistantEnabled) return '未启用';
    if (settings.aiApiKey == null) return '已启用 · 未填密钥';
    return '已启用';
  }
}

/// Selector key that holds only the fields the settings home renders, so the
/// `ListView` rebuilds only when those specific fields change. Unrelated
/// settings updates (e.g. quiet-hour windows or the auto-delete flag) are
/// ignored here.
class _SettingsForSubtitle {
  const _SettingsForSubtitle({
    required this.themeMode,
    required this.seedColor,
    required this.vibrationEnabled,
    required this.quietHoursEnabled,
    required this.snoozeDuration,
    required this.aiAssistantEnabled,
    required this.aiApiKey,
  });

  factory _SettingsForSubtitle.from(AppSettings settings) {
    return _SettingsForSubtitle(
      themeMode: settings.themeMode,
      seedColor: settings.seedColor,
      vibrationEnabled: settings.vibrationEnabled,
      quietHoursEnabled: settings.quietHoursEnabled,
      snoozeDuration: settings.snoozeDuration,
      aiAssistantEnabled: settings.aiAssistantEnabled,
      aiApiKey: settings.aiApiKey,
    );
  }

  final ThemeMode themeMode;
  final AppSeedColor seedColor;
  final bool vibrationEnabled;
  final bool quietHoursEnabled;
  final SnoozeDuration snoozeDuration;
  final bool aiAssistantEnabled;
  final String? aiApiKey;

  @override
  bool operator ==(Object other) =>
      other is _SettingsForSubtitle &&
      other.themeMode == themeMode &&
      other.seedColor == seedColor &&
      other.vibrationEnabled == vibrationEnabled &&
      other.quietHoursEnabled == quietHoursEnabled &&
      other.snoozeDuration == snoozeDuration &&
      other.aiAssistantEnabled == aiAssistantEnabled &&
      other.aiApiKey == aiApiKey;

  @override
  int get hashCode => Object.hash(
    themeMode,
    seedColor,
    vibrationEnabled,
    quietHoursEnabled,
    snoozeDuration,
    aiAssistantEnabled,
    aiApiKey,
  );
}

class _SeedColorLeading extends StatelessWidget {
  const _SeedColorLeading({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black26),
      ),
    );
  }
}
