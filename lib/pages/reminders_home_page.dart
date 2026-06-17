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
          return _AnimatedRemindersList(
            items: items,
            onTap: (reminder) => _openEditorFromItem(context, reminder),
            onDelete: (reminder) =>
                _deleteWithFeedback(context, viewModel, reminder),
            onAddToCalendar: _addToCalendarWithFeedback,
            onToggleComplete: (reminder) =>
                viewModel.setCompleted(reminder.id, !reminder.isCompleted),
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

/// `ListView.separated` wrapper that animates items when the data is
/// re-sorted — typically when a reminder is toggled between active
/// and completed and the active-first sort places it at a new index.
///
/// Each row gets a `_AnimatedReminderRow` which animates a
/// `Transform.translate` from the previous y-position to the new one
/// (FLIP — First, Last, Invert, Play). The first build records
/// positions and the row height; subsequent builds compute the
/// delta from the previous frame and replay it as a 350 ms slide.
class _AnimatedRemindersList extends StatefulWidget {
  const _AnimatedRemindersList({
    required this.items,
    required this.onTap,
    required this.onDelete,
    required this.onAddToCalendar,
    required this.onToggleComplete,
  });

  final List<Reminder> items;
  final void Function(Reminder reminder) onTap;
  final void Function(Reminder reminder) onDelete;
  final void Function(Reminder reminder) onAddToCalendar;
  final void Function(Reminder reminder) onToggleComplete;

  @override
  State<_AnimatedRemindersList> createState() => _AnimatedRemindersListState();
}

class _AnimatedRemindersListState extends State<_AnimatedRemindersList> {
  final GlobalKey _listKey = GlobalKey();
  ScrollController? _localScrollController;

  // Per-reminder measurement key. Stable across rebuilds so we can
  // find each item's `RenderBox` after layout to read its y-position.
  final Map<String, GlobalKey> _keys = <String, GlobalKey>{};
  // Absolute Y-position of each item in the scrollable content container
  // from the previous frame.
  final Map<String, double> _lastY = <String, double>{};
  // Individual height of each item, to support wrapping/multi-line layout.
  final Map<String, double> _heights = <String, double>{};
  // Row height fallback (ListTile + 1 px Divider). Measured/average.
  double? _rowHeight;

  ScrollController _getEffectiveScrollController() {
    return PrimaryScrollController.maybeOf(context) ??
        (_localScrollController ??= ScrollController());
  }

  @override
  void dispose() {
    _localScrollController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Measure positions after the next frame so _lastY and
    // _rowHeight are up to date for the *following* build.
    WidgetsBinding.instance.addPostFrameCallback(_recordPositions);

    // Compute absolute Y positions for the current layout based on measured heights
    final Map<String, double> newYAbsolute = {};
    double currentY = 0.0;
    final defaultHeight = _rowHeight ?? 56.0;
    for (final item in widget.items) {
      newYAbsolute[item.id] = currentY;
      final itemHeight = _heights[item.id] ?? defaultHeight;
      currentY += itemHeight + 1.0; // +1.0 for Divider(height: 1)
    }

    final scrollController = _getEffectiveScrollController();

    return ListView.separated(
      key: _listKey,
      controller: scrollController,
      itemCount: widget.items.length,
      separatorBuilder: (context, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final reminder = widget.items[index];
        final key = _keys.putIfAbsent(reminder.id, GlobalKey.new);
        final newY = newYAbsolute[reminder.id]!;
        // First build (no _lastY entry yet): offset is 0, no slide.
        // The row simply renders at its natural position.
        final oldY = _lastY[reminder.id] ?? newY;
        final offset = oldY - newY;
        return _AnimatedReminderRow(
          // Keying the row by reminder id preserves the
          // AnimationController state across rebuilds of the same
          // item — even when the item changes index in the list.
          key: ValueKey<String>(reminder.id),
          offset: offset,
          measurementKey: key,
          child: ReminderListItem(
            reminder: reminder,
            onTap: () => widget.onTap(reminder),
            onDelete: () => widget.onDelete(reminder),
            onAddToCalendar: () => widget.onAddToCalendar(reminder),
            onToggleComplete: () => widget.onToggleComplete(reminder),
          ),
        );
      },
    );
  }

  void _recordPositions(Duration _) {
    final currentIds = widget.items.map((r) => r.id).toSet();
    // Drop keys for items that left the visible list (filter
    // changed, soft-deleted, etc.) so the map does not grow.
    _keys.removeWhere((id, _) => !currentIds.contains(id));
    _lastY.removeWhere((id, _) => !currentIds.contains(id));
    _heights.removeWhere((id, _) => !currentIds.contains(id));

    final listRenderBox = _listKey.currentContext?.findRenderObject() as RenderBox?;
    if (listRenderBox == null) return;

    final scrollController = _getEffectiveScrollController();
    final scrollOffset = scrollController.hasClients ? scrollController.offset : 0.0;

    final newY = <String, double>{};
    for (final entry in _keys.entries) {
      final renderBox =
          entry.value.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox == null) continue;

      // visual position relative to ListView viewport
      final localOffset = renderBox.localToGlobal(Offset.zero, ancestor: listRenderBox);

      // absolute position in scrollable content
      newY[entry.key] = localOffset.dy + scrollOffset;

      // record height
      _heights[entry.key] = renderBox.size.height;
    }

    if (_heights.isNotEmpty) {
      _rowHeight = _heights.values.reduce((a, b) => a + b) / _heights.length;
    }

    _lastY
      ..clear()
      ..addAll(newY);
  }
}

/// Wraps a row in `Transform.translate` driven by an
/// `AnimationController`. When [offset] changes (parent detected
/// the row moved), the controller is reset and re-fires from the
/// new offset back to 0. Chaining rapid reorders produces a
/// smooth redirect from wherever the row currently sits.
class _AnimatedReminderRow extends StatefulWidget {
  const _AnimatedReminderRow({
    super.key,
    required this.offset,
    required this.child,
    required this.measurementKey,
  });

  final double offset;
  final Widget child;
  final Key measurementKey;

  @override
  State<_AnimatedReminderRow> createState() => _AnimatedReminderRowState();
}

class _AnimatedReminderRowState extends State<_AnimatedReminderRow>
    with SingleTickerProviderStateMixin {
  static const Duration _duration = Duration(milliseconds: 350);

  late final AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _duration);
    _animation = _buildAnimation(widget.offset);
    if (widget.offset != 0) _controller.forward();
  }

  @override
  void didUpdateWidget(covariant _AnimatedReminderRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.offset != 0) {
      // Calculate current translation value to ensure continuity
      final currentTranslation = _animation.value;
      final startOffset = widget.offset + currentTranslation;
      _animation = _buildAnimation(startOffset);
      _controller
        ..reset()
        ..forward();
    }
  }

  Animation<double> _buildAnimation(double offset) => CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOutCubic,
  ).drive(Tween<double>(begin: offset, end: 0));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: widget.measurementKey,
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, child) => Transform.translate(
          offset: Offset(0, _animation.value),
          child: child,
        ),
        child: widget.child,
      ),
    );
  }
}
