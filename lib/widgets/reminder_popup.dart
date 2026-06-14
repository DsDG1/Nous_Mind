import 'dart:ui';

import 'package:flutter/material.dart';

/// Shows a centred reminder popup over a Gaussian-blurred backdrop.
///
/// The dialog contains a small "消息提醒" label, a large [title], an
/// optional [description] rendered below the title, and a row of two
/// buttons: the snooze button (labelled with [snoozeLabel], defaults
/// to "稍后提醒（5 分钟）") which invokes [onSnooze] then dismisses,
/// and "确定" which just dismisses.
///
/// The [context] should belong to the root navigator so the popup sits on top
/// of every route, including tab bars and shell scaffolds.
Future<void> showReminderPopup({
  required BuildContext context,
  required String title,
  String? description,
  String snoozeLabel = '稍后提醒（5 分钟）',
  VoidCallback? onSnooze,
}) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'Reminder popup',
    barrierColor: Colors.black38,
    transitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (context, animation, secondaryAnimation) {
      final colors = Theme.of(context).colorScheme;
      final textTheme = Theme.of(context).textTheme;
      final hasDescription =
          description != null && description.trim().isNotEmpty;
      final safeDescription = description ?? '';
      return BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Material(
              type: MaterialType.card,
              elevation: 8,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              color: colors.surface,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 32, 28, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      '消息提醒',
                      style: textTheme.labelMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (hasDescription) ...<Widget>[
                      const SizedBox(height: 12),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 160),
                        child: SingleChildScrollView(
                          child: Text(
                            safeDescription,
                            textAlign: TextAlign.center,
                            style: textTheme.bodyMedium?.copyWith(
                              color: colors.onSurfaceVariant,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 32),
                    if (onSnooze != null) ...[
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: () {
                            onSnooze();
                            Navigator.of(context).pop();
                          },
                          child: Text(snoozeLabel),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('确定'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.8, end: 1.0).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
          ),
          child: child,
        ),
      );
    },
  );
}
