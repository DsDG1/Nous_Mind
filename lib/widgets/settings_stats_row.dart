import 'package:flutter/material.dart';

import 'package:nousmind/services/backup_service.dart';

/// Three-cell summary row for [StorageStats]: reminders, inspirations,
/// image bytes. Renders an icon + titleMedium value + bodySmall label
/// per cell, separated by a thin vertical divider.
///
/// Used by the settings home `SettingsStatsCard` and by the data
/// management subpage. The host owns any card chrome / loading
/// state — this widget only renders the row.
///
/// When [stats] is `null`, each cell renders an em-dash placeholder.
class SettingsStatsRow extends StatelessWidget {
  const SettingsStatsRow({
    super.key,
    required this.stats,
  });

  final StorageStats? stats;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final valueStyle = textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w600,
      color: colors.onSurface,
    );
    final labelStyle = textTheme.bodySmall?.copyWith(
      color: colors.onSurfaceVariant,
    );

    final reminderText = stats == null ? '—' : '${stats!.reminderCount}';
    final inspirationText =
        stats == null ? '—' : '${stats!.inspirationCount}';
    final imageText = stats == null
        ? '—'
        : BackupService.formatBytes(stats!.imageBytes);

    Widget cell({
      required IconData icon,
      required String value,
      required String label,
    }) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 18, color: colors.primary),
          const SizedBox(height: 4),
          Text(value, style: valueStyle),
          const SizedBox(height: 2),
          Text(label, style: labelStyle),
        ],
      );
    }

    return Row(
      children: <Widget>[
        Expanded(
          child: cell(
            icon: Icons.notifications_active_outlined,
            value: reminderText,
            label: '提醒',
          ),
        ),
        VerticalDivider(
          width: 9,
          thickness: 1,
          color: colors.outlineVariant,
        ),
        Expanded(
          child: cell(
            icon: Icons.lightbulb_outline,
            value: inspirationText,
            label: '灵感',
          ),
        ),
        VerticalDivider(
          width: 9,
          thickness: 1,
          color: colors.outlineVariant,
        ),
        Expanded(
          child: cell(
            icon: Icons.image_outlined,
            value: imageText,
            label: '图片',
          ),
        ),
      ],
    );
  }
}
