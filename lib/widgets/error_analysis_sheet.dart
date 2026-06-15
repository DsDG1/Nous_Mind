import 'package:flutter/material.dart';

import 'package:nousmind/services/ai_analyzer.dart';
import 'package:nousmind/services/ai_usage_guard.dart';
import 'package:nousmind/services/error_log_service.dart';

/// Modal bottom sheet that runs [AiAnalyzer.analyzeError] against an
/// [ErrorLogEntry] and renders the AI's diagnosis. Modeled after
/// `AiPolishSheet` so the look-and-feel stays consistent across the AI
/// surfaces.
///
/// The sheet kicks off the analysis on first build (no extra button) and
/// shows three transient states:
///   * loading — spinner + "AI 正在分析…"
///   * error   — red panel with the [AiAnalysisException.message] and a
///               "重试" button (the original error is still visible above)
///   * success — selectable diagnosis text
class ErrorAnalysisSheet extends StatefulWidget {
  const ErrorAnalysisSheet._({
    required this.entry,
    required this.analyzer,
    required this.apiKey,
    required this.systemPrompt,
    required this.guard,
  });

  final ErrorLogEntry entry;
  final AiAnalyzer analyzer;
  final String apiKey;
  final String? systemPrompt;
  final AiUsageGuard guard;

  /// Opens the sheet and awaits its dismissal. There is no return value
  /// — the analysis is purely informational and is not persisted.
  static Future<void> show(
    BuildContext context, {
    required ErrorLogEntry entry,
    required AiAnalyzer analyzer,
    required String apiKey,
    required AiUsageGuard guard,
    String? systemPrompt,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ErrorAnalysisSheet._(
        entry: entry,
        analyzer: analyzer,
        apiKey: apiKey,
        systemPrompt: systemPrompt,
        guard: guard,
      ),
    );
  }

  @override
  State<ErrorAnalysisSheet> createState() => _ErrorAnalysisSheetState();
}

class _ErrorAnalysisSheetState extends State<ErrorAnalysisSheet> {
  bool _busy = false;
  String? _result;
  AiAnalysisException? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _runAnalysis();
    });
  }

  /// Re-checks the usage guard before every call (initial run AND
  /// "重试" presses). The guard owns the cooldown clock and the daily
  /// counter, so each entry point asks it before charging a token.
  Future<void> _runAnalysis() async {
    final verdict = widget.guard.tryAcquire();
    if (verdict is AcquireCooldown) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = AiCooldownException(
          'AI 刚调用过,请稍候 ${verdict.retryAfter.inSeconds} 秒再试',
        );
      });
      return;
    }
    if (verdict is AcquireDailyLimitReached) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = AiUsageLimitException(
          '今日 AI 调用已达上限(${verdict.limit}/${verdict.limit}),'
          '明天自动恢复或前往设置调整',
        );
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.analyzer.analyzeError(
        text: widget.entry.format(),
        apiKey: widget.apiKey,
        systemPrompt: widget.systemPrompt,
      );
      if (!mounted) return;
      await widget.guard.recordSuccess();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _result = result;
      });
    } on AiAnalysisException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final media = MediaQuery.of(context);
    final maxHeight = media.size.height * 0.75;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Container(
          height: maxHeight,
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('AI 错误分析', style: textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Text(
                      '诊断仅作参考,实际原因请结合代码上下文判断',
                      style: textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _Card(
                        label: '原始日志',
                        body: widget.entry.format(),
                        bg: colors.surfaceContainerHighest,
                        fg: colors.onSurfaceVariant,
                      ),
                      const SizedBox(height: 12),
                      _resultArea(colors: colors, textTheme: textTheme),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Row(
                  children: <Widget>[
                    if (_error != null) ...<Widget>[
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _busy ? null : _runAnalysis,
                          icon: const Icon(Icons.refresh),
                          label: const Text('重试'),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('关闭'),
                      ),
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

  Widget _resultArea({
    required ColorScheme colors,
    required TextTheme textTheme,
  }) {
    if (_busy) {
      return Container(
        constraints: const BoxConstraints(minHeight: 120),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.primaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: <Widget>[
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Text(
              'AI 正在分析…',
              style: textTheme.bodyMedium?.copyWith(
                color: colors.onPrimaryContainer,
              ),
            ),
          ],
        ),
      );
    }
    if (_error != null) {
      return _Card(
        label: '分析失败',
        body: _error!.message,
        bg: colors.errorContainer,
        fg: colors.onErrorContainer,
      );
    }
    return _Card(
      label: 'AI 分析',
      body: _result ?? '',
      bg: colors.primaryContainer,
      fg: colors.onPrimaryContainer,
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.label,
    required this.body,
    required this.bg,
    required this.fg,
  });

  final String label;
  final String body;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 120),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            label,
            style: textTheme.labelMedium?.copyWith(
              color: fg,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          SelectableText(
            body,
            style: textTheme.bodyMedium?.copyWith(color: fg, height: 1.5),
          ),
        ],
      ),
    );
  }
}
