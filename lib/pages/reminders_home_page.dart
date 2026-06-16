import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:nousmind/models/reminder.dart';
import 'package:nousmind/services/app_settings_bridge.dart';
import 'package:nousmind/services/calendar_service.dart';
import 'package:nousmind/utils/snackbar_x.dart';
import 'package:nousmind/viewmodels/reminders_view_model.dart';
import 'package:nousmind/widgets/empty_state.dart';
import 'package:nousmind/widgets/reminder_list_item.dart';

/// Home screen: shows all reminders, hosts the FAB to add a new one, and
/// routes taps to the editor and left-swipes to delete.
class RemindersHomePage extends StatefulWidget {
  const RemindersHomePage({super.key});

  @override
  State<RemindersHomePage> createState() => _RemindersHomePageState();
}

class _RemindersHomePageState extends State<RemindersHomePage> {
  final GlobalKey _fabKey = GlobalKey();
  final CalendarService _calendar = CalendarService();
  final AppSettingsBridge _appSettings = AppSettingsBridge();

  Future<void> _openEditor(BuildContext context, Reminder? existing) async {
    final fabRenderBox =
        _fabKey.currentContext?.findRenderObject() as RenderBox?;
    final fabPosition = fabRenderBox != null
        ? fabRenderBox.localToGlobal(
            Offset(fabRenderBox.size.width / 2, fabRenderBox.size.height / 2),
          )
        : Offset.zero;
    await context.push('/editor', extra: (existing, fabPosition));
  }

  Future<void> _openEditorFromItem(
    BuildContext context,
    Reminder existing,
  ) async {
    await context.push('/editor', extra: (existing, null as Offset?));
  }

  Future<void> _deleteWithFeedback(
    BuildContext context,
    RemindersViewModel viewModel,
    Reminder reminder,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    await viewModel.softDelete(reminder.id);
    messenger.showAppSnackBar(
      '已移入回收站「${reminder.title}」',
      duration: const Duration(seconds: 5),
      action: SnackBarAction(
        label: '撤销',
        onPressed: () => viewModel.restore(reminder.id),
      ),
    );
  }

  Future<void> _addToCalendarWithFeedback(Reminder reminder) async {
    final messenger = ScaffoldMessenger.of(context);
    final granted = await _calendar.requestPermissions();
    if (!granted) {
      if (!mounted) return;
      messenger.showAppSnackBar(
        '未授予日历写入权限',
        action: SnackBarAction(
          label: '去设置',
          onPressed: _appSettings.openAppSettings,
        ),
      );
      return;
    }
    final result = await _calendar.addReminder(reminder);
    if (!mounted) return;
    final message = switch (result) {
      CalendarAddResult.success => '已加入日历',
      CalendarAddResult.noCalendars => '设备上没有日历账户，请先添加一个日历账户',
      CalendarAddResult.noWritableCalendar => '没有可写入的日历，请检查日历权限',
      CalendarAddResult.writeFailed => '写入日历失败，请稍后重试',
    };
    messenger.showAppSnackBar(message);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('提醒事项')),
      body: Consumer<RemindersViewModel>(
        builder: (context, viewModel, _) {
          if (!viewModel.isLoaded) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = viewModel.reminders;
          if (items.isEmpty) {
            return const EmptyState(
              icon: Icons.notifications_none,
              title: '还没有提醒',
              subtitle: '点击右下角 + 添加',
            );
          }
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final reminder = items[index];
              return ReminderListItem(
                reminder: reminder,
                onTap: () => _openEditorFromItem(context, reminder),
                onDelete: () =>
                    _deleteWithFeedback(context, viewModel, reminder),
                onAddToCalendar: () => _addToCalendarWithFeedback(reminder),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        key: _fabKey,
        heroTag: 'reminders-fab',
        onPressed: () => _openEditor(context, null),
        tooltip: '添加提醒',
        child: const Icon(Icons.add),
      ),
    );
  }
}
