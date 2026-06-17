import 'package:flutter/material.dart';

import 'package:nousmind/models/tag.dart';
import 'package:nousmind/widgets/tag_chip.dart';

/// Reusable bottom sheet that lets the user pick a tag (or "全部",
/// or the `已完成` pseudo-tag) to filter or assign. Same widget is
/// used by:
///   * the home page's filter icon (with [allowCreateNew] = false
///     so the sheet is read-only — the user goes to the settings
///     subpage to manage tags)
///   * the reminder editor's "更改标签" tile (with [allowCreateNew]
///     = true so a "+ 新建标签" tile appears at the bottom; the
///     editor route handles the actual creation flow)
class TagFilterSheet extends StatelessWidget {
  const TagFilterSheet({
    super.key,
    required this.selectedTagId,
    required this.tags,
    this.allowCreateNew = false,
    this.title = '筛选标签',
  });

  /// Currently-applied selection. `null` means "全部". The
  /// `已完成` id is also accepted.
  final String? selectedTagId;

  /// Tags to render in the sheet. The home page passes every
  /// available tag; the editor passes the same (so users can
  /// pick a default tag, not just custom ones).
  final List<Tag> tags;

  /// When `true`, a "+ 新建标签" tile is appended at the bottom.
  /// Tapping it returns a special sentinel value via the static
  /// [show] so the caller can open its own create-tag flow.
  final bool allowCreateNew;

  final String title;

  /// Sentinel returned by [show] when the user picks "+ 新建标签".
  /// Callers should compare with `==` and route into their
  /// own creation UI.
  static const String createNewSentinel = '__create_new__';

  /// Sentinel returned by [show] when the user picks "全部" (All).
  /// Callers should compare with this sentinel to distinguish selecting
  /// "全部" from dismissing the sheet (which returns null).
  static const String allTagsSentinel = '__all_tags__';

  /// Convenience wrapper that pushes the sheet and returns the
  /// chosen tag id (or [allTagsSentinel] for "全部", or
  /// [createNewSentinel] for "+ 新建标签"). The caller handles
  /// dismissal (outside tap, drag, X button) as `null`.
  static Future<String?> show(
    BuildContext context, {
    required String? selectedTagId,
    required List<Tag> tags,
    bool allowCreateNew = false,
    String title = '筛选标签',
  }) {
    return showModalBottomSheet<String?>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => TagFilterSheet(
        selectedTagId: selectedTagId,
        tags: tags,
        allowCreateNew: allowCreateNew,
        title: title,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Row(
              children: <Widget>[
                Expanded(child: Text(title, style: textTheme.titleMedium)),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: '关闭',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: <Widget>[
                _TagRow(
                  leading: Icon(Icons.inbox_outlined, color: colors.primary),
                  title: '全部',
                  selected: selectedTagId == null,
                  onTap: () => Navigator.of(context).pop(allTagsSentinel),
                ),
                for (final tag in tags)
                  _TagRow(
                    leading: TagChip(tag: tag, compact: true),
                    title: tag.name,
                    selected: selectedTagId == tag.id,
                    onTap: () => Navigator.of(context).pop(tag.id),
                  ),
                if (allowCreateNew) ...<Widget>[
                  const Divider(height: 1),
                  ListTile(
                    leading: Icon(
                      Icons.add_circle_outline,
                      color: colors.primary,
                    ),
                    title: const Text('新建标签'),
                    onTap: () => Navigator.of(context).pop(createNewSentinel),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TagRow extends StatelessWidget {
  const _TagRow({
    required this.leading,
    required this.title,
    required this.selected,
    required this.onTap,
  });

  final Widget leading;
  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      leading: leading,
      title: Text(title),
      trailing: selected
          ? Icon(Icons.check, color: colors.primary)
          : const SizedBox.shrink(),
      onTap: onTap,
    );
  }
}
