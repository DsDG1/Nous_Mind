import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:nousmind/services/backup_service.dart';
import 'package:nousmind/viewmodels/inspirations_view_model.dart';
import 'package:nousmind/viewmodels/reminders_view_model.dart';
import 'package:nousmind/widgets/settings_section.dart';

/// Settings subpage for data management: stats, backup / restore, and
/// bulk-clear actions. Every mutation goes through the relevant view
/// model so the in-memory state and database stay in sync.
class DataSettingsPage extends StatefulWidget {
  const DataSettingsPage({super.key});

  @override
  State<DataSettingsPage> createState() => _DataSettingsPageState();
}

class _DataSettingsPageState extends State<DataSettingsPage> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(context.read<BackupService>().refreshStats());
    // Refresh the trash count whenever the page becomes visible so the
    // tile subtitle matches the actual on-disk state. The router pushes
    // us back here when the user returns from the trash page; using a
    // `didChangeDependencies` would also work but `initState` covers
    // the first paint and a manual refresh after navigation covers
    // the rest.
  }

  Future<void> _refreshTrashCount() async {
    // Cheap refresh that only re-counts the trash. We do this on every
    // build via a Selector below, so calling it manually is only needed
    // when we return from the trash page (which is handled by the
    // route-pop callback in `_openTrash`).
    await context.read<RemindersViewModel>().refreshTrashCount();
  }

  Future<void> _openTrash() async {
    await context.push<void>('/settings/data/trash');
    if (!mounted) return;
    await _refreshTrashCount();
  }

  Future<void> _export() async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final backup = context.read<BackupService>();
    try {
      final file = await backup.exportToFile();
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[XFile(file.path, mimeType: 'application/json')],
          text: 'Nous 记事 备份',
        ),
      );
    } on Exception catch (error) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('导出失败: $error')));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _import() async {
    if (_busy) return;
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['json'],
    );
    if (picked == null || picked.files.isEmpty) return;
    final path = picked.files.first.path;
    if (path == null || !mounted) return;

    final confirmed = await _confirmImport();
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final backup = context.read<BackupService>();
    final remindersVm = context.read<RemindersViewModel>();
    final inspirationsVm = context.read<InspirationsViewModel>();
    try {
      final result = await backup.importFromFile(File(path));
      await remindersVm.refresh();
      await inspirationsVm.refresh();
      unawaited(backup.refreshStats());
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              '已导入 ${result.remindersImported} 条提醒、'
              '${result.inspirationsImported} 条灵感',
            ),
          ),
        );
    } on FormatException catch (error) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('文件格式无效: ${error.message}')));
    } on Exception catch (error) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('导入失败: $error')));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<bool?> _confirmImport() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导入备份？'),
        content: const Text(
          '新条目会与现有数据合并,已存在的条目会被跳过。'
          '设置项不会被覆盖。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('导入'),
          ),
        ],
      ),
    );
  }

  Future<void> _clearRemindersToTrash() async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final remindersVm = context.read<RemindersViewModel>();
    final backup = context.read<BackupService>();
    // Snapshot the current list so the SnackBar's "撤销" button can
    // ask the view model to restore the same set in one click.
    final snapshot = List<String>.from(remindersVm.reminders.map((r) => r.id));
    try {
      final moved = await remindersVm.clearAllToTrash();
      unawaited(backup.refreshStats());
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('已移入回收站 $moved 条提醒'),
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: '撤销',
              onPressed: () async {
                await remindersVm.restoreAll(snapshot);
                if (!mounted) return;
                messenger
                  ..hideCurrentSnackBar()
                  ..showSnackBar(
                    SnackBar(content: Text('已恢复 ${snapshot.length} 条')),
                  );
              },
            ),
          ),
        );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _clearInspirations() async {
    if (_busy) return;
    final confirmed = await _confirmBulk(
      title: '清空所有灵感？',
      message: '所有灵感及其图片将被永久删除。此操作不可撤销。',
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final inspirationsVm = context.read<InspirationsViewModel>();
    final backup = context.read<BackupService>();
    try {
      final removed = await inspirationsVm.clearAll();
      unawaited(backup.refreshStats());
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('已删除 $removed 条灵感')));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _clearAll() async {
    if (_busy) return;
    final confirmed = await _confirmBulk(
      title: '清空所有数据？',
      message: '所有提醒、灵感与图片将被永久删除。设置项保留。此操作不可撤销。',
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final remindersVm = context.read<RemindersViewModel>();
    final inspirationsVm = context.read<InspirationsViewModel>();
    final backup = context.read<BackupService>();
    try {
      final r = await remindersVm.clearAll();
      final i = await inspirationsVm.clearAll();
      unawaited(backup.refreshStats());
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('已清空 ($r 条提醒, $i 条灵感)')));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<bool?> _confirmBulk({required String title, required String message}) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.onErrorContainer,
              backgroundColor: Theme.of(ctx).colorScheme.errorContainer,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('数据')),
      body: SafeArea(
        child: AbsorbPointer(
          absorbing: _busy,
          child: ListView(
            children: <Widget>[
              SettingsSection(
                title: '存储',
                icon: Icons.storage_outlined,
                children: <Widget>[
                  ValueListenableBuilder<StorageStats?>(
                    valueListenable:
                        context.read<BackupService>().statsNotifier,
                    builder: (context, stats, _) => _StatsRow(stats: stats),
                  ),
                ],
              ),
              SettingsSection(
                title: '回收站',
                icon: Icons.delete_outline,
                children: <Widget>[
                  Selector<RemindersViewModel, int>(
                    selector: (_, vm) => vm.trashCount,
                    builder: (context, trashCount, _) {
                      final subtitle = trashCount == 0
                          ? '已删提醒会在此保留 30 天'
                          : '$trashCount 项 · 最早将在 1 天后清除';
                      return SettingsTile(
                        leading: const Icon(Icons.restore_from_trash_outlined),
                        title: '回收站',
                        subtitle: subtitle,
                        onTap: _busy ? null : _openTrash,
                      );
                    },
                  ),
                ],
              ),
              SettingsSection(
                title: '备份与恢复',
                icon: Icons.import_export,
                children: <Widget>[
                  SettingsTile(
                    leading: const Icon(Icons.upload_outlined),
                    title: '导出备份',
                    subtitle: '保存为 JSON 文件,可分享到任意位置',
                    onTap: _busy ? null : _export,
                  ),
                  SettingsTile(
                    leading: const Icon(Icons.download_outlined),
                    title: '导入备份',
                    subtitle: '从 JSON 文件中合入新条目',
                    onTap: _busy ? null : _import,
                  ),
                ],
              ),
              SettingsSection(
                title: '清空',
                icon: Icons.delete_sweep_outlined,
                children: <Widget>[
                  SettingsTile(
                    leading: const Icon(Icons.restore_from_trash_outlined),
                    title: '全部移入回收站',
                    subtitle: '可从回收站恢复 30 天',
                    onTap: _busy ? null : _clearRemindersToTrash,
                  ),
                  SettingsTile(
                    leading: const Icon(Icons.lightbulb_outline),
                    title: '清空所有灵感',
                    subtitle: '永久删除所有灵感与附图',
                    onTap: _busy ? null : _clearInspirations,
                  ),
                  SettingsTile(
                    leading: const Icon(Icons.delete_forever_outlined),
                    title: '清空全部数据',
                    subtitle: '永久删除所有提醒、灵感与图片',
                    onTap: _busy ? null : _clearAll,
                  ),
                ],
              ),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Single read-only row showing the live storage stats.
class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.stats});

  final StorageStats? stats;

  @override
  Widget build(BuildContext context) {
    if (stats == null) {
      return const ListTile(
        leading: Icon(Icons.hourglass_empty),
        title: Text('正在加载……'),
      );
    }
    final s = stats;
    final reminderText = s == null ? '—' : '${s.reminderCount}';
    final inspirationText = s == null ? '—' : '${s.inspirationCount}';
    final imageText = s == null ? '—' : BackupService.formatBytes(s.imageBytes);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _StatCell(label: '提醒', value: reminderText),
          ),
          const _StatDivider(),
          Expanded(
            child: _StatCell(label: '灵感', value: inspirationText),
          ),
          const _StatDivider(),
          Expanded(
            child: _StatCell(label: '图片', value: imageText),
          ),
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          value,
          style: textTheme.titleLarge?.copyWith(
            color: colors.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: textTheme.bodySmall),
      ],
    );
  }
}

class _StatDivider extends StatelessWidget {
  const _StatDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 32,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: Theme.of(context).dividerColor,
    );
  }
}
