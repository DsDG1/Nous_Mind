import 'package:flutter/material.dart';

/// Side-by-side (or stacked on narrow screens) preview that lets the
/// user accept or reject an AI-polished revision of their reminder
/// description. Returns `true` when the user accepts the polished
/// version, `false` (or `null` if dismissed) otherwise.
///
/// The caller wires the [polished] string back into the editor's
/// description controller; this widget stays pure presentation.
class AiPolishSheet extends StatelessWidget {
  const AiPolishSheet({
    super.key,
    required this.original,
    required this.polished,
  });

  final String original;
  final String polished;

  /// Convenience wrapper. Returns `true` when the user accepts the
  /// polish, `false` on cancel or scrim dismiss.
  static Future<bool> show(
    BuildContext context, {
    required String original,
    required String polished,
  }) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          AiPolishSheet(original: original, polished: polished),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final media = MediaQuery.of(context);
    final isWide = media.size.width >= 600;
    final maxHeight = media.size.height * 0.7;

    Widget card({
      required String label,
      required String body,
      required Color bg,
      required Color fg,
    }) {
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

    final originalCard = card(
      label: '原文',
      body: original,
      bg: colors.surfaceContainerHighest,
      fg: colors.onSurfaceVariant,
    );
    final polishedCard = card(
      label: '润色后',
      body: polished,
      bg: colors.primaryContainer,
      fg: colors.onPrimaryContainer,
    );

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
                    Text('AI 润色建议', style: textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Text(
                      '采用后将替换原描述',
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
                  child: isWide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Expanded(child: originalCard),
                            const SizedBox(width: 12),
                            Expanded(child: polishedCard),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            originalCard,
                            const SizedBox(height: 12),
                            polishedCard,
                          ],
                        ),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('取消'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text('采用'),
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
}
