import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/app_settings.dart';
import '../../router.dart';
import '../../services/notification_service.dart';
import '../../viewmodels/settings_view_model.dart';
import '../../widgets/reminder_popup.dart';
import '../../widgets/settings_section.dart';

/// Settings subpage for notification behavior.
///
/// Hosts vibration, quiet hours, and a "send test notification" entry.
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
    final navigatorState = rootNavigatorKey.currentState;
    if (navigatorState != null) {
      await showReminderPopup(
        // ignore: use_build_context_synchronously
        context: navigatorState.context,
        title: _testTitle,
      );
    }
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
}
