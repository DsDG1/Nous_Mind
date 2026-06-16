import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'package:nousmind/models/reminder.dart';
import 'package:nousmind/models/reminder_draft.dart';
import 'package:nousmind/services/ai_analyzer.dart';
import 'package:nousmind/services/ai_usage_guard.dart';
import 'package:nousmind/services/inspiration_image_store.dart';
import 'package:nousmind/viewmodels/reminder_ai_adjust_controller.dart';
import 'package:nousmind/viewmodels/reminders_view_model.dart';
import 'package:nousmind/viewmodels/settings_view_model.dart';
import 'package:nousmind/widgets/image_preview.dart';
import 'package:nousmind/widgets/image_preview_screen.dart';

/// Page used for both creating a new reminder and editing an existing one.
///
/// When [initial] is null the page is in "add" mode; otherwise it pre-fills
/// the form.
class ReminderEditorPage extends StatefulWidget {
  const ReminderEditorPage({super.key, this.initial});

  final Reminder? initial;

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
    _imagePath = widget.initial?.imagePath;
    _resolveTimezone();
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('获取图片失败')));
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
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (_, _, _) => ImagePreviewScreen(
          imagePath: _imagePath!,
          heroTag: _imageHeroTag(),
        ),
      ),
    );
  }

  Future<void> _resolveTimezone() async {
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      if (!mounted) return;
      setState(() {
        _timezone = info.identifier;
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
    await controller.adjust(
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim(),
      reminderTime: _reminderTime,
      imagePath: _imagePath,
      timezone: _timezone,
    );
  }

  /// Translates each [AiAdjustEvent] into the matching Flutter
  /// primitive. Mounted checks after every `await` keep the editor
  /// from touching `BuildContext` after the page has been disposed.
  Future<void> _handleAiEvent(AiAdjustEvent event) async {
    if (!mounted) return;
    switch (event) {
      case ShowSnackBarEvent(:final message):
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(message)));
      case ApplyDraftEvent(
        :final title,
        :final description,
        :final reminderTime,
      ):
        setState(() {
          _titleController.text = title;
          if (description != null && description.isNotEmpty) {
            _descriptionController.text = description;
          }
          _reminderTime = reminderTime;
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
                  subtitle: Text(_formatDateTime(_reminderTime)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _pickDateTime,
                ),
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

  static String _formatDateTime(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}';
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
  });

  final ReminderDraft draft;
  final bool selected;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return InkWell(
      onTap: () => onChanged(!selected),
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
                  Text(
                    draft.title,
                    style: textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
                        _formatDateTime(draft.suggestedTime),
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
          ],
        ),
      ),
    );
  }

  static String _formatDateTime(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}';
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
