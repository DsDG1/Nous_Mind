import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:nousmind/models/inspiration.dart';
import 'package:nousmind/models/reminder.dart';
import 'package:nousmind/services/reminder_repository.dart';
import 'package:nousmind/utils/snackbar_x.dart';
import 'package:nousmind/viewmodels/inspirations_view_model.dart';
import 'package:nousmind/viewmodels/reminders_view_model.dart';
import 'package:nousmind/widgets/empty_state.dart';

/// Trash page reachable from `设置 → 数据 → 回收站`. Lists every
/// soft-deleted reminder and inspiration in a tabbed view, exposing
/// top-level bulk actions ("全部恢复" / "永久删除") per tab.
class TrashPage extends StatefulWidget {
  const TrashPage({super.key});

  @override
  State<TrashPage> createState() => _TrashPageState();
}

class _TrashPageState extends State<TrashPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  List<Reminder> _trashReminders = [];
  List<Inspiration> _trashInspirations = [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
    _reload();
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    setState(() {});
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final rVm = context.read<RemindersViewModel>();
    final iVm = context.read<InspirationsViewModel>();
    final rItems = await rVm.refreshAndFetchTrash();
    final iItems = await iVm.refreshAndFetchTrash();
    if (!mounted) return;
    setState(() {
      _trashReminders = rItems;
      _trashInspirations = iItems;
      _loading = false;
    });
  }

  Future<void> _confirmAndPurge() async {
    final isReminders = _tabController.index == 0;
    final title = isReminders ? '永久删除全部提醒？' : '永久删除全部灵感？';
    final content = isReminders
        ? '回收站中的所有提醒与附图将被永久清除，无法恢复。'
        : '回收站中的所有灵感与附图将被永久清除，无法恢复。';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
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
    int removed = 0;
    if (isReminders) {
      final vm = context.read<RemindersViewModel>();
      removed = await vm.purgeTrash();
    } else {
      final vm = context.read<InspirationsViewModel>();
      removed = await vm.purgeTrash();
    }
    await _reload();
    if (!mounted) return;
    setState(() => _busy = false);
    messenger.showAppSnackBar('已永久删除 $removed 项');
  }

  Future<void> _restoreAll() async {
    final isReminders = _tabController.index == 0;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    int restored = 0;
    if (isReminders) {
      final vm = context.read<RemindersViewModel>();
      final ids = _trashReminders.map((r) => r.id).toList();
      restored = await vm.restoreAll(ids);
    } else {
      final vm = context.read<InspirationsViewModel>();
      final ids = _trashInspirations.map((i) => i.id).toList();
      restored = await vm.restoreAll(ids);
    }
    await _reload();
    if (!mounted) return;
    setState(() => _busy = false);
    messenger.showAppSnackBar('已恢复 $restored 项');
  }

  @override
  Widget build(BuildContext context) {
    final hasItems = _tabController.index == 0
        ? _trashReminders.isNotEmpty
        : _trashInspirations.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('回收站'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '提醒事项'),
            Tab(text: '灵感'),
          ],
        ),
        actions: <Widget>[
          if (!_loading && hasItems)
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
            : TabBarView(
                controller: _tabController,
                children: [_buildRemindersTab(), _buildInspirationsTab()],
              ),
      ),
    );
  }

  Widget _buildRemindersTab() {
    if (_trashReminders.isEmpty) {
      return const EmptyState(
        icon: Icons.delete_outline,
        title: '提醒回收站是空的',
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
                  label: Text('全部恢复（${_trashReminders.length}）'),
                  onPressed: _busy ? null : _restoreAll,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: _trashReminders.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final r = _trashReminders[index];
              return _TrashListItem(
                reminder: r,
                onTap: _busy
                    ? null
                    : () async {
                        await context.push('/editor', extra: (r, Offset.zero));
                        if (!mounted) return;
                        await _reload();
                      },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildInspirationsTab() {
    if (_trashInspirations.isEmpty) {
      return const EmptyState(
        icon: Icons.delete_outline,
        title: '灵感回收站是空的',
        subtitle: '删除的灵感会在这里保留 30 天',
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
                  label: Text('全部恢复（${_trashInspirations.length}）'),
                  onPressed: _busy ? null : _restoreAll,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: _trashInspirations.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final i = _trashInspirations[index];
              return _TrashInspirationListItem(
                inspiration: i,
                onTap: _busy
                    ? null
                    : () async {
                        await context.push('/inspirations/editor', extra: i);
                        if (!mounted) return;
                        await _reload();
                      },
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Plain (non-dismissible) variant of [ReminderListItem] for the trash.
class _TrashListItem extends StatelessWidget {
  const _TrashListItem({required this.reminder, required this.onTap});

  final Reminder reminder;
  final VoidCallback? onTap;

  String _daysRemaining(DateTime deletedAt) {
    final cutoff = deletedAt.add(ReminderRepository.trashRetention);
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

class _TrashInspirationListItem extends StatelessWidget {
  const _TrashInspirationListItem({
    required this.inspiration,
    required this.onTap,
  });

  final Inspiration inspiration;
  final VoidCallback? onTap;

  String _daysRemaining(DateTime deletedAt) {
    final cutoff = deletedAt.add(const Duration(days: 30));
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
      leading: Icon(Icons.lightbulb_outline, color: colors.onSurfaceVariant),
      title: Text(
        inspiration.text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: textTheme.titleMedium?.copyWith(color: colors.onSurfaceVariant),
      ),
      subtitle: Text(
        _daysRemaining(inspiration.deletedAt ?? DateTime.now()),
        style: textTheme.bodySmall,
      ),
    );
  }
}
