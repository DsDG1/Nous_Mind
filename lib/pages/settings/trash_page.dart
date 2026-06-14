import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../models/reminder.dart';
import '../../viewmodels/reminders_view_model.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/reminder_list_item.dart';

/// Trash page reachable from `设置 → 数据 → 回收站`. Lists every
/// soft-deleted reminder, exposes two top-level bulk actions
/// ("全部恢复" / "永久删除"), and renders a per-row "X 天后清除"
/// countdown based on [RemindersViewModel.trashRetention].
///
/// The page does not maintain its own copy of the trash list —
/// the parent [RemindersViewModel] is the single source of truth, and
/// any mutation flows through it so the active reminders list and
/// the data-settings tile count stay in sync without extra plumbing.
class TrashPage extends StatefulWidget {
  const TrashPage({super.key});

  @override
  State<TrashPage> createState() => _TrashPageState();
}

class _TrashPageState extends State<TrashPage> {
  late Future<List<Reminder>> _loadFuture;

  @override
  void initState() {
    super.initState();
    _loadFuture = _loadTrash();
  }

  Future<List<Reminder>> _loadTrash() async {
    final repo = context.read<RemindersViewModel>();
    // We re-read the repository via the VM's helper to avoid coupling
    // this page to the underlying SQLite schema; a future move to a
    // dedicated provider or stream can swap the implementation here.
    return repo.refreshAndFetchTrash();
  }

  Future<void> _reload() async {
    final next = await _loadTrash();
    if (!mounted) return;
    setState(() => _loadFuture = Future<List<Reminder>>.value(next));
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
    final messenger = ScaffoldMessenger.of(context);
    final vm = context.read<RemindersViewModel>();
    final removed = await vm.purgeTrash();
    await _reload();
    if (!mounted) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('已永久删除 $removed 项')));
  }

  Future<void> _restoreAll(List<Reminder> items) async {
    final messenger = ScaffoldMessenger.of(context);
    final vm = context.read<RemindersViewModel>();
    for (final r in items) {
      await vm.restore(r.id);
    }
    await _reload();
    if (!mounted) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('已恢复 ${items.length} 项')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('回收站'),
        actions: <Widget>[
          Consumer<RemindersViewModel>(
            builder: (context, vm, _) {
              if (vm.trashCount == 0) return const SizedBox.shrink();
              return TextButton.icon(
                icon: const Icon(Icons.delete_forever_outlined),
                label: const Text('永久删除'),
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                onPressed: _confirmAndPurge,
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<List<Reminder>>(
          future: _loadFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final items = snapshot.data ?? const <Reminder>[];
            if (items.isEmpty) {
              return const EmptyState(
                icon: Icons.delete_outline,
                title: '回收站是空的',
                subtitle: '删除的提醒会在这里保留 30 天',
              );
            }
            return Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: FilledButton.tonalIcon(
                          icon: const Icon(Icons.restore),
                          label: Text('全部恢复（${items.length}）'),
                          onPressed: () => _restoreAll(items),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final r = items[index];
                      return _TrashListItem(
                        reminder: r,
                        onTap: () =>
                            context.push('/editor', extra: (r, Offset.zero)),
                      );
                    },
                  ),
                ),
              ],
            );
          },
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
  final VoidCallback onTap;

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
