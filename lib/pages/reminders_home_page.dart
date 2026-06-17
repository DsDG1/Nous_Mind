import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:nousmind/models/reminder.dart';
import 'package:nousmind/models/tag.dart';
import 'package:nousmind/services/app_settings_bridge.dart';
import 'package:nousmind/services/calendar_service.dart';
import 'package:nousmind/utils/snackbar_x.dart';
import 'package:nousmind/viewmodels/reminders_view_model.dart';
import 'package:nousmind/viewmodels/tags_view_model.dart';
import 'package:nousmind/widgets/empty_state.dart';
import 'package:nousmind/widgets/reminder_list_item.dart';
import 'package:nousmind/widgets/tag_filter_sheet.dart';

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

  Future<void> _openFilterSheet(
    BuildContext context,
    RemindersViewModel remindersVm,
    TagsViewModel tagsVm,
  ) async {
    final selected = await TagFilterSheet.show(
      context,
      selectedTagId: remindersVm.selectedTagId,
      tags: tagsVm.tags,
      title: '筛选标签',
    );
    if (!context.mounted) return;
    if (selected == null) {
      // Dismissed (drag / close / outside tap) — do nothing, keep current filter
      return;
    }
    if (selected == TagFilterSheet.allTagsSentinel) {
      remindersVm.setSelectedTagId(null);
    } else if (selected == TagFilterSheet.createNewSentinel) {
      // The home page's sheet is read-only; nudge the user to the
      // settings subpage instead of inlining a creation flow.
      ScaffoldMessenger.of(context).showAppSnackBar('请到「设置 → 标签」中管理自定义标签');
    } else {
      remindersVm.setSelectedTagId(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('提醒事项'),
        leading: Selector<RemindersViewModel, String?>(
          selector: (_, vm) => vm.selectedTagId,
          builder: (context, selectedTagId, _) {
            return Consumer<TagsViewModel>(
              builder: (context, tagsVm, _) {
                final isFiltering = selectedTagId != null;
                return IconButton(
                  icon: Icon(
                    isFiltering ? Icons.filter_alt : Icons.filter_alt_outlined,
                  ),
                  tooltip: isFiltering
                      ? '筛选中：${_filterLabel(tagsVm, selectedTagId)}'
                      : '筛选标签',
                  onPressed: () => _openFilterSheet(
                    context,
                    context.read<RemindersViewModel>(),
                    tagsVm,
                  ),
                );
              },
            );
          },
        ),
      ),
      body: Consumer<RemindersViewModel>(
        builder: (context, viewModel, _) {
          if (!viewModel.isLoaded) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = viewModel.visibleReminders;
          if (items.isEmpty) {
            final hasFilter = viewModel.selectedTagId != null;
            return EmptyState(
              icon: hasFilter
                  ? Icons.filter_alt_off_outlined
                  : Icons.notifications_none,
              title: hasFilter ? '该标签下暂无提醒' : '还没有提醒',
              subtitle: hasFilter ? '切换筛选条件以查看其他提醒' : '点击右下角 + 添加',
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
                onToggleComplete: () =>
                    viewModel.setCompleted(reminder.id, !reminder.isCompleted),
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

  /// Resolves a tag id to a human label for the AppBar tooltip.
  /// Falls back to the id itself if the tag was just deleted.
  String _filterLabel(TagsViewModel tagsVm, String tagId) {
    if (tagId == kCompletedTagId) return '已完成';
    for (final t in tagsVm.tags) {
      if (t.id == tagId) return t.name;
    }
    return tagId;
  }
}
