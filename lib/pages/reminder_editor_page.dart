import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'package:nousmind/models/reminder.dart';
import 'package:nousmind/models/reminder_draft.dart';
import 'package:nousmind/models/tag.dart';
import 'package:nousmind/services/ai_analyzer.dart';
import 'package:nousmind/services/ai_usage_guard.dart';
import 'package:nousmind/services/inspiration_image_store.dart';
import 'package:nousmind/utils/date_format.dart';
import 'package:nousmind/utils/snackbar_x.dart';
import 'package:nousmind/utils/timezone_fallback.dart';
import 'package:nousmind/viewmodels/reminder_ai_adjust_controller.dart';
import 'package:nousmind/viewmodels/reminders_view_model.dart';
import 'package:nousmind/viewmodels/settings_view_model.dart';
import 'package:nousmind/viewmodels/tags_view_model.dart';
import 'package:nousmind/widgets/image_preview.dart';
import 'package:nousmind/widgets/image_preview_screen.dart';
import 'package:nousmind/widgets/tag_chip.dart';
import 'package:nousmind/widgets/tag_filter_sheet.dart';

/// Page used for both creating a new reminder and editing an existing one.
///
/// When [initial] is null the page is in "add" mode; otherwise it pre-fills
/// the form.
class ReminderEditorPage extends StatefulWidget {
  const ReminderEditorPage({super.key, this.initial, this.initialImagePath});

  final Reminder? initial;
  final String? initialImagePath;

  bool get isEditing => initial != null;

  @override
  State<ReminderEditorPage> createState() => _ReminderEditorPageState();
}

class _ReminderEditorPageState extends State<ReminderEditorPage> {
  final _formKey = GlobalKey<FormState>();
  final ImagePicker _picker = ImagePicker();
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late DateTime _reminderTime;

  String? _imagePath;
  bool _picking = false;
  int _aiPressCount = 0;
  Timer? _aiPressTimer;
  String _timezone = 'UTC';

  /// Currently selected tag id for this reminder. Initialised from
  /// the existing reminder when editing; `null` for new reminders
  /// until the user (or the AI) picks one. Never set to
  /// [kCompletedTagId] from the editor — the row's complete button
  /// is the only path to "已完成".
  String? _tagId;

