import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:nousmind/services/backup_service.dart';
import 'package:nousmind/widgets/settings_stats_row.dart';

/// Compact card displayed at the top of the settings home page. Shows
/// the current record counts and the on-disk size of the user's images.
///
/// Subscribes to [BackupService.statsNotifier] so it can paint the most
/// recent cached value instantly when the settings page is re-entered.
/// Triggering a refresh is the host's job — typically via
/// [BackupService.refreshStats] on app startup or
/// [BackupService.invalidateAndRefresh] after mutations.
class SettingsStatsCard extends StatelessWidget {
  const SettingsStatsCard({super.key});

  @override
  Widget build(BuildContext context) {
    final backup = context.read<BackupService>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: ValueListenableBuilder<StorageStats?>(
        valueListenable: backup.statsNotifier,
        builder: (context, stats, _) {
          final colors = Theme.of(context).colorScheme;
          return _shell(
            colors,
            child: SettingsStatsRow(stats: stats),
          );
        },
      ),
    );
  }

  Widget _shell(ColorScheme colors, {required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant),
      ),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: child,
    );
  }
}
