import 'package:flutter/material.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:provider/provider.dart';

import 'package:nousmind/services/ai_analyzer.dart';
import 'package:nousmind/utils/snackbar_x.dart';
import 'package:nousmind/viewmodels/settings_view_model.dart';

/// Settings subpage for editing the system prompts used by the AI
/// surfaces (error analysis, reminder adjustment, inspiration analysis).
/// Each field shows the built-in default when nothing is stored.
/// Leaving a field empty saves `null`, which makes [AiAnalyzer] fall
/// back to its hard-coded default at call time. The templates support
/// runtime placeholders that are rendered before calling the API.
class AiPromptsSettingsPage extends StatefulWidget {
  const AiPromptsSettingsPage({super.key});

  @override
  State<AiPromptsSettingsPage> createState() => _AiPromptsSettingsPageState();
}

class _AiPromptsSettingsPageState extends State<AiPromptsSettingsPage> {
  late final TextEditingController _errorAnalysisController;
  late final TextEditingController _adjustController;
  late final TextEditingController _inspirationController;

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
    _inspirationController = TextEditingController(
      text:
          settings.aiInspirationPrompt ??
          DeepSeekAnalyzer.defaultInspirationAnalysisPromptTemplate,
    );
  }

  @override
  void dispose() {
    _errorAnalysisController.dispose();
    _adjustController.dispose();
    _inspirationController.dispose();
    super.dispose();
  }

  Future<void> _saveErrorAnalysis(SettingsViewModel vm) =>
      _saveFor(vm.setAiErrorAnalysisPrompt, _errorAnalysisController.text);
  Future<void> _saveAdjust(SettingsViewModel vm) =>
      _saveFor(vm.setAiAdjustPrompt, _adjustController.text);
  Future<void> _saveInspiration(SettingsViewModel vm) =>
      _saveFor(vm.setAiInspirationPrompt, _inspirationController.text);

  Future<void> _saveFor(
    Future<void> Function(String?) setter,
    String value,
  ) async {
    await setter(value);
    if (!mounted) return;
    context.showAppSnackBar('已保存');
  }

  Future<void> _previewAdjust() async {
    final template = _adjustController.text.trim().isEmpty
        ? DeepSeekAnalyzer.defaultAdjustPromptTemplate
        : _adjustController.text;
    await _previewTemplate(template);
  }

  Future<void> _previewInspiration() async {
    final template = _inspirationController.text.trim().isEmpty
        ? DeepSeekAnalyzer.defaultInspirationAnalysisPromptTemplate
        : _inspirationController.text;
    await _previewTemplate(template);
  }

  Future<void> _previewTemplate(String template) async {
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

  Future<void> _resetInspiration(SettingsViewModel vm) async {
    _inspirationController.text =
        DeepSeekAnalyzer.defaultInspirationAnalysisPromptTemplate;
    await vm.setAiInspirationPrompt(null);
    _notifyReset();
  }

  void _notifyReset() {
    if (!mounted) return;
    context.showAppSnackBar('已恢复默认');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('自定义 prompt')),
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
                const SizedBox(height: 16),
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
                  title: '提醒自动调整',
                  icon: Icons.auto_fix_high_outlined,
                  controller: _adjustController,
                  isCustomized: s.aiAdjustPrompt != null,
                  helper:
                      '可用占位符:{{now}}、{{timezone}}、{{offset}}、{{weekday}}。'
                      '删除占位符即不再注入对应运行时变量。',
                  onSave: () => _saveAdjust(vm),
                  onReset: () => _resetAdjust(vm),
                  onPreview: _previewAdjust,
                ),
                const SizedBox(height: 12),
                _PromptSection(
                  title: '灵感智能分析',
                  icon: Icons.lightbulb_outline,
                  controller: _inspirationController,
                  isCustomized: s.aiInspirationPrompt != null,
                  helper:
                      '可用占位符:{{now}}、{{timezone}}、{{offset}}、{{weekday}}、{{tags}}。'
                      '删除占位符即不再注入对应运行时变量。',
                  onSave: () => _saveInspiration(vm),
                  onReset: () => _resetInspiration(vm),
                  onPreview: _previewInspiration,
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
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: colors.outlineVariant, width: 1),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: Icon(icon, color: colors.primary),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: Row(
          children: <Widget>[
            Icon(
              isCustomized ? Icons.edit_outlined : Icons.check_circle_outline,
              size: 14,
              color: isCustomized ? colors.secondary : colors.outline,
            ),
            const SizedBox(width: 4),
            Text(
              isCustomized ? '已自定义' : '使用默认',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: isCustomized ? colors.secondary : colors.outline,
              ),
            ),
          ],
        ),
        shape: const Border(),
        collapsedShape: const Border(),
        childrenPadding: const EdgeInsets.all(16),
        children: <Widget>[
          TextField(
            controller: controller,
            minLines: 4,
            maxLines: 12,
            maxLength: 2000,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: 'System Prompt',
              helperText: helper,
              helperMaxLines: 3,
              alignLabelWithHint: true,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                TextButton.icon(
                  onPressed: onReset,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                  ),
                  icon: const Icon(Icons.restore_outlined, size: 16),
                  label: const Text('恢复默认', style: TextStyle(fontSize: 13)),
                ),
                if (onPreview != null) ...[
                  OutlinedButton.icon(
                    onPressed: onPreview,
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                    ),
                    icon: const Icon(Icons.preview_outlined, size: 16),
                    label: const Text('预览', style: TextStyle(fontSize: 13)),
                  ),
                ],
                FilledButton.icon(
                  onPressed: onSave,
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                  ),
                  icon: const Icon(Icons.save_outlined, size: 16),
                  label: const Text('保存', style: TextStyle(fontSize: 13)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: 0.25),
        border: Border.all(color: colors.primaryContainer, width: 1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.tips_and_updates_outlined, color: colors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '编辑后请保存才会生效。留空(或点击"恢复默认")会使用内置 prompt。'
              '不当的 prompt 可能让 AI 返回失败或乱码 — 出现问题时,'
              '请先恢复默认再排查。',
              style: TextStyle(
                fontSize: 13,
                color: colors.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
