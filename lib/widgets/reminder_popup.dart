import 'dart:ui';

import 'package:flutter/material.dart';

/// Shows a centred reminder popup over a Gaussian-blurred backdrop.
///
/// The dialog contains a small "消息提醒" label, a large [title], and a row of
/// two buttons: "稍后提醒（5分钟）" which invokes [onSnooze] then dismisses,
/// and "确定" which just dismisses.
///
/// The [context] should belong to the root navigator so the popup sits on top
/// of every route, including tab bars and shell scaffolds.
Future<void> showReminderPopup({
  required BuildContext context,
  required String title,
  VoidCallback? onSnooze,
}) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'Reminder popup',
    barrierColor: Colors.black38,
    transitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (context, animation, secondaryAnimation) {
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
              color: Theme.of(context).colorScheme.surface,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 32, 28, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      '消息提醒',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 32),
                    Row(
                      children: <Widget>[
                        if (onSnooze != null)
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                onSnooze();
                                Navigator.of(context).pop();
                              },
                              child: const Text('稍后提醒（5分钟）'),
                            ),
                          ),
                        if (onSnooze != null) const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('确定'),
                          ),
                        ),
                      ],
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
