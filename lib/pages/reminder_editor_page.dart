import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/reminder.dart';
import '../services/ai_analyzer.dart';
import '../services/inspiration_image_store.dart';
import '../viewmodels/reminders_view_model.dart';
import '../viewmodels/settings_view_model.dart';
import '../widgets/ai_polish_sheet.dart';
import '../widgets/image_preview.dart';

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
  bool _isPolishing = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initial?.title ?? '');
    _descriptionController = TextEditingController(
      text: widget.initial?.description ?? '',
    );
    _reminderTime = widget.initial?.reminderTime ?? _defaultTime();
    _imagePath = widget.initial?.imagePath;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
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

  /// Invokes the AI analyzer's [AiAnalyzer.polishText] on the current
  /// description, then shows a side-by-side preview so the user can
  /// accept or reject the revision before it overwrites the field.
  /// Failures are mapped through the same [AiAnalysisException]
  /// hierarchy used by the AI assistant page, so the SnackBar copy
  /// stays consistent.
  Future<void> _onPolishPressed() async {
    if (_isPolishing) return;
    final settings = context.read<SettingsViewModel>().settings;
    if (!settings.aiAssistantEnabled) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('请先在 设置 → AI 助手 中启用 AI 助手')),
        );
      return;
    }
    final apiKey = settings.aiApiKey;
    if (apiKey == null || apiKey.trim().isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('请先在 设置 → AI 助手 中填写 API 密钥')),
        );
      return;
    }
    final original = _descriptionController.text;
    if (original.trim().isEmpty) return;

    final analyzer = context.read<AiAnalyzer>();
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _isPolishing = true);
    try {
      final polished = await analyzer.polishText(
        text: original,
        apiKey: apiKey,
      );
      if (!mounted) return;
      final accepted = await AiPolishSheet.show(
        context,
        original: original,
        polished: polished,
      );
      if (accepted && mounted) {
        setState(() {
          _descriptionController.text = polished;
        });
      }
    } on AiAnalysisException catch (error) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error.message)));
    } on Exception catch (error, stackTrace) {
      developer.log('AI polish failed', error: error, stackTrace: stackTrace);
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('润色失败,请稍后重试')));
    } finally {
      if (mounted) setState(() => _isPolishing = false);
    }
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
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? '编辑提醒' : '新增提醒'),
        actions: <Widget>[
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
              Consumer<SettingsViewModel>(
                builder: (context, settingsVm, _) {
                  final settings = settingsVm.settings;
                  final canPolish =
                      settings.aiAssistantEnabled &&
                      (settings.aiApiKey?.trim().isNotEmpty ?? false);
                  return TextFormField(
                    controller: _descriptionController,
                    decoration: InputDecoration(
                      labelText: '描述(可选)',
                      hintText: '详情、清单、备注……会显示在通知中',
                      border: const OutlineInputBorder(),
                      alignLabelWithHint: true,
                      suffixIcon: canPolish
                          ? _isPolishing
                                ? const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  )
                                : IconButton(
                                    icon: const Icon(Icons.auto_fix_high),
                                    tooltip: 'AI 一键润色',
                                    onPressed: _onPolishPressed,
                                  )
                          : null,
                    ),
                    minLines: 3,
                    maxLines: 8,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    maxLength: 1000,
                  );
                },
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
