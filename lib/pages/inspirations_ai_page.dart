import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:provider/provider.dart';

import 'package:nousmind/models/inspiration.dart';
import 'package:nousmind/services/ai_analyzer.dart';
import 'package:nousmind/services/ai_usage_guard.dart';
import 'package:nousmind/utils/snackbar_x.dart';
import 'package:nousmind/viewmodels/inspirations_view_model.dart';
import 'package:nousmind/viewmodels/reminders_view_model.dart';
import 'package:nousmind/viewmodels/settings_view_model.dart';
import 'package:nousmind/viewmodels/tags_view_model.dart';

class InspirationsAiPage extends StatefulWidget {
  const InspirationsAiPage({super.key});

  @override
  State<InspirationsAiPage> createState() => _InspirationsAiPageState();
}

class _InspirationsAiPageState extends State<InspirationsAiPage> {
  final Set<String> _selectedIds = <String>{};

  bool _summarize = true;
  bool _createReminders = true;
  bool _extractTodos = true;
  bool _extractThemes = true;

  bool _isAnalyzing = false;
  InspirationAnalysisResult? _result;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final viewModel = Provider.of<InspirationsViewModel>(
      context,
      listen: false,
    );
    if (_selectedIds.isEmpty && viewModel.inspirations.isNotEmpty) {
      _selectedIds.addAll(viewModel.inspirations.map((i) => i.id));
    }
  }

  void _toggleSelectAll(bool select, List<Inspiration> items) {
    setState(() {
      if (select) {
        _selectedIds.addAll(items.map((i) => i.id));
      } else {
        _selectedIds.clear();
      }
    });
  }

  Future<void> _selectByDateRange(List<Inspiration> items) async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (range == null) return;

    final start = DateUtils.dateOnly(range.start);
    final end = DateUtils.dateOnly(range.end).add(const Duration(days: 1));

    setState(() {
      _selectedIds.clear();
      for (final item in items) {
        if (item.createdAt.isAfter(start) && item.createdAt.isBefore(end)) {
          _selectedIds.add(item.id);
        }
      }
    });

    if (!mounted) return;
    context.showAppSnackBar('已选中该时间范围内的 ${_selectedIds.length} 条灵感');
  }

  Future<String> _resolveTimezone() async {
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      return info.identifier;
    } on Exception {
      return 'UTC';
    }
  }

  Future<void> _runAnalysis(List<Inspiration> allInspirations) async {
    final settingsViewModel = context.read<SettingsViewModel>();
    final settings = settingsViewModel.settings;

    if (!settings.aiAssistantEnabled) {
      context.showAppSnackBar('请先在 设置 → AI 助手 中启用 AI 助手');
      return;
    }
    final apiKey = settings.aiApiKey;
    if (apiKey == null || apiKey.trim().isEmpty) {
      context.showAppSnackBar('请先在 设置 → AI 助手 中填写 API 密钥');
      return;
    }

    final guard = context.read<AiUsageGuard>();
    final verdict = guard.tryAcquire();
    if (verdict is AcquireCooldown) {
      context.showAppSnackBar(
        'AI 刚调用过,请稍候 ${verdict.retryAfter.inSeconds} 秒再试',
      );
      return;
    }
    if (verdict is AcquireDailyLimitReached) {
      context.showAppSnackBar(
        '今日 AI 调用已达上限(${verdict.limit}/${verdict.limit}),'
        '明天自动恢复或前往设置调整',
      );
      return;
    }
    final allowed = verdict as AcquireAllowed;

    final remaining = allowed.remaining;
    final quotaLine = remaining == null
        ? '今日不限制调用次数,是否继续?'
        : '将消耗 1 次 AI 调用(今日剩余 $remaining 次),是否继续?';

    final confirmed = await showDialog<bool>(
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
    if (confirmed != true) return;

    setState(() {
      _isAnalyzing = true;
      _result = null;
    });

    try {
      final selectedInspirations = allInspirations
          .where((i) => _selectedIds.contains(i.id))
          .toList();

      final texts = selectedInspirations.map((i) => i.text).toList();
      final ocrTexts = selectedInspirations
          .map((i) => i.ocrText ?? '')
          .toList();
      final dates = selectedInspirations.map((i) => i.createdAt).toList();

      final enabledFunctions = <String>[];
      if (_summarize) enabledFunctions.add('总结想法');
      if (_createReminders) enabledFunctions.add('一键加到提醒');
      if (_extractTodos) enabledFunctions.add('待办清单/行动步骤');
      if (_extractThemes) enabledFunctions.add('核心标签主题');

      final analyzer = context.read<AiAnalyzer>();
      final timezone = await _resolveTimezone();
      if (!mounted) return;

      final tagsViewModel = context.read<TagsViewModel>();
      final availableTags = tagsViewModel.tags
          .map((t) => (id: t.id, name: t.name))
          .toList();

      final responseMap = await analyzer.analyzeInspirations(
        texts: texts,
        ocrTexts: ocrTexts,
        dates: dates,
        enabledFunctions: enabledFunctions,
        apiKey: apiKey,
        timezone: timezone,
        now: DateTime.now(),
        systemPromptTemplate: settings.aiInspirationPrompt,
        availableTags: availableTags,
      );

      await guard.recordSuccess();

      setState(() {
        _result = InspirationAnalysisResult.fromJson(responseMap);
        _isAnalyzing = false;
      });

      if (!mounted) return;
      context.showAppSnackBar('分析成功！结果已在下方展示');
    } catch (e, stackTrace) {
      developer.log(
        'Batch AI analysis failed',
        error: e,
        stackTrace: stackTrace,
      );
      setState(() {
        _isAnalyzing = false;
      });
      if (!mounted) return;
      context.showAppSnackBar(
        e is Exception ? e.toString() : 'AI 分析失败，请检查网络或稍后重试',
      );
    }
  }

  Future<void> _importReminder(SuggestedReminder reminder) async {
    final remindersViewModel = context.read<RemindersViewModel>();
    try {
      await remindersViewModel.add(
        title: reminder.title,
        reminderTime: reminder.suggestedTime,
        description: reminder.description,
        tagId: reminder.tagId,
      );
      setState(() {
        reminder.imported = true;
      });
      if (!mounted) return;
      context.showAppSnackBar('提醒事项 "${reminder.title}" 已导入成功');
    } catch (e) {
      if (!mounted) return;
      context.showAppSnackBar('导入失败: $e');
    }
  }

  Future<void> _importAllReminders(List<SuggestedReminder> reminders) async {
    final remindersViewModel = context.read<RemindersViewModel>();
    final pending = reminders.where((r) => !r.imported).toList();
    if (pending.isEmpty) return;

    try {
      final list = pending
          .map(
            (r) => (
              title: r.title,
              reminderTime: r.suggestedTime,
              description: r.description,
              tagId: r.tagId,
            ),
          )
          .toList();

      await remindersViewModel.addMultiple(list);

      setState(() {
        for (final r in pending) {
          r.imported = true;
        }
      });
      if (!mounted) return;
      context.showAppSnackBar('成功导入 ${pending.length} 项提醒事项');
    } catch (e) {
      if (!mounted) return;
      context.showAppSnackBar('批量导入失败: $e');
    }
  }

  String _formatDateTime(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}年${dt.month}月${dt.day}日 ${two(dt.hour)}:${two(dt.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('AI 智能分析')),
      body: SafeArea(
        child: Consumer<InspirationsViewModel>(
          builder: (context, viewModel, _) {
            final all = viewModel.inspirations;
            if (all.isEmpty) {
              return const Center(child: Text('没有可分析的灵感，请先添加一些灵感。'));
            }

            final isSelectionValid = _selectedIds.isNotEmpty;
            final isFeatureValid =
                _summarize ||
                _createReminders ||
                _extractTodos ||
                _extractThemes;

            return ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                // Step 1: Selection Card
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    side: BorderSide(color: colors.outlineVariant),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '第一步：选择灵感范围',
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: <Widget>[
                            ActionChip(
                              avatar: const Icon(Icons.select_all, size: 16),
                              label: const Text('全选'),
                              onPressed: () => _toggleSelectAll(true, all),
                            ),
                            ActionChip(
                              avatar: const Icon(Icons.deselect, size: 16),
                              label: const Text('全不选'),
                              onPressed: () => _toggleSelectAll(false, all),
                            ),
                            ActionChip(
                              avatar: const Icon(
                                Icons.calendar_month,
                                size: 16,
                              ),
                              label: const Text('按日期段选择'),
                              onPressed: () => _selectByDateRange(all),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Container(
                          constraints: const BoxConstraints(maxHeight: 180),
                          decoration: BoxDecoration(
                            border: Border.all(color: colors.outlineVariant),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: all.length,
                            separatorBuilder: (context, index) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final item = all[index];
                              final isSelected = _selectedIds.contains(item.id);
                              final dateStr =
                                  '${item.createdAt.month}-${item.createdAt.day}';
                              return CheckboxListTile(
                                value: isSelected,
                                title: Text(
                                  item.text,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 14),
                                ),
                                subtitle: Row(
                                  children: [
                                    Text(
                                      dateStr,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: colors.outline,
                                      ),
                                    ),
                                    if (item.imagePath != null) ...[
                                      const SizedBox(width: 8),
                                      Icon(
                                        Icons.image_outlined,
                                        size: 14,
                                        color: colors.outline,
                                      ),
                                    ],
                                  ],
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                visualDensity: VisualDensity.compact,
                                onChanged: (val) {
                                  setState(() {
                                    if (val == true) {
                                      _selectedIds.add(item.id);
                                    } else {
                                      _selectedIds.remove(item.id);
                                    }
                                  });
                                },
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '当前已选中 ${_selectedIds.length} 条灵感（仅传输文本/图片识别结果，不传输图片）',
                          style: textTheme.bodySmall?.copyWith(
                            color: colors.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Step 2: Features Card
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    side: BorderSide(color: colors.outlineVariant),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '第二步：选择分析维度',
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        CheckboxListTile(
                          value: _summarize,
                          title: const Text('总结想法'),
                          subtitle: const Text('深度提炼核心观点，总结思维火花'),
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          onChanged: (val) =>
                              setState(() => _summarize = val ?? false),
                        ),
                        CheckboxListTile(
                          value: _createReminders,
                          title: const Text('转化为提醒事项'),
                          subtitle: const Text('智能识别其中的计划与截止日，一键导入提醒'),
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          onChanged: (val) =>
                              setState(() => _createReminders = val ?? false),
                        ),
                        CheckboxListTile(
                          value: _extractTodos,
                          title: const Text('提取行动清单'),
                          subtitle: const Text('将宏观的想法拆解成具体的可执行步骤'),
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          onChanged: (val) =>
                              setState(() => _extractTodos = val ?? false),
                        ),
                        CheckboxListTile(
                          value: _extractThemes,
                          title: const Text('提炼核心主题'),
                          subtitle: const Text('识别灵感的关键分类标签与核心关键词'),
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          onChanged: (val) =>
                              setState(() => _extractThemes = val ?? false),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Step 3: Run Button
                if (_isAnalyzing)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 12),
                          Text('AI 正在深度思考分析中，请稍候...'),
                        ],
                      ),
                    ),
                  )
                else
                  Container(
                    width: double.infinity,
                    height: 50,
                    decoration: BoxDecoration(
                      gradient: isSelectionValid && isFeatureValid
                          ? LinearGradient(
                              colors: [colors.primary, colors.secondary],
                            )
                          : null,
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                      ),
                      onPressed: isSelectionValid && isFeatureValid
                          ? () => _runAnalysis(all)
                          : null,
                      icon: const Icon(Icons.auto_awesome),
                      label: Text(
                        '开始 AI 智能分析 (${_selectedIds.length}条)',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 24),

                // Step 4: Results Display Section
                if (_result != null) ...[
                  const Divider(height: 32),
                  Row(
                    children: [
                      Icon(Icons.analytics_outlined, color: colors.primary),
                      const SizedBox(width: 8),
                      Text(
                        'AI 分析报告',
                        style: textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // 4.1 Summary Result
                  if (_summarize && _result!.summary != null) ...[
                    Card(
                      elevation: 0,
                      color: colors.primaryContainer.withValues(alpha: 0.15),
                      shape: RoundedRectangleBorder(
                        side: BorderSide(
                          color: colors.primaryContainer.withValues(alpha: 0.5),
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              '💡 想法总结',
                              style: textTheme.titleMedium?.copyWith(
                                color: colors.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            SelectableText(
                              _result!.summary!,
                              style: const TextStyle(fontSize: 14, height: 1.5),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // 4.2 Todos Result
                  if (_extractTodos && _result!.todos.isNotEmpty) ...[
                    Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        side: BorderSide(color: colors.outlineVariant),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              '✅ 行动清单 / 待办事项',
                              style: textTheme.titleMedium?.copyWith(
                                color: colors.secondary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _result!.todos.length,
                              itemBuilder: (context, idx) {
                                return _TodoRow(text: _result!.todos[idx]);
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // 4.3 Themes Result
                  if (_extractThemes && _result!.themes.isNotEmpty) ...[
                    Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        side: BorderSide(color: colors.outlineVariant),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const Text(
                              '🏷️ 提炼的主题与标签',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _result!.themes.map((theme) {
                                return Chip(
                                  label: Text(theme),
                                  backgroundColor:
                                      colors.surfaceContainerHighest,
                                  side: BorderSide.none,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // 4.4 Reminders Result
                  if (_createReminders && _result!.reminders.isNotEmpty) ...[
                    Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        side: BorderSide(color: colors.outlineVariant),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    '⏰ 推荐提醒事项 (${_result!.reminders.length}项)',
                                    style: textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed:
                                      _result!.reminders.any((r) => !r.imported)
                                      ? () => _importAllReminders(
                                          _result!.reminders,
                                        )
                                      : null,
                                  icon: const Icon(Icons.add_task, size: 16),
                                  label: const Text('导入全部'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _result!.reminders.length,
                              separatorBuilder: (context, index) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (context, idx) {
                                final reminder = _result!.reminders[idx];
                                return Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: colors.surfaceContainerLow,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: colors.outlineVariant,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              reminder.title,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 15,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          if (reminder.imported)
                                            const Row(
                                              children: [
                                                Icon(
                                                  Icons.check,
                                                  color: Colors.green,
                                                  size: 16,
                                                ),
                                                SizedBox(width: 4),
                                                Text(
                                                  '已导入',
                                                  style: TextStyle(
                                                    color: Colors.green,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ],
                                            )
                                          else
                                            IconButton(
                                              icon: Icon(
                                                Icons.add_circle_outline,
                                                color: colors.primary,
                                              ),
                                              padding: EdgeInsets.zero,
                                              constraints:
                                                  const BoxConstraints(),
                                              onPressed: () =>
                                                  _importReminder(reminder),
                                              tooltip: '导入此提醒',
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.access_time,
                                            size: 12,
                                            color: colors.outline,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            '推荐时间: ${_formatDateTime(reminder.suggestedTime)}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: colors.outline,
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (reminder.description != null &&
                                          reminder.description!.isNotEmpty) ...[
                                        const SizedBox(height: 6),
                                        Text(
                                          reminder.description!,
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: colors.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                      if (reminder.reason != null &&
                                          reminder.reason!.isNotEmpty) ...[
                                        const SizedBox(height: 8),
                                        Text(
                                          '分析理由: ${reminder.reason!}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: colors.primary,
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TodoRow extends StatefulWidget {
  const _TodoRow({required this.text});
  final String text;

  @override
  State<_TodoRow> createState() => _TodoRowState();
}

class _TodoRowState extends State<_TodoRow> {
  bool _checked = false;

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      value: _checked,
      title: Text(
        widget.text,
        style: TextStyle(
          fontSize: 14,
          decoration: _checked ? TextDecoration.lineThrough : null,
          color: _checked ? Theme.of(context).colorScheme.outline : null,
        ),
      ),
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.zero,
      dense: true,
      onChanged: (val) {
        setState(() {
          _checked = val ?? false;
        });
      },
    );
  }
}

class InspirationAnalysisResult {
  InspirationAnalysisResult({
    required this.summary,
    required this.reminders,
    required this.todos,
    required this.themes,
  });

  final String? summary;
  final List<SuggestedReminder> reminders;
  final List<String> todos;
  final List<String> themes;

  factory InspirationAnalysisResult.fromJson(Map<String, dynamic> json) {
    final summary = json['summary'] as String?;

    final remindersList = json['reminders'] as List<dynamic>? ?? [];
    final reminders = remindersList
        .map((r) => SuggestedReminder.fromJson(r as Map<String, dynamic>))
        .toList();

    final todosList = json['todos'] as List<dynamic>? ?? [];
    final todos = todosList.map((t) => t.toString()).toList();

    final themesList = json['themes'] as List<dynamic>? ?? [];
    final themes = themesList.map((t) => t.toString()).toList();

    return InspirationAnalysisResult(
      summary: summary,
      reminders: reminders,
      todos: todos,
      themes: themes,
    );
  }
}

class SuggestedReminder {
  SuggestedReminder({
    required this.title,
    required this.suggestedTime,
    required this.description,
    required this.reason,
    required this.tagId,
    this.imported = false,
  });

  final String title;
  final DateTime suggestedTime;
  final String? description;
  final String? reason;
  final String? tagId;
  bool imported;

  factory SuggestedReminder.fromJson(Map<String, dynamic> json) {
    final title = json['title'] as String? ?? '未命名提醒';

    DateTime suggestedTime;
    final rawTime = json['suggested_time'] as String?;
    if (rawTime != null) {
      suggestedTime =
          DateTime.tryParse(rawTime) ??
          DateTime.now().add(const Duration(hours: 1));
    } else {
      suggestedTime = DateTime.now().add(const Duration(hours: 1));
    }

    return SuggestedReminder(
      title: title,
      suggestedTime: suggestedTime,
      description: json['description'] as String?,
      reason: json['reason'] as String?,
      tagId: json['tag_id'] as String?,
    );
  }
}
