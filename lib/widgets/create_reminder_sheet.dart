import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Bottom sheet that lets the user choose between creating a reminder
/// manually or via the AI assistant.
///
/// Shown by tapping the FAB on the reminders home page. The [fabPosition]
/// is forwarded to the destination route so the circular-reveal transition
/// continues to grow out of the FAB icon.
class CreateReminderSheet extends StatelessWidget {
  const CreateReminderSheet({super.key, required this.fabPosition});

  final Offset fabPosition;

  /// Shows the modal bottom sheet using [context]'s navigator.
  static Future<void> show(
    BuildContext context, {
    required Offset fabPosition,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => CreateReminderSheet(fabPosition: fabPosition),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '新建提醒',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
            _SheetOption(
              icon: Icons.edit_note,
              iconColor: colors.onPrimaryContainer,
              iconBg: colors.primaryContainer,
              title: '新增提醒',
              subtitle: '手动填写标题和时间',
              semanticsLabel: '新增提醒（手动）',
              onTap: () => _closeAndThen(context, () {
                context.push('/editor', extra: (null, fabPosition));
              }),
            ),
            _SheetOption(
              icon: Icons.auto_awesome,
              iconColor: colors.onTertiaryContainer,
              iconBg: colors.tertiaryContainer,
              title: '新增提醒（AI）',
              subtitle: '粘贴文本或截图，自动提取',
              semanticsLabel: '新增提醒（AI）',
              onTap: () => _closeAndThen(context, () {
                context.push('/assistant', extra: fabPosition);
              }),
            ),
          ],
        ),
      ),
    );
  }

  /// Pops the sheet first, then schedules [action] on the next microtask
  /// so the pop animation starts before the new route is pushed.
  void _closeAndThen(BuildContext context, VoidCallback action) {
    Navigator.of(context).pop();
    Future.microtask(action);
  }
}

/// One tappable row inside [CreateReminderSheet].
class _SheetOption extends StatelessWidget {
  const _SheetOption({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.semanticsLabel,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String subtitle;
  final String semanticsLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: semanticsLabel,
      child: Tooltip(
        message: semanticsLabel,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: <Widget>[
                CircleAvatar(
                  radius: 22,
                  backgroundColor: iconBg,
                  child: Icon(icon, color: iconColor),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(title, style: Theme.of(context).textTheme.bodyLarge),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
