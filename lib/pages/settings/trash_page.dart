import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:nousmind/models/reminder.dart';
import 'package:nousmind/utils/snackbar_x.dart';
import 'package:nousmind/viewmodels/reminders_view_model.dart';
import 'package:nousmind/widgets/empty_state.dart';

/// Trash page reachable from `设置 → 数据 → 回收站`. Lists every
/// soft-deleted reminder, exposes two top-level bulk actions
/// ("全部恢复" / "永久删除"), and renders a per-row "X 天后清除"
/// countdown based on [RemindersViewModel.trashRetention].
class TrashPage extends StatefulWidget {
  const TrashPage({super.key});

  @override
  State<TrashPage> createState() => _TrashPageState();
}

class _TrashPageState extends State<TrashPage> {
  List<Reminder> _trashItems = [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final vm = context.read<RemindersViewModel>();
    final items = await vm.refreshAndFetchTrash();
    if (!mounted) return;
    setState(() {
      _trashItems = items;
      _loading = false;
    });
  }

  Future<void> _confirmAndPurge() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('永久删除全部？'),
        content: const Text('回收站中的所有提醒与附图将被永久清除，无法恢复。'),
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
            child: const Text('永久删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final vm = context.read<RemindersViewModel>();
    final removed = await vm.purgeTrash();
    await _reload();
    if (!mounted) return;
    setState(() => _busy = false);
    messenger.showAppSnackBar('已永久删除 $removed 项');
  }

  Future<void> _restoreAll() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final vm = context.read<RemindersViewModel>();
    final ids = _trashItems.map((r) => r.id).toList();
    final restored = await vm.restoreAll(ids);
    await _reload();
    if (!mounted) return;
    setState(() => _busy = false);
    messenger.showAppSnackBar('已恢复 $restored 项');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('回收站'),
        actions: <Widget>[
          if (_trashItems.isNotEmpty)
            TextButton.icon(
              icon: const Icon(Icons.delete_forever_outlined),
              label: const Text('永久删除'),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: _busy ? null : _confirmAndPurge,
            ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _trashItems.isEmpty
            ? const EmptyState(
                icon: Icons.delete_outline,
                title: '回收站是空的',
                subtitle: '删除的提醒会在这里保留 30 天',
              )
            : Column(
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: FilledButton.tonalIcon(
                            icon: const Icon(Icons.restore),
                            label: Text('全部恢复（${_trashItems.length}）'),
                            onPressed: _busy ? null : _restoreAll,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.separated(
                      itemCount: _trashItems.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final r = _trashItems[index];
                        return _TrashListItem(
                          reminder: r,
                          onTap: _busy
                              ? null
                              : () async {
                                  await context.push(
                                    '/editor',
                                    extra: (r, Offset.zero),
                                  );
                                  if (!mounted) return;
                                  await _reload();
                                },
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Plain (non-dismissible) variant of [ReminderListItem] for the trash.
/// Subtitle shows the "将在 X 天后清除" countdown instead of the fire
/// time, since the reminder is no longer scheduled.
class _TrashListItem extends StatelessWidget {
  const _TrashListItem({required this.reminder, required this.onTap});

  final Reminder reminder;
  final VoidCallback? onTap;

  String _daysRemaining(DateTime deletedAt) {
    final cutoff = deletedAt.add(RemindersViewModel.trashRetention);
    final remaining = cutoff.difference(DateTime.now());
    if (remaining.isNegative) return '即将清除';
    final days = remaining.inDays;
    if (days <= 0) return '今天清除';
    if (days == 1) return '将在 1 天后清除';
    return '将在 $days 天后清除';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return ListTile(
      onTap: onTap,
      leading: Icon(
        Icons.notifications_off_outlined,
        color: colors.onSurfaceVariant,
      ),
      title: Text(
        reminder.title,
        style: textTheme.titleMedium?.copyWith(color: colors.onSurfaceVariant),
      ),
      subtitle: Text(
        _daysRemaining(reminder.deletedAt ?? DateTime.now()),
        style: textTheme.bodySmall,
      ),
    );
  }
}
