import 'package:flutter/material.dart';

import '../models/reminder.dart';
import '../utils/date_format.dart';

/// A swipe-to-delete list row representing a single [Reminder].
///
/// The row exposes:
///   * a tap to open the editor (handled by the parent)
///   * a left swipe that triggers [onDelete] and shows a [SnackBar]
class ReminderListItem extends StatelessWidget {
  const ReminderListItem({
    super.key,
    required this.reminder,
    required this.onTap,
    required this.onDelete,
  });

  final Reminder reminder;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Dismissible(
      key: ValueKey<String>(reminder.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: colors.error,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Icon(Icons.delete, color: colors.onError),
      ),
      onDismissed: (_) => onDelete(),
      child: ListTile(
        onTap: onTap,
        leading: Icon(Icons.notifications_outlined, color: colors.primary),
        title: Text(
          reminder.title,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        subtitle: Text(formatDateTime(reminder.reminderTime)),
      ),
    );
  }
}
