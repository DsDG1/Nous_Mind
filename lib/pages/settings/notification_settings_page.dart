import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/app_settings.dart';
import '../../services/notification_service.dart';
import '../../viewmodels/settings_view_model.dart';
import '../../widgets/settings_section.dart';

/// Settings subpage for notification behavior.
///
/// Hosts four groups: vibration, quiet hours, lead time, and a single
/// "send a test notification" entry that lets the user verify their
/// preferences end-to-end without waiting for a real reminder.
class NotificationSettingsPage extends StatelessWidget {
  const NotificationSettingsPage({super.key});

  static const String _testTitle = '测试通知';
  static const String _testBody = '通知功能正常工作';
  static const String _permissionDeniedMessage = '未授予通知权限';
  static const String _sentMessage = '已发送测试通知';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('通知')),
      body: SafeArea(
        child: Consumer<SettingsViewModel>(
          builder: (context, vm, _) {
            final settings = vm.settings;
            return ListView(
              children: <Widget>[
                SettingsSection(
                  title: '提醒方式',
                  icon: Icons.notifications_outlined,
                  children: <Widget>[
                    SwitchListTile(
                      title: const Text('震动'),
                      subtitle: const Text('通知到达时震动'),
                      secondary: const Icon(Icons.vibration),
                      value: settings.vibrationEnabled,
                      onChanged: vm.setVibrationEnabled,
                    ),
                  ],
                ),
                SettingsSection(
                  title: '免打扰',
                  icon: Icons.do_not_disturb_on_outlined,
                  children: <Widget>[
                    SwitchListTile(
                      title: const Text('启用免打扰'),
                      subtitle: const Text('在指定时段内推迟提醒'),
                      secondary: const Icon(Icons.bedtime_outlined),
                      value: settings.quietHoursEnabled,
                      onChanged: vm.setQuietHoursEnabled,
                    ),
                    SettingsTile(
                      title: '时间段',
                      subtitle: _formatRange(settings.quietHours),
                      leading: const Icon(Icons.schedule_outlined),
                      onTap: settings.quietHoursEnabled
                          ? () => _editQuietHours(context, vm, settings.quietHours)
                          : null,
                    ),
                  ],
                ),
                SettingsSection(
                  title: '提前提醒',
                  icon: Icons.access_time,
                  children: <Widget>[
                    SettingsTile(
                      title: '提前时长',
                      subtitle: settings.leadTime.label,
                      leading: const Icon(Icons.timelapse_outlined),
                      onTap: () => _pickLeadTime(context, vm, settings.leadTime),
                    ),
                  ],
                ),
                SettingsSection(
                  title: '测试',
                  icon: Icons.science_outlined,
                  children: <Widget>[
                    SettingsTile(
                      title: '发送测试通知',
                      subtitle: '立即收到一条通知，验证设置',
                      leading: const Icon(Icons.send_outlined),
                      onTap: () => _sendTestNotification(context),
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

  static String _formatRange(QuietHoursWindow window) {
    final start = _formatTime(window.start);
    final end = _formatTime(window.end);
    final cross = window.isCrossDay ? '（跨天）' : '';
    return '$start – $end$cross';
  }

  static String _formatTime(TimeOfDay t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}';
  }

  Future<void> _sendTestNotification(BuildContext context) async {
    final service = context.read<NotificationService>();
    final vm = context.read<SettingsViewModel>();
    final messenger = ScaffoldMessenger.of(context);
    final granted = await service.requestPermissions();
    if (!granted) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text(_permissionDeniedMessage)));
      return;
    }
    await service.showImmediate(
      title: _testTitle,
      body: _testBody,
      vibrationEnabled: vm.settings.vibrationEnabled,
    );
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text(_sentMessage)));
  }

  Future<void> _editQuietHours(
    BuildContext context,
    SettingsViewModel vm,
    QuietHoursWindow current,
  ) async {
    final pickedStart = await showTimePicker(
      context: context,
      initialTime: current.start,
      helpText: '开始时间',
    );
    if (pickedStart == null || !context.mounted) {
      return;
    }
    final pickedEnd = await showTimePicker(
      context: context,
      initialTime: current.end,
      helpText: '结束时间',
    );
    if (pickedEnd == null) {
      return;
    }
    await vm.setQuietHours(
      QuietHoursWindow(start: pickedStart, end: pickedEnd),
    );
  }

  Future<void> _pickLeadTime(
    BuildContext context,
    SettingsViewModel vm,
    LeadTime current,
  ) async {
    const presets = <(LeadTimePreset, String)>[
      (LeadTimePreset.off, '不提前'),
      (LeadTimePreset.fiveMinutes, '提前 5 分钟'),
      (LeadTimePreset.fifteenMinutes, '提前 15 分钟'),
      (LeadTimePreset.thirtyMinutes, '提前 30 分钟'),
      (LeadTimePreset.custom, '自定义...'),
    ];
    final selected = await showModalBottomSheet<LeadTimePreset>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: RadioGroup<LeadTimePreset>(
            groupValue: current.preset,
            onChanged: (value) => Navigator.of(ctx).pop(value),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (final (preset, label) in presets)
                  RadioListTile<LeadTimePreset>(
                    title: Text(label),
                    value: preset,
                  ),
              ],
            ),
          ),
        );
      },
    );
    if (selected == null) {
      return;
    }
    if (selected == LeadTimePreset.custom) {
      if (!context.mounted) {
        return;
      }
      final minutes = await _pickCustomMinutes(context, current.custom);
      if (minutes == null) {
        return;
      }
      await vm.setLeadTime(
        LeadTime(preset: LeadTimePreset.custom, custom: minutes),
      );
    } else {
      await vm.setLeadTime(LeadTime(preset: selected));
    }
  }

  Future<Duration?> _pickCustomMinutes(
    BuildContext context,
    Duration current,
  ) async {
    final controller = TextEditingController(
      text: current.inMinutes.toString(),
    );
    final minutes = await showDialog<int>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('自定义提前时长'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              suffixText: '分钟',
              border: OutlineInputBorder(),
            ),
            autofocus: true,
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final parsed = int.tryParse(controller.text.trim());
                if (parsed == null || parsed < 0 || parsed > 24 * 60) {
                  Navigator.of(ctx).pop();
                  return;
                }
                Navigator.of(ctx).pop(parsed);
              },
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (minutes == null) {
      return null;
    }
    return Duration(minutes: minutes);
  }
}
