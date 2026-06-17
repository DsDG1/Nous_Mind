import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:nousmind/models/reminder.dart';
import 'package:nousmind/models/tag.dart';
import 'package:nousmind/utils/date_format.dart';
import 'package:nousmind/viewmodels/tags_view_model.dart';
import 'package:nousmind/widgets/tag_chip.dart';

/// A swipe-to-delete list row representing a single [Reminder].
///
/// The row exposes:
///   * a tap to open the editor (handled by the parent)
///   * a leading check-circle button that toggles [onToggleComplete]
///     (marking the reminder as done / undone; the row grays out
///     in the done state)
///   * a trailing calendar-icon button that triggers [onAddToCalendar]
///   * a left swipe that triggers [onDelete] and shows a [SnackBar]
class ReminderListItem extends StatelessWidget {
  const ReminderListItem({
    super.key,
    required this.reminder,
    required this.onTap,
    required this.onDelete,
    required this.onAddToCalendar,
    required this.onToggleComplete,
  });

  final Reminder reminder;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onAddToCalendar;
  final VoidCallback onToggleComplete;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final completed = reminder.isCompleted;
    // The completed style uses explicit color overrides (not
    // `Opacity`) so the trailing calendar button stays vibrant
    // and tappable. The leading icon and the title/subtitle
    // desaturate; the tag chip (if any) keeps its tag color so
    // the user can still tell at a glance which category the
    // completed row belonged to.
    final titleColor = completed ? colors.onSurfaceVariant : colors.onSurface;
    final subtitleColor = completed ? colors.outline : colors.onSurfaceVariant;
    final titleDecoration = completed
        ? TextDecoration.lineThrough
        : TextDecoration.none;

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
        leading: _CompleteButton(
          completed: completed,
          onPressed: onToggleComplete,
        ),
        title: Text(
          reminder.title,
          style: textTheme.titleMedium?.copyWith(
            color: titleColor,
            decoration: titleDecoration,
            decorationColor: titleColor,
          ),
        ),
        subtitle: Row(
          children: <Widget>[
            Flexible(
              child: Text(
                formatDateTime(reminder.reminderTime),
                style: textTheme.bodySmall?.copyWith(color: subtitleColor),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            _ReminderTagChip(reminder: reminder),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.event_available_outlined),
          tooltip: '加入日历',
          onPressed: onAddToCalendar,
        ),
      ),
    );
  }
}

/// Round IconButton used in the leading slot. Filled when the
/// reminder is complete, outlined otherwise. Tinted with the
/// primary color so it stays visually distinct from the tag chip
/// rendered next to the date.
class _CompleteButton extends StatelessWidget {
  const _CompleteButton({required this.completed, required this.onPressed});

  final bool completed;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return IconButton(
      icon: Icon(
        completed ? Icons.check_circle : Icons.check_circle_outline,
        color: completed ? colors.primary : colors.outline,
      ),
      tooltip: completed ? '标记为未完成' : '标记为已完成',
      onPressed: onPressed,
    );
  }
}

/// Inline tag chip rendered on the row's subtitle. Resolves the
/// reminder's [Reminder.tagId] through the [TagsViewModel]; renders
/// nothing when the reminder has no tag (e.g. a pre-v5 row that
/// never got one) or when the id no longer maps to a known tag
/// (e.g. the user deleted the tag from settings). The lookup is
/// intentionally defensive: a stale id should not crash the list.
class _ReminderTagChip extends StatelessWidget {
  const _ReminderTagChip({required this.reminder});

  final Reminder reminder;

  @override
  Widget build(BuildContext context) {
    final tagId = reminder.tagId;
    if (tagId == null) return const SizedBox.shrink();
    // `context.read` (no listen) keeps the row from rebuilding on
    // every tag mutation. The parent `Consumer<RemindersViewModel>`
    // already rebuilds the list whenever the row itself changes
    // (e.g. tag assigned from the editor), so the chip picks up
    // the latest name / color in the same frame. A rename from
    // the settings subpage surfaces when the user navigates back,
    // which is acceptable for v1.
    final tagsVm = context.read<TagsViewModel>();
    final tags = tagsVm.tags;
    Tag? match;
    for (final t in tags) {
      if (t.id == tagId) {
        match = t;
        break;
      }
    }
    if (match == null) return const SizedBox.shrink();
    // For the "已完成" pseudo-tag we render the same name but use
    // a more neutral color so the row doesn't advertise a category
    // the user never picked. The Tag itself carries a grey color
    // already, so no extra branch is needed.
    return TagChip(tag: match, compact: true);
  }
}
