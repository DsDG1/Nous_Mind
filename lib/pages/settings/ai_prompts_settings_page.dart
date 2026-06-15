import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/ai_analyzer.dart';
import '../../viewmodels/settings_view_model.dart';
import '../../widgets/settings_section.dart';

/// Settings subpage for editing the three system prompts used by the AI
/// surfaces (reminder extraction, text polish, error analysis). Each
/// field shows the built-in default when nothing is stored. Leaving a
/// field empty saves `null`, which makes [AiAnalyzer] fall back to its
/// hard-coded default at call time. The extraction prompt supports
/// runtime placeholders that are substituted by
/// [DeepSeekAnalyzer.renderAssistantPrompt].
class AiPromptsSettingsPage extends StatefulWidget {
  const AiPromptsSettingsPage({super.key});

  @override
  State<AiPromptsSettingsPage> createState() => _AiPromptsSettingsPageState();
}

class _AiPromptsSettingsPageState extends State<AiPromptsSettingsPage> {
  late final TextEditingController _assistantController;
  late final TextEditingController _polishController;
  late final TextEditingController _errorAnalysisController;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsViewModel>().settings;
    _assistantController = TextEditingController(
      text:
          settings.aiAssistantPrompt ??
          DeepSeekAnalyzer.defaultAssistantPromptTemplate,
    );
    _polishController = TextEditingController(
      text: settings.aiPolishPrompt ?? DeepSeekAnalyzer.defaultPolishPrompt,
    );
    _errorAnalysisController = TextEditingController(
      text:
          settings.aiErrorAnalysisPrompt ??
          DeepSeekAnalyzer.defaultErrorAnalysisPrompt,
    );
  }

  @override
  void dispose() {
    _assistantController.dispose();
    _polishController.dispose();
    _errorAnalysisController.dispose();
    super.dispose();
  }

  Future<void> _saveAssistant(SettingsViewModel vm) =>
      _saveFor(vm.setAiAssistantPrompt, _assistantController.text);
  Future<void> _savePolish(SettingsViewModel vm) =>
      _saveFor(vm.setAiPolishPrompt, _polishController.text);
  Future<void> _saveErrorAnalysis(SettingsViewModel vm) =>
      _saveFor(vm.setAiErrorAnalysisPrompt, _errorAnalysisController.text);

  Future<void> _saveFor(
    Future<void> Function(String?) setter,
    String value,
  ) async {
    await setter(value);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('已保存')));
  }

  Future<void> _resetAssistant(SettingsViewModel vm) async {
    _assistantController.text = DeepSeekAnalyzer.defaultAssistantPromptTemplate;
    await vm.setAiAssistantPrompt(null);
    _notifyReset();
  }

  Future<void> _resetPolish(SettingsViewModel vm) async {
    _polishController.text = DeepSeekAnalyzer.defaultPolishPrompt;
    await vm.setAiPolishPrompt(null);
    _notifyReset();
  }

  Future<void> _resetErrorAnalysis(SettingsViewModel vm) async {
    _errorAnalysisController.text = DeepSeekAnalyzer.defaultErrorAnalysisPrompt;
    await vm.setAiErrorAnalysisPrompt(null);
    _notifyReset();
  }

  void _notifyReset() {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('已恢复默认')));
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
                  title: '提醒提取',
                  icon: Icons.event_note_outlined,
                  controller: _assistantController,
                  isCustomized: s.aiAssistantPrompt != null,
                  helper:
                      '可用占位符:{{now}}、{{timezone}}、{{offset}}、{{weekday}}、{{tomorrow}}'
                      '。删除占位符即不再注入对应运行时变量。',
                  onSave: () => _saveAssistant(vm),
                  onReset: () => _resetAssistant(vm),
                ),
                const SizedBox(height: 12),
                _PromptSection(
                  title: '文本润色',
                  icon: Icons.auto_fix_high_outlined,
                  controller: _polishController,
                  isCustomized: s.aiPolishPrompt != null,
                  helper: '原样发送给模型,无占位符。',
                  onSave: () => _savePolish(vm),
                  onReset: () => _resetPolish(vm),
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
  });

  final String title;
  final IconData icon;
  final TextEditingController controller;
  final bool isCustomized;
  final String helper;
  final VoidCallback onSave;
  final VoidCallback onReset;

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
          child: Row(
            children: <Widget>[
              FilledButton.icon(
                onPressed: onSave,
                icon: const Icon(Icons.save_outlined),
                label: const Text('保存'),
              ),
              const SizedBox(width: 12),
              TextButton.icon(
                onPressed: onReset,
                icon: const Icon(Icons.restore_outlined),
                label: const Text('恢复默认'),
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
