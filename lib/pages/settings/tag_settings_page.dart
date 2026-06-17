import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:nousmind/models/tag.dart';
import 'package:nousmind/services/tag_repository.dart';
import 'package:nousmind/utils/snackbar_x.dart';
import 'package:nousmind/viewmodels/tags_view_model.dart';
import 'package:nousmind/widgets/color_dot.dart';
import 'package:nousmind/widgets/settings_section.dart';
import 'package:nousmind/widgets/tag_chip.dart';

/// Settings subpage for managing the user's tags. Renders two
/// groups:
///   * "内置标签" — read-only rows for the four default tags plus
///     the `已完成` pseudo-tag. The settings subpage exists mainly
///     to surface them as discoverable; the rest of the app shows
///     them inline.
///   * "自定义标签" — editable rows for the user's custom tags.
///     Tap a row to rename / recolor; the trailing delete button
///     (or long-press) attempts to delete with a confirm dialog.
///     The trailing `+` FAB opens the add-tag dialog. The button
///     is disabled with a tooltip when [TagsViewModel.customCount]
///     reaches [TagsViewModel.customTagCap].
class TagSettingsPage extends StatelessWidget {
  const TagSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('标签')),
      body: SafeArea(
        child: Consumer<TagsViewModel>(
          builder: (context, vm, _) {
            if (!vm.isLoaded) {
              return const Center(child: CircularProgressIndicator());
            }
            final builtins = vm.tags
                .where((t) => t.builtIn)
                .toList(growable: false);
            final customs = vm.tags
                .where((t) => !t.builtIn)
                .toList(growable: false);
            return ListView(
              children: <Widget>[
                SettingsSection(
                  title: '内置标签',
                  icon: Icons.bookmark_outline,
                  children: <Widget>[
                    for (final tag in builtins) _BuiltInTagRow(tag: tag),
                  ],
                ),
                SettingsSection(
                  title: '自定义标签',
                  icon: Icons.label_outline,
                  children: <Widget>[
                    if (customs.isEmpty)
                      const SettingsTile(
                        title: '还没有自定义标签',
                        subtitle: '点击右下角 + 添加',
                      )
                    else
                      for (final tag in customs) _CustomTagRow(tag: tag),
                  ],
                ),
                const SizedBox(height: 80),
              ],
            );
          },
        ),
      ),
      floatingActionButton: Consumer<TagsViewModel>(
        builder: (context, vm, _) {
          final atCap = vm.customCount >= TagsViewModel.customTagCap;
          return FloatingActionButton.extended(
            heroTag: 'tags-fab',
            tooltip: atCap ? '自定义标签最多 ${TagsViewModel.customTagCap} 个' : '添加标签',
            onPressed: atCap ? null : () => _showAddDialog(context, vm),
            icon: const Icon(Icons.add),
            label: const Text('添加标签'),
          );
        },
      ),
    );
  }

  Future<void> _showAddDialog(BuildContext context, TagsViewModel vm) async {
    final result = await showDialog<_TagEditResult>(
      context: context,
      builder: (_) => const _TagEditDialog(),
    );
    if (result == null) return;
    final created = await vm.add(name: result.name, color: result.color);
    if (created == null) {
      if (context.mounted) {
        context.showAppSnackBar('添加失败：名称重复或已达上限');
      }
    }
  }
}

/// Read-only row for a built-in tag. Shows the [ColorDot], name, and
/// a small `内置` chip. There is no tap target and no delete
/// affordance.
class _BuiltInTagRow extends StatelessWidget {
  const _BuiltInTagRow({required this.tag});

  final Tag tag;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      leading: ColorDot(color: Color(tag.color)),
      title: Text(tag.name),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          '内置',
          style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
        ),
      ),
    );
  }
}

/// Editable row for a custom tag. Tap to rename / recolor; the
/// trailing `×` button triggers a confirm-and-delete.
class _CustomTagRow extends StatelessWidget {
  const _CustomTagRow({required this.tag});

  final Tag tag;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: ColorDot(color: Color(tag.color)),
      title: Text(tag.name),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: '编辑',
            onPressed: () => _showEditDialog(context, tag),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '删除',
            onPressed: () => _confirmDelete(context, tag),
          ),
        ],
      ),
      onTap: () => _showEditDialog(context, tag),
    );
  }

  Future<void> _showEditDialog(BuildContext context, Tag tag) async {
    final vm = context.read<TagsViewModel>();
    final result = await showDialog<_TagEditResult>(
      context: context,
      builder: (_) => _TagEditDialog(initial: tag),
    );
    if (result == null) return;
    if (result.name != tag.name) {
      await vm.rename(tag.id, result.name);
    }
    if (result.color != tag.color) {
      await vm.recolor(tag.id, result.color);
    }
  }

  Future<void> _confirmDelete(BuildContext context, Tag tag) async {
    final vm = context.read<TagsViewModel>();
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除标签'),
        content: Text('确定要删除「${tag.name}」吗？'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await vm.deleteCustom(tag.id);
    } on TagInUseException {
      messenger.showAppSnackBar('该标签正在被使用，无法删除');
    } on Exception {
      messenger.showAppSnackBar('删除失败，请稍后重试');
    }
  }
}

/// Dialog used for both add and edit. Returns a [_TagEditResult]
/// with the chosen name + color, or `null` when dismissed.
class _TagEditDialog extends StatefulWidget {
  const _TagEditDialog({this.initial});

  final Tag? initial;

  @override
  State<_TagEditDialog> createState() => _TagEditDialogState();
}

class _TagEditDialogState extends State<_TagEditDialog> {
  late final TextEditingController _nameController;
  late int _color;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initial?.name ?? '');
    _nameController.addListener(_onNameChanged);
    _color = widget.initial?.color ?? kTagPalette.first;
  }

  @override
  void dispose() {
    _nameController.removeListener(_onNameChanged);
    _nameController.dispose();
    super.dispose();
  }

  void _onNameChanged() {
    setState(() {});
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(_TagEditResult(name: name, color: _color));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? '添加标签' : '编辑标签'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TextField(
            controller: _nameController,
            autofocus: true,
            maxLength: 12,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: '名称',
              border: OutlineInputBorder(),
              counterText: '',
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 16),
          const Text('选择颜色'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final color in kTagPalette)
                _ColorSwatch(
                  color: color,
                  selected: color == _color,
                  onTap: () => setState(() => _color = color),
                ),
            ],
          ),
          const SizedBox(height: 16),
          // Live preview so the user sees how the chip will look in
          // the list / editor before confirming.
          Row(
            children: <Widget>[
              const Text('预览：'),
              const SizedBox(width: 8),
              TagChip(
                tag: Tag(
                  id: 'preview',
                  name: _nameController.text.isEmpty
                      ? '示例'
                      : _nameController.text,
                  color: _color,
                ),
              ),
            ],
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('保存')),
      ],
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final int color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Color(color),
          shape: BoxShape.circle,
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Colors.black26,
            width: selected ? 3 : 1,
          ),
        ),
        child: selected
            ? const Icon(Icons.check, color: Colors.white, size: 18)
            : null,
      ),
    );
  }
}

class _TagEditResult {
  const _TagEditResult({required this.name, required this.color});

  final String name;
  final int color;
}
