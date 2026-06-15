import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/reminder_draft.dart';
import '../viewmodels/ai_assist_view_model.dart';
import '../viewmodels/reminders_view_model.dart';
import '../viewmodels/settings_view_model.dart';
import '../widgets/image_preview.dart';

/// Full-screen page that takes free-form text and/or a screenshot,
/// dispatches it to the [AiAssistViewModel], and lets the user review,
/// edit, and bulk-save the returned [ReminderDraft] candidates.
class AiAssistantPage extends StatefulWidget {
  const AiAssistantPage({super.key});

  @override
  State<AiAssistantPage> createState() => _AiAssistantPageState();
}

class _AiAssistantPageState extends State<AiAssistantPage> {
  final TextEditingController _textController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  String? _imagePath;
  String _timezone = 'UTC';
  bool _picking = false;
  bool _tzResolved = false;

  @override
  void initState() {
    super.initState();
    _resolveTimezone();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AiAssistViewModel>().reset();
    });
  }

  Future<void> _resolveTimezone() async {
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      if (!mounted) return;
      setState(() {
        _timezone = info.identifier;
        _tzResolved = true;
      });
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Failed to read local timezone; falling back to UTC',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      setState(() => _tzResolved = true);
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 2048,
        imageQuality: 85,
      );
      if (!mounted) return;
      if (picked != null) {
        setState(() => _imagePath = picked.path);
      }
    } on PlatformException catch (error, stackTrace) {
      developer.log('Image pick failed', error: error, stackTrace: stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('获取图片失败')));
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  void _removeImage() => setState(() => _imagePath = null);

  Future<void> _runAnalysis() async {
    final settings = context.read<SettingsViewModel>().settings;
    final apiKey = settings.aiApiKey;
    if (!settings.aiAssistantEnabled || apiKey == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('请先在设置 → AI 助手 中启用并配置')));
      return;
    }
    final aiAssist = context.read<AiAssistViewModel>();
    if (aiAssist.isLockedDueToAuth) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('API 密钥连续失败,分析已锁定,请到设置更新密钥')),
        );
      return;
    }
    if (aiAssist.isThrottled) {
      // The throttle banner is already visible; no need to also snack.
      return;
    }
    final text = _textController.text.trim();
    if (text.isEmpty && _imagePath == null) return;
    try {
      await aiAssist.analyze(
        apiKey: apiKey,
        timezone: _timezone,
        text: text.isEmpty ? null : text,
        imagePath: _imagePath,
        now: DateTime.now(),
        systemPromptTemplate: settings.aiAssistantPrompt,
      );
    } catch (error, stackTrace) {
      developer.log(
        'AI analysis crashed in UI handler',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      aiAssist.setError('分析过程发生错误,请重试');
    }
  }

  Future<void> _saveSelected() async {
    final vm = context.read<AiAssistViewModel>();
    final selected = vm.candidates.where((c) => c.selected).toList();
    if (selected.isEmpty) return;
    final reminders = context.read<RemindersViewModel>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = GoRouter.of(context);
    await reminders.addMultiple(
      selected
          .map(
            (c) => (
              title: c.title,
              reminderTime: c.suggestedTime,
              description: c.description,
            ),
          )
          .toList(),
    );
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('已添加 ${selected.length} 项')));
    vm.reset();
    if (mounted) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI 助手')),
      body: SafeArea(
        child: Consumer<AiAssistViewModel>(
          builder: (context, vm, _) {
            switch (vm.status) {
              case AiAssistStatus.idle:
              case AiAssistStatus.analyzing:
              case AiAssistStatus.error:
                return _buildInputForm(context, vm);
              case AiAssistStatus.success:
                if (vm.isEmpty) return _buildEmptyState(context, vm);
                return _buildReviewList(context, vm);
            }
          },
        ),
      ),
    );
  }

  Widget _buildInputForm(BuildContext context, AiAssistViewModel vm) {
    final colors = Theme.of(context).colorScheme;
    final ready = context.select<SettingsViewModel, bool>(
      (s) => s.settings.aiAssistantEnabled && s.settings.aiApiKey != null,
    );
    final hasInput =
        _textController.text.trim().isNotEmpty || _imagePath != null;
    final canAnalyze =
        ready &&
        hasInput &&
        !vm.isLoading &&
        !vm.isLockedDueToAuth &&
        !vm.isThrottled;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        if (vm.isLockedDueToAuth) const _AuthLockoutBanner(),
        if (vm.isThrottled) _ThrottleBanner(viewModel: vm),
        if (!ready)
          const _MissingKeyBanner(message: '请先在 设置 → AI 助手 中启用并配置 AI 助手'),
        if (vm.status == AiAssistStatus.error && vm.errorMessage != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: <Widget>[
                  Icon(Icons.error_outline, color: colors.onErrorContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      vm.errorMessage!,
                      style: TextStyle(color: colors.onErrorContainer),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ImagePreview(
          imagePath: _imagePath,
          onRemove: _imagePath == null ? null : _removeImage,
        ),
        const SizedBox(height: 12),
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
        const SizedBox(height: 16),
        TextField(
          controller: _textController,
          minLines: 5,
          maxLines: 10,
          decoration: const InputDecoration(
            labelText: '文本',
            hintText: '粘贴聊天记录、邮件内容,或直接描述…',
            border: OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: canAnalyze ? _runAnalysis : null,
          icon: vm.isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.auto_awesome),
          label: Text(vm.isLoading ? '分析中…' : '分析'),
        ),
        if (vm.isLoading && !_tzResolved)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(
              '正在识别截图中的文字…',
              style: TextStyle(fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context, AiAssistViewModel vm) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.search_off, size: 64),
            const SizedBox(height: 12),
            const Text(
              '未识别到提醒',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text('换一张更清晰的截图或补充文字再试。', textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => vm.reset(),
              icon: const Icon(Icons.arrow_back),
              label: const Text('返回'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReviewList(BuildContext context, AiAssistViewModel vm) {
    return Column(
      children: <Widget>[
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            itemCount: vm.candidates.length,
            itemBuilder: (context, index) {
              final candidate = vm.candidates[index];
              return _CandidateRow(
                key: ValueKey(candidate.id),
                candidate: candidate,
                onToggle: (v) => vm.toggleSelected(candidate.id, v),
                onTitleChanged: (v) =>
                    vm.updateCandidate(candidate.id, title: v),
                onTimeChanged: (t) =>
                    vm.updateCandidate(candidate.id, suggestedTime: t),
                onRemove: () => vm.removeCandidate(candidate.id),
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: vm.selectedCount == 0 ? null : _saveSelected,
              icon: const Icon(Icons.add_task),
              label: Text(
                vm.selectedCount <= 1
                    ? '添加 ${vm.selectedCount} 项'
                    : '添加 ${vm.selectedCount} 项',
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// One row in the review list. Owns its own title [TextEditingController]
/// and renders the time + reason + edit-time button underneath.
class _CandidateRow extends StatefulWidget {
  const _CandidateRow({
    super.key,
    required this.candidate,
    required this.onToggle,
    required this.onTitleChanged,
    required this.onTimeChanged,
    required this.onRemove,
  });

  final ReminderDraft candidate;
  final ValueChanged<bool> onToggle;
  final ValueChanged<String> onTitleChanged;
  final ValueChanged<DateTime> onTimeChanged;
  final VoidCallback onRemove;

  @override
  State<_CandidateRow> createState() => _CandidateRowState();
}

class _CandidateRowState extends State<_CandidateRow> {
  late final TextEditingController _titleController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.candidate.title);
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _editTime() async {
    final initial = widget.candidate.suggestedTime;
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (pickedDate == null || !mounted) return;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (pickedTime == null) return;
    widget.onTimeChanged(
      DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final bodySmall = Theme.of(context).textTheme.bodySmall;
    return Dismissible(
      key: ValueKey('dismiss-${widget.candidate.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          color: colors.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(Icons.delete, color: colors.onErrorContainer),
      ),
      onDismissed: (_) => widget.onRemove(),
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Checkbox(
                    value: widget.candidate.selected,
                    onChanged: (v) => widget.onToggle(v ?? false),
                  ),
                  Expanded(
                    child: TextFormField(
                      controller: _titleController,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        hintText: '标题',
                      ),
                      onChanged: widget.onTitleChanged,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: widget.onRemove,
                  ),
                ],
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.access_time, size: 16, color: colors.primary),
                    const SizedBox(width: 6),
                    Text(
                      _formatDateTime(widget.candidate.suggestedTime),
                      style: bodySmall,
                    ),
                    const SizedBox(width: 12),
                    if (widget.candidate.reason != null)
                      Expanded(
                        child: Text(
                          widget.candidate.reason!,
                          style: bodySmall?.copyWith(color: colors.outline),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      )
                    else
                      const Spacer(),
                    TextButton.icon(
                      onPressed: _editTime,
                      icon: const Icon(Icons.edit_calendar_outlined, size: 16),
                      label: const Text('修改时间'),
                    ),
                  ],
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

class _MissingKeyBanner extends StatelessWidget {
  const _MissingKeyBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.info_outline, color: colors.onPrimaryContainer),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: const TextStyle(fontSize: 13))),
          TextButton(
            onPressed: () => GoRouter.of(context).go('/settings/ai'),
            child: const Text('去设置'),
          ),
        ],
      ),
    );
  }
}

/// Banner shown when consecutive auth failures have locked the analysis
/// flow. The lock is only lifted by updating the API key in settings.
class _AuthLockoutBanner extends StatelessWidget {
  const _AuthLockoutBanner();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.error, width: 1.5),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.lock_outline, color: colors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'API 密钥连续 ${AiAssistViewModel.authLockThreshold} 次失败,分析已锁定。请到 设置 → AI 助手 更新密钥。',
              style: TextStyle(color: colors.onErrorContainer, fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: () => GoRouter.of(context).go('/settings/ai'),
            child: const Text('去设置'),
          ),
        ],
      ),
    );
  }
}

/// Banner shown while the click throttle is active. Owns its own 1-second
/// ticker so the countdown text re-renders without depending on the
/// outer page's `setState`.
class _ThrottleBanner extends StatefulWidget {
  const _ThrottleBanner({required this.viewModel});

  final AiAssistViewModel viewModel;

  @override
  State<_ThrottleBanner> createState() => _ThrottleBannerState();
}

class _ThrottleBannerState extends State<_ThrottleBanner> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant _ThrottleBanner old) {
    super.didUpdateWidget(old);
    _syncTicker();
  }

  void _syncTicker() {
    final throttled = widget.viewModel.isThrottled;
    if (throttled && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {});
        if (!widget.viewModel.isThrottled) _syncTicker();
      });
    } else if (!throttled && _ticker != null) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.viewModel;
    if (!vm.isThrottled) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    final remaining = vm.throttleRemainingSeconds;
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.error, width: 1.5),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.warning_amber_rounded, color: colors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '严重警告:操作过于频繁,请稍候 ${remaining}s 再试',
              style: TextStyle(color: colors.onErrorContainer, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