  /// Reference to the AI flow controller supplied by the local
  /// [ChangeNotifierProvider] in [build]. The state's own `context`
  /// sits *above* that provider, so [_AiControllerScope] hands the
  /// controller back via a callback during its
  /// `didChangeDependencies`. The field is kept for use by
  /// [_runAiAdjust] and [_handleAiEvent], which run in callbacks
  /// without a guaranteed [BuildContext].
  ReminderAiAdjustController? _aiController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initial?.title ?? '');
    _descriptionController = TextEditingController(
      text: widget.initial?.description ?? '',
    );
    _reminderTime = widget.initial?.reminderTime ?? _defaultTime();
    _imagePath = widget.initial?.imagePath ?? widget.initialImagePath;
    final initialTag = widget.initial?.tagId;
    // Don't show the "已完成" pseudo-tag in the editor — that
    // category is set by the row's complete button, not by manual
    // editing. Clearing it on open means re-saving the row
    // doesn't accidentally re-mark it as done.
    _tagId = (initialTag != null && initialTag != kCompletedTagId)
        ? initialTag
        : null;
    _resolveTimezone();

    if (widget.initialImagePath != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _runAiAdjust();
      });
    }
  }

  @override
  void didUpdateWidget(ReminderEditorPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialImagePath != null &&
        widget.initialImagePath != oldWidget.initialImagePath) {
      setState(() {
        _titleController.clear();
        _descriptionController.clear();
        _reminderTime = _defaultTime();
        _imagePath = widget.initialImagePath;
        _tagId = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _runAiAdjust();
      });
    }
  }

  @override
  void dispose() {
    _aiController = null;
    _titleController.dispose();
    _descriptionController.dispose();
    _aiPressTimer?.cancel();
    super.dispose();
  }

  static DateTime _defaultTime() {
    final now = DateTime.now();
    final base = DateTime(now.year, now.month, now.day, now.hour, 0);
    return now.minute <= 30
        ? base.add(const Duration(minutes: 30))
        : base.add(const Duration(hours: 1));
  }

  Future<void> _pickImage(ImageSource source) async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final file = await _picker.pickImage(
        source: source,
        maxWidth: 2048,
        imageQuality: 85,
      );
      if (!mounted) return;
      if (file != null) {
        setState(() => _imagePath = file.path);
      }
    } on PlatformException catch (error, stackTrace) {
      developer.log('Image pick failed', error: error, stackTrace: stackTrace);
      if (!mounted) return;
      context.showAppSnackBar('获取图片失败');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  void _removeImage() {
    setState(() => _imagePath = null);
  }

  /// Hero tag for the editor's image. Uses the persisted id when
  /// editing, otherwise fingerprints the current path so the tag
  /// changes if the user picks a new image.
  String _imageHeroTag() {
    final id = widget.initial?.id;
    return id != null
        ? 'editor-image:$id'
        : 'editor-image:new-${_imagePath.hashCode}';
  }

  void _openImagePreview() {
    if (_imagePath == null) return;
    Navigator.of(context, rootNavigator: true).push(
      openImagePreviewRoute(imagePath: _imagePath!, heroTag: _imageHeroTag()),
    );
  }

  Future<void> _resolveTimezone() async {
    try {
      final timezoneId = await getSafeLocalTimezone();
      if (!mounted) return;
      setState(() {
        _timezone = timezoneId;
      });
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Failed to read local timezone; falling back to UTC',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _onAiPressed() {
    _aiPressTimer?.cancel();
    if (_aiPressCount == 0) {
      setState(() => _aiPressCount = 1);
      _aiPressTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _aiPressCount = 0);
      });
    } else {
      _aiPressCount = 0;
      _aiPressTimer = null;
      _runAiAdjust();
    }
  }

  /// Thin wrapper that hands the current form snapshot to
  /// [ReminderAiAdjustController.adjust]. Every branch decision
  /// (pre-flight checks, confirm dialog, single vs multi, success vs
  /// error) lives in the controller and is delivered back as
  /// [AiAdjustEvent]s handled in [_handleAiEvent].
  Future<void> _runAiAdjust() async {
    final controller = _aiController;
    if (controller == null) return;
    // Pass the current tag list (minus the "已完成" pseudo-tag,
    // which is the AI's own completion signal and should not be a
    // pickable option in the prompt's catalogue) so the model can
    // pick a real category. The parser validates the returned id
    // against this set, so a hallucination is dropped silently.
    final tagsVm = context.read<TagsViewModel>();
    final availableTags = <({String id, String name})>[
      for (final t in tagsVm.tags)
        if (t.id != kCompletedTagId) (id: t.id, name: t.name),
    ];
    await controller.adjust(
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim(),
      reminderTime: _reminderTime,
      imagePath: _imagePath,
      timezone: _timezone,
      availableTags: availableTags,
      skipConfirm: widget.initialImagePath != null,
    );
  }

  /// Translates each [AiAdjustEvent] into the matching Flutter
  /// primitive. Mounted checks after every `await` keep the editor
  /// from touching `BuildContext` after the page has been disposed.
  Future<void> _handleAiEvent(AiAdjustEvent event) async {
    if (!mounted) return;
    switch (event) {
      case ShowSnackBarEvent(:final message):
        context.showAppSnackBar(message);
      case ApplyDraftEvent(
        :final title,
        :final description,
        :final reminderTime,
        :final tagId,
      ):
        setState(() {
          _titleController.text = title;
          if (description != null && description.isNotEmpty) {
            _descriptionController.text = description;
          }
          _reminderTime = reminderTime;
          // Only overwrite the form's tag if the AI picked one. A
          // null tagId means "no category" and we leave the
          // user's existing choice alone.
          if (tagId != null) {
            _tagId = tagId;
          }
        });
      case PopEvent():
        context.pop();
      case ShowConfirmDialogEvent(:final quotaLine):
        final result = await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title: const Text('确认调用 AI'),
              content: Text(quotaLine),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('调用 AI'),
                ),
              ],
            );
          },
        );
        if (!mounted) return;
        _aiController?.onConfirmDialogResult(result ?? false);
      case ShowBatchSheetEvent(:final drafts):
        final selected = await showModalBottomSheet<List<int>>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          builder: (_) => _BatchConfirmSheet(drafts: drafts),
        );
        if (!mounted) return;
        _aiController?.onBatchSheetResult(selected);
    }
  }

  Widget _buildAiButton() {
    // The per-page [ChangeNotifierProvider] in [build] is below
    // this state, so the state's outer `context` cannot see the
    // controller. Wrap in a [Consumer] so the builder's own context
    // has the controller as an ancestor — also scopes the
    // `notifyListeners` rebuild to just the AI button instead of
    // the whole Scaffold.
    return Consumer<ReminderAiAdjustController>(
      builder: (context, controller, _) {
        final settings = context.watch<SettingsViewModel>().settings;
        final isAnalyzing = controller.isAnalyzing;
        final canUseAi =
            settings.aiAssistantEnabled &&
            (settings.aiApiKey?.trim().isNotEmpty ?? false);
        if (!canUseAi) {
          return const IconButton(
            icon: Icon(Icons.auto_awesome),
            tooltip: '请先在设置中启用 AI 助手',
            onPressed: null,
          );
        }
        if (isAnalyzing) {
          return const Padding(
            padding: EdgeInsets.all(12),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        final colors = Theme.of(context).colorScheme;
        return IconButton(
          icon: Icon(
            Icons.auto_awesome,
            color: _aiPressCount > 0 ? colors.primary : null,
          ),
          tooltip: _aiPressCount > 0 ? '再按一次以 AI 分析' : 'AI 自动调整',
          onPressed: _onAiPressed,
        );
      },
    );
  }

  Future<void> _pickDateTime() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _reminderTime,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (pickedDate == null || !mounted) return;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_reminderTime),
    );
    if (pickedTime == null) return;
    setState(() {
      _reminderTime = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
    });
  }

  /// Opens the tag picker sheet. Resolves the "+ 新建标签" path
  /// inline: pops a [Tag] and the editor stores the new id. The
  /// `__completed__` id is filtered out at the sheet level, but a
  /// defensive `null` check here is cheap insurance.
  Future<void> _pickTag() async {
    final tagsVm = context.read<TagsViewModel>();
    final tags = tagsVm.tags
        .where((t) => t.id != kCompletedTagId)
        .toList(growable: false);
    final selected = await TagFilterSheet.show(
      context,
      selectedTagId: _tagId,
      tags: tags,
      allowCreateNew: true,
      title: '选择标签',
    );
    if (!mounted) return;
    if (selected == null) {
      // Dismissed — do nothing, keep current tag selection
      return;
    }
    if (selected == TagFilterSheet.allTagsSentinel) {
      if (_tagId != null) setState(() => _tagId = null);
      return;
    }
    if (selected == TagFilterSheet.createNewSentinel) {
      // Open the add dialog inline. We reuse the dialog from the
      // tag settings page by going through the view model — the
      // settings subpage owns the dialog widget, but the public
      // `add()` method is enough to add a tag without navigating
      // away. The user gets the same color palette via a quick
      // AlertDialog (see [_showAddTagDialog] below).
      final created = await _showAddTagDialog();
      if (created == null || !mounted) return;
      setState(() => _tagId = created.id);
      return;
    }
    setState(() => _tagId = selected);
  }

  void _clearTag() {
    if (_tagId == null) return;
    setState(() => _tagId = null);
  }

  /// Inline "add a tag" dialog for the editor's "+ 新建标签" path.
  /// Kept simple: a text field and the same color palette as the
  /// settings subpage. The palette is duplicated here to avoid a
  /// wider refactor of the settings page (which owns its own
  /// dialog with the same palette); the two are kept in sync via
  /// the shared `kTagPalette` constant.
  Future<Tag?> _showAddTagDialog() async {
    final tagsVm = context.read<TagsViewModel>();
    final nameController = TextEditingController();
    int color = kTagPalette.first;
    final result = await showDialog<dynamic>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            scrollable: true,
            title: const Text('新建标签'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                TextField(
                  controller: nameController,
                  autofocus: true,
                  maxLength: 12,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: '名称',
                    border: OutlineInputBorder(),
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (final c in kTagPalette)
                      GestureDetector(
                        onTap: () => setLocal(() => color = c),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: Color(c),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: color == c
                                  ? Theme.of(ctx).colorScheme.primary
                                  : Colors.black26,
                              width: color == c ? 3 : 1,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  final name = nameController.text.trim();
                  if (name.isEmpty) return;
                  // The view model returns the created tag (or
                  // null on dedup / cap). We hand the work off so
                  // all the persistence / error handling lives in
                  // one place.
                  Navigator.of(ctx).pop(_PendingTag(name: name, color: color));
                },
                child: const Text('创建'),
              ),
            ],
          ),
        );
      },
    );
    if (result == null || result is! _PendingTag) return null;
    return tagsVm.add(name: result.name, color: result.color);
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final viewModel = context.read<RemindersViewModel>();
    final store = context.read<InspirationImageStore>();
    final title = _titleController.text.trim();
    final description = _descriptionController.text.trim();
    final time = _reminderTime;
    final existing = widget.initial;

    final previousImagePath = existing?.imagePath;
    String? newImagePath = _imagePath;

    if (newImagePath != null && newImagePath != previousImagePath) {
      final reminderId =
          existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString();
      final source = XFile(newImagePath);
      newImagePath = await store.save(
        inspirationId: reminderId,
        source: source,
      );
    }

    if (existing == null) {
      await viewModel.add(
        title: title,
        reminderTime: time,
        imagePath: newImagePath,
        description: description.isEmpty ? null : description,
        tagId: _tagId,
      );
    } else {
      // Editing a reminder that was sitting in the trash is treated
      // as an implicit restore: the user is actively engaging with
      // the row, so dropping it back into the active list is what
      // they almost certainly want. The save path therefore clears
      // the soft-delete flags; the trash page's "全部恢复" action
      // remains available for one-shot bulk restores.
      await viewModel.update(
        existing.copyWith(
          title: title,
          reminderTime: time,
          imagePath: newImagePath,
          description: description.isEmpty ? null : description,
          clearDescription: description.isEmpty,
          isDeleted: false,
          clearDeletedAt: true,
          // Preserve "已完成" if the user opens the editor on a
          // completed row but doesn't touch the tag chip — the
          // row stays in the completed bucket.
          tagId: _tagId ?? (existing.isCompleted ? existing.tagId : null),
          clearTagId: _tagId == null && !existing.isCompleted,
        ),
      );
      if (previousImagePath != null && previousImagePath != newImagePath) {
        await store.deleteByPath(previousImagePath);
      }
    }

    if (!mounted) return;
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    // The AI flow controller is local to this page so it is disposed
    // automatically when the editor closes. The state's own
    // `context` sits *above* this provider, so [_AiControllerScope]
    // — a child [StatefulWidget] — reaches the controller from its
    // own context, wires the event subscription once, and hands the
    // reference back to this state via a callback.
    return ChangeNotifierProvider<ReminderAiAdjustController>(
      create: (ctx) => ReminderAiAdjustController(
        settings: ctx.read<SettingsViewModel>(),
        guard: ctx.read<AiUsageGuard>(),
        analyzer: ctx.read<AiAnalyzer>(),
        reminderAdder: (drafts) =>
            ctx.read<RemindersViewModel>().addMultiple(drafts),
      ),
      child: _AiControllerScope(
        onController: (controller) => _aiController = controller,
        onEvent: _handleAiEvent,
        child: _buildScaffold(context),
      ),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? '编辑提醒' : '新增提醒'),
        actions: <Widget>[
          _buildAiButton(),
          TextButton(onPressed: _save, child: const Text('保存')),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              ImagePreview(
                imagePath: _imagePath,
                onRemove: _imagePath == null ? null : _removeImage,
                onTap: _imagePath == null ? null : _openImagePreview,
                heroTag: _imagePath == null ? null : _imageHeroTag(),
              ),
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _picking
                          ? null
                          : () => _pickImage(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('相册'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _picking
                          ? null
                          : () => _pickImage(ImageSource.camera),
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: const Text('拍照'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: '标题',
                  border: OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _save(),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '请输入提醒标题';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: '描述(可选)',
                  hintText: '详情、清单、备注……会显示在通知中',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                minLines: 3,
                maxLines: 8,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                maxLength: 1000,
              ),
              const SizedBox(height: 24),
              Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading: Icon(Icons.access_time, color: colors.primary),
                  title: const Text('提醒时间'),
                  subtitle: Text(formatDateTime(_reminderTime)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _pickDateTime,
                ),
              ),
              const SizedBox(height: 16),
              _TagPickerCard(
                tagId: _tagId,
                onPick: _pickTag,
                onClear: _tagId == null ? null : _clearTag,
              ),
              const SizedBox(height: 16),
              if (_picking)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: LinearProgressIndicator(color: colors.primary),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet that lets the user review and confirm multiple AI-detected
/// reminders before batch-creating them. All items are selected by default;
/// the user can deselect any they don't want.
class _BatchConfirmSheet extends StatefulWidget {
  const _BatchConfirmSheet({required this.drafts});

  final List<ReminderDraft> drafts;

  @override
  State<_BatchConfirmSheet> createState() => _BatchConfirmSheetState();
}

class _BatchConfirmSheetState extends State<_BatchConfirmSheet> {
  late final List<bool> _selected;

  @override
  void initState() {
    super.initState();
    _selected = List<bool>.filled(widget.drafts.length, true);
  }

  int get _selectedCount => _selected.where((s) => s).length;

  void _toggle(int index, bool? value) {
    setState(() => _selected[index] = value ?? false);
  }

  void _toggleAll(bool select) {
    setState(() {
      for (var i = 0; i < _selected.length; i++) {
        _selected[i] = select;
      }
    });
  }

  Future<void> _editDraft(int index) async {
    final updated = await showDialog<ReminderDraft>(
      context: context,
      builder: (ctx) => _DraftEditDialog(draft: widget.drafts[index]),
    );
    if (updated != null) {
      setState(() {
        widget.drafts[index] = updated;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final media = MediaQuery.of(context);
    final maxHeight = media.size.height * 0.6;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '检测到 ${widget.drafts.length} 条提醒',
                      style: textTheme.titleMedium,
                    ),
                  ),
                  TextButton(
                    onPressed: () =>
                        _toggleAll(_selectedCount < widget.drafts.length),
                    child: Text(
                      _selectedCount == widget.drafts.length ? '全部取消' : '全选',
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(<int>[]),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: widget.drafts.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, indent: 56),
                itemBuilder: (context, index) {
                  final draft = widget.drafts[index];
                  return _DraftTile(
                    draft: draft,
                    selected: _selected[index],
                    onChanged: (v) => _toggle(index, v),
                    onEdit: () => _editDraft(index),
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _selectedCount == 0
                      ? null
                      : () {
                          final selected = <int>[];
                          for (var i = 0; i < _selected.length; i++) {
                            if (_selected[i]) selected.add(i);
                          }
                          Navigator.of(context).pop(selected);
                        },
                  icon: const Icon(Icons.add_task),
                  label: Text('添加 $_selectedCount 项'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single row in the batch confirm sheet showing a [ReminderDraft]
/// with a checkbox, title, description snippet, and time.
class _DraftTile extends StatelessWidget {
  const _DraftTile({
    required this.draft,
    required this.selected,
    required this.onChanged,
    required this.onEdit,
  });

  final ReminderDraft draft;
  final bool selected;
  final ValueChanged<bool?> onChanged;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return InkWell(
      onTap: () => onChanged(!selected),
      onLongPress: onEdit,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Checkbox(value: selected, onChanged: onChanged),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          draft.title,
                          style: textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (draft.tagId != null) ...<Widget>[
                        const SizedBox(width: 8),
                        _DraftTagChip(tagId: draft.tagId!),
                      ],
                    ],
                  ),
                  if (draft.description != null &&
                      draft.description!.trim().isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      draft.description!.trim(),
                      style: textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 4),
                  Row(
                    children: <Widget>[
                      Icon(Icons.access_time, size: 14, color: colors.primary),
                      const SizedBox(width: 4),
                      Text(
                        formatDateTime(draft.suggestedTime),
                        style: textTheme.bodySmall,
                      ),
                      if (draft.reason != null) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            draft.reason!,
                            style: textTheme.bodySmall?.copyWith(
                              color: colors.outline,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: '编辑',
              onPressed: onEdit,
            ),
          ],
        ),
      ),
    );
  }
}

/// Renders the AI-chosen tag for a batch confirm draft. Resolves
/// the id through the [TagsViewModel] so the chip matches the
/// user's palette; falls back to nothing for hallucinated ids the
/// parser dropped, since `_DraftTile` only renders when
/// `draft.tagId != null` and the parser enforces that.
class _DraftTagChip extends StatelessWidget {
  const _DraftTagChip({required this.tagId});

  final String tagId;

  @override
  Widget build(BuildContext context) {
    final tags = context.read<TagsViewModel>().tags;
    for (final t in tags) {
      if (t.id == tagId) {
        return TagChip(tag: t, compact: true);
      }
    }
    return const SizedBox.shrink();
  }
}

/// Owns the subscription lifecycle for the per-page
/// [ReminderAiAdjustController]. Wires the controller's `events`
/// stream exactly once via [State.didChangeDependencies] (guarded)
/// and tears it down in [State.dispose]. The hosting state
/// receives the controller reference via [onController] for use
/// in callbacks that lack a guaranteed [BuildContext].
class _AiControllerScope extends StatefulWidget {
  const _AiControllerScope({
    required this.onController,
    required this.onEvent,
    required this.child,
  });

  final void Function(ReminderAiAdjustController controller) onController;
  final void Function(AiAdjustEvent event) onEvent;
  final Widget child;

  @override
  State<_AiControllerScope> createState() => _AiControllerScopeState();
}

class _AiControllerScopeState extends State<_AiControllerScope> {
  ReminderAiAdjustController? _controller;
  StreamSubscription<AiAdjustEvent>? _sub;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller == null) {
      _controller = context.read<ReminderAiAdjustController>();
      _sub = _controller!.events.listen(widget.onEvent);
      widget.onController(_controller!);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _sub = null;
    _controller = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Card used in the editor to display and edit the currently
/// selected tag. Shows the resolved [TagChip] when a tag is
/// chosen, "未分类" when none is, and a chevron that opens the
/// tag picker. The `onClear` trailing icon lets the user drop the
/// current selection without going through the sheet.
class _TagPickerCard extends StatelessWidget {
  const _TagPickerCard({
    required this.tagId,
    required this.onPick,
    required this.onClear,
  });

  final String? tagId;
  final VoidCallback onPick;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final tagsVm = context.watch<TagsViewModel>();
    Tag? match;
    if (tagId != null) {
      for (final t in tagsVm.tags) {
        if (t.id == tagId) {
          match = t;
          break;
        }
      }
    }
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(Icons.label_outline, color: colors.primary),
        title: const Text('标签'),
        subtitle: match == null
            ? Text('未分类', style: TextStyle(color: colors.onSurfaceVariant))
            : Padding(
                padding: const EdgeInsets.only(top: 4),
                child: TagChip(tag: match),
              ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (onClear != null)
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: '清除标签',
                onPressed: onClear,
              ),
            const Icon(Icons.chevron_right),
          ],
        ),
        onTap: onPick,
      ),
    );
  }
}

/// Internal sentinel returned from the inline "新建标签" dialog
/// so the editor can distinguish "user picked an existing tag"
/// (a real [Tag.id] string) from "user created a brand new tag
/// (we need to add it through the view model and then use the
/// returned id)".
class _PendingTag {
  const _PendingTag({required this.name, required this.color});
  final String name;
  final int color;
}

class _DraftEditDialog extends StatefulWidget {
  const _DraftEditDialog({required this.draft});

  final ReminderDraft draft;

  @override
  State<_DraftEditDialog> createState() => _DraftEditDialogState();
}

class _DraftEditDialogState extends State<_DraftEditDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late DateTime _suggestedTime;
  String? _tagId;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.draft.title);
    _descriptionController = TextEditingController(
      text: widget.draft.description ?? '',
    );
    _suggestedTime = widget.draft.suggestedTime;
    _tagId = widget.draft.tagId;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _suggestedTime,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (pickedDate == null || !mounted) return;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_suggestedTime),
    );
    if (pickedTime == null) return;
    setState(() {
      _suggestedTime = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
    });
  }

  Future<void> _pickTag() async {
    final tagsVm = context.read<TagsViewModel>();
    final tags = tagsVm.tags
        .where((t) => t.id != kCompletedTagId)
        .toList(growable: false);
    final selected = await TagFilterSheet.show(
      context,
      selectedTagId: _tagId,
      tags: tags,
      allowCreateNew: false,
      title: '选择标签',
    );
    if (!mounted) return;
    if (selected == null) {
      // Cancelled/dismissed — do nothing
      return;
    }
    if (selected == TagFilterSheet.allTagsSentinel) {
      setState(() => _tagId = null);
      return;
    }
    setState(() => _tagId = selected);
  }

  void _submit() {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;
    final desc = _descriptionController.text.trim();
    Navigator.of(context).pop(
      widget.draft.copyWith(
        title: title,
        description: desc.isEmpty ? null : desc,
        suggestedTime: _suggestedTime,
        tagId: _tagId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final tagsVm = context.watch<TagsViewModel>();
    Tag? match;
    if (_tagId != null) {
      for (final t in tagsVm.tags) {
        if (t.id == _tagId) {
          match = t;
          break;
        }
      }
    }

    return AlertDialog(
      title: const Text('编辑提醒内容'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextField(
              controller: _titleController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '标题',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: '描述(可选)',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: Icon(Icons.access_time, color: colors.primary),
                title: const Text('提醒时间'),
                subtitle: Text(formatDateTime(_suggestedTime)),
                trailing: const Icon(Icons.chevron_right),
                onTap: _pickDateTime,
              ),
            ),
            const SizedBox(height: 16),
            Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: Icon(Icons.label_outline, color: colors.primary),
                title: const Text('标签'),
                subtitle: match == null
                    ? Text(
                        '未分类',
                        style: TextStyle(color: colors.onSurfaceVariant),
                      )
                    : Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: TagChip(tag: match),
                      ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _pickTag,
              ),
            ),
          ],
        ),
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
