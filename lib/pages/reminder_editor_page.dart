import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/reminder.dart';
import '../viewmodels/reminders_view_model.dart';

/// Page used for both creating a new reminder and editing an existing one.
///
/// When [initial] is null the page is in "add" mode; otherwise it pre-fills
/// the form with the values of [initial] and updates that reminder on save.
/// Save mutates the [RemindersViewModel] directly and pops without a value;
/// the caller only needs to `context.push('/editor', extra: existing)` and
/// then observe the view model.
class ReminderEditorPage extends StatefulWidget {
  const ReminderEditorPage({super.key, this.initial});

  final Reminder? initial;

  bool get isEditing => initial != null;

  @override
  State<ReminderEditorPage> createState() => _ReminderEditorPageState();
}

class _ReminderEditorPageState extends State<ReminderEditorPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late DateTime _reminderTime;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initial?.title ?? '');
    _reminderTime = widget.initial?.reminderTime ?? _defaultTime();
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  /// Default to "now rounded up to the next half hour" so a new reminder
  /// lands on a sensible time instead of whenever the user tapped the FAB.
  static DateTime _defaultTime() {
    final now = DateTime.now();
    final base = DateTime(now.year, now.month, now.day, now.hour, 0);
    return now.minute <= 30
        ? base.add(const Duration(minutes: 30))
        : base.add(const Duration(hours: 1));
  }

  Future<void> _pickDateTime() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _reminderTime,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (pickedDate == null || !mounted) {
      return;
    }
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_reminderTime),
    );
    if (pickedTime == null) {
      return;
    }
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

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final viewModel = context.read<RemindersViewModel>();
    final title = _titleController.text.trim();
    final time = _reminderTime;
    final existing = widget.initial;
    if (existing == null) {
      viewModel.add(title: title, reminderTime: time);
    } else {
      viewModel.update(existing.copyWith(title: title, reminderTime: time));
    }
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
