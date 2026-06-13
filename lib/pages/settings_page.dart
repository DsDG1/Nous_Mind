import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/app_settings.dart';
import '../viewmodels/settings_view_model.dart';
import '../widgets/settings_section.dart';

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
        child: Consumer<SettingsViewModel>(
          builder: (context, vm, _) {
            final settings = vm.settings;
            return ListView(
              children: <Widget>[
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
                      title: 'AI 助手',
                      subtitle: settings.aiApiKey == null ? '未配置' : '已配置',
                      leading: const Icon(Icons.auto_awesome_outlined),
                      onTap: () => context.push('/settings/ai'),
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

  static String _appearanceSubtitle(AppSettings settings) {
    return '${themeModeLabel(settings.themeMode)} · '
        '${appSeedColorShortLabel(settings.seedColor)}';
  }

  static String _notificationSubtitle(AppSettings settings) {
    final parts = <String>[];
    if (settings.vibrationEnabled) {
      parts.add('震动');
    }
    if (settings.quietHoursEnabled) {
      parts.add('免打扰');
    }
    return parts.isEmpty ? '默认设置' : parts.join(' · ');
  }
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
