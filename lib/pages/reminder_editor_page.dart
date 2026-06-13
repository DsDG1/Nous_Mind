import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/reminder.dart';
import '../services/inspiration_image_store.dart';
import '../viewmodels/reminders_view_model.dart';
import '../widgets/image_preview.dart';

/// Page used for both creating a new reminder and editing an existing one.
///
/// When [initial] is null the page is in "add" mode; otherwise it pre-fills
/// the form. [prefillImagePath] is used by the screenshot tile flow to
/// supply an image before the user enters any text.
class ReminderEditorPage extends StatefulWidget {
  const ReminderEditorPage({super.key, this.initial, this.prefillImagePath});

  final Reminder? initial;
  final String? prefillImagePath;

  bool get isEditing => initial != null;

  @override
  State<ReminderEditorPage> createState() => _ReminderEditorPageState();
}

class _ReminderEditorPageState extends State<ReminderEditorPage> {
  final _formKey = GlobalKey<FormState>();
  final ImagePicker _picker = ImagePicker();
  late final TextEditingController _titleController;
  late DateTime _reminderTime;

  String? _imagePath;
  bool _picking = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initial?.title ?? '');
    _reminderTime = widget.initial?.reminderTime ?? _defaultTime();
    _imagePath = widget.initial?.imagePath ?? widget.prefillImagePath;
  }

  @override
  void dispose() {
    _titleController.dispose();
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
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('获取图片失败')));
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  void _removeImage() {
    setState(() => _imagePath = null);
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
      await viewModel.add(title: title, reminderTime: time, imagePath: newImagePath);
    } else {
      await viewModel.update(
        existing.copyWith(title: title, reminderTime: time, imagePath: newImagePath),
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
                      onPressed: _picking ? null : () => _pickImage(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('相册'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _picking ? null : () => _pickImage(ImageSource.camera),
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
