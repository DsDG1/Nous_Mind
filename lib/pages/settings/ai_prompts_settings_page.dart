import 'package:flutter/material.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:provider/provider.dart';

import 'package:nousmind/services/ai_analyzer.dart';
import 'package:nousmind/utils/snackbar_x.dart';
import 'package:nousmind/viewmodels/settings_view_model.dart';
import 'package:nousmind/widgets/settings_section.dart';

/// Settings subpage for editing the system prompts used by the AI
/// surfaces (error analysis, reminder adjustment). Each field shows
/// the built-in default when nothing is stored. Leaving a field empty
/// saves `null`, which makes [AiAnalyzer] fall back to its hard-coded
/// default at call time. The adjustment prompt supports runtime
/// placeholders that are substituted by
/// [DeepSeekAnalyzer.renderAssistantPrompt].
class AiPromptsSettingsPage extends StatefulWidget {
  const AiPromptsSettingsPage({super.key});

  @override
  State<AiPromptsSettingsPage> createState() => _AiPromptsSettingsPageState();
}

class _AiPromptsSettingsPageState extends State<AiPromptsSettingsPage> {
  late final TextEditingController _errorAnalysisController;
  late final TextEditingController _adjustController;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsViewModel>().settings;
    _errorAnalysisController = TextEditingController(
      text:
          settings.aiErrorAnalysisPrompt ??
          DeepSeekAnalyzer.defaultErrorAnalysisPrompt,
    );
    _adjustController = TextEditingController(
      text:
          settings.aiAdjustPrompt ??
          DeepSeekAnalyzer.defaultAdjustPromptTemplate,
    );
  }

  @override
  void dispose() {
    _errorAnalysisController.dispose();
    _adjustController.dispose();
    super.dispose();
  }

  Future<void> _saveErrorAnalysis(SettingsViewModel vm) =>
      _saveFor(vm.setAiErrorAnalysisPrompt, _errorAnalysisController.text);
  Future<void> _saveAdjust(SettingsViewModel vm) =>
      _saveFor(vm.setAiAdjustPrompt, _adjustController.text);

  Future<void> _saveFor(
    Future<void> Function(String?) setter,
    String value,
  ) async {
    await setter(value);
    if (!mounted) return;
    context.showAppSnackBar('已保存');
  }

  /// Pops a read-only dialog showing how the placeholder values will
  /// be substituted when the prompt is actually sent to the model.
  /// Lets the user eyeball the rendered text before saving — useful
  /// because a typo in `{{tomorrow}}` looks identical to the literal
  /// characters on the editor surface.
  Future<void> _previewAdjust() async {
    final template = _adjustController.text.trim().isEmpty
        ? DeepSeekAnalyzer.defaultAdjustPromptTemplate
        : _adjustController.text;
    final timezone = await _resolveTimezone();
    if (!mounted) return;
    final rendered = DeepSeekAnalyzer.renderAssistantPrompt(
      template: template,
      timezone: timezone,
      now: DateTime.now(),
    );
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('渲染预览'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: SelectableText(
                rendered,
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }

  Future<String> _resolveTimezone() async {
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      return info.identifier;
    } on Exception {
      return 'UTC';
    }
  }

  Future<void> _resetErrorAnalysis(SettingsViewModel vm) async {
    _errorAnalysisController.text = DeepSeekAnalyzer.defaultErrorAnalysisPrompt;
    await vm.setAiErrorAnalysisPrompt(null);
    _notifyReset();
  }

  Future<void> _resetAdjust(SettingsViewModel vm) async {
    _adjustController.text = DeepSeekAnalyzer.defaultAdjustPromptTemplate;
    await vm.setAiAdjustPrompt(null);
    _notifyReset();
  }

  void _notifyReset() {
    if (!mounted) return;
    context.showAppSnackBar('已恢复默认');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('提示词')),
      body: SafeArea(
        child: Consumer<SettingsViewModel>(
          builder: (context, vm, _) {
            final s = vm.settings;
            return ListView(
              padding: const EdgeInsets.symmetric(vertical: 16),
              children: <Widget>[
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: _InfoCard(),
                ),
                const SizedBox(height: 12),
                _PromptSection(
                  title: '错误日志分析',
                  icon: Icons.bug_report_outlined,
                  controller: _errorAnalysisController,
                  isCustomized: s.aiErrorAnalysisPrompt != null,
                  helper: '原样发送给模型,无占位符。',
                  onSave: () => _saveErrorAnalysis(vm),
                  onReset: () => _resetErrorAnalysis(vm),
                ),
                const SizedBox(height: 12),
                _PromptSection(
                  title: '提醒调整',
                  icon: Icons.auto_fix_high_outlined,
                  controller: _adjustController,
                  isCustomized: s.aiAdjustPrompt != null,
                  helper:
                      '可用占位符:{{now}}、{{timezone}}、{{offset}}、{{weekday}}'
                      '。删除占位符即不再注入对应运行时变量。',
                  onSave: () => _saveAdjust(vm),
                  onReset: () => _resetAdjust(vm),
                  onPreview: _previewAdjust,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PromptSection extends StatelessWidget {
  const _PromptSection({
    required this.title,
    required this.icon,
    required this.controller,
    required this.isCustomized,
    required this.helper,
    required this.onSave,
    required this.onReset,
    this.onPreview,
  });

  final String title;
  final IconData icon;
  final TextEditingController controller;
  final bool isCustomized;
  final String helper;
  final VoidCallback onSave;
  final VoidCallback onReset;
  final VoidCallback? onPreview;

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      title: title,
      icon: icon,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: <Widget>[
              Icon(
                isCustomized ? Icons.edit_outlined : Icons.check_circle_outline,
                size: 16,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                isCustomized ? '已自定义' : '使用默认',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: TextField(
            controller: controller,
            minLines: 6,
            maxLines: 14,
            maxLength: 2000,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: 'system prompt',
              helperText: helper,
              helperMaxLines: 3,
              alignLabelWithHint: true,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            children: <Widget>[
              FilledButton.icon(
                onPressed: onSave,
                icon: const Icon(Icons.save_outlined),
                label: const Text('保存'),
              ),
              TextButton.icon(
                onPressed: onReset,
                icon: const Icon(Icons.restore_outlined),
                label: const Text('恢复默认'),
              ),
              if (onPreview != null)
                TextButton.icon(
                  onPressed: onPreview,
                  icon: const Icon(Icons.preview_outlined),
                  label: const Text('渲染预览'),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.tips_and_updates_outlined, color: colors.primary),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              '编辑后请保存才会生效。留空(或点击"恢复默认")会使用内置 prompt。'
              '不当的 prompt 可能让 AI 返回失败或乱码 — 出现问题时,'
              '请先恢复默认再排查。',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
