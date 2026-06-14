import 'package:flutter/material.dart';

import '../services/backup_service.dart';

/// Compact card displayed at the top of the settings home page. Shows
/// the current record counts and the on-disk size of the user's images.
///
/// Reads its data once when first built; subsequent updates require a
/// manual [reload]. Designed to be wrapped in a `FutureBuilder` by the
/// host page so the rest of the page does not block on the database.
class SettingsStatsCard extends StatefulWidget {
  const SettingsStatsCard({required this.future, super.key});

  /// A future that resolves to a [StorageStats] snapshot. The widget
  /// re-runs the future every time it is reparented with a new
  /// [Future] instance, so callers can pass a freshly-built future
  /// after operations that change counts.
  final Future<StorageStats> future;

  @override
  State<SettingsStatsCard> createState() => _SettingsStatsCardState();
}

class _SettingsStatsCardState extends State<SettingsStatsCard> {
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: FutureBuilder<StorageStats>(
        future: widget.future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return _shell(
              colors,
              child: const Center(
                child: SizedBox(
                  height: 36,
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
            );
          }
          final stats = snapshot.data;
          return _shell(
            colors,
            child: Row(
              children: <Widget>[
                Expanded(
                  child: _StatCell(
                    icon: Icons.notifications_active_outlined,
                    value: stats == null ? '—' : '${stats.reminderCount}',
                    label: '提醒',
                  ),
                ),
                _Divider(color: colors.outlineVariant),
                Expanded(
                  child: _StatCell(
                    icon: Icons.lightbulb_outline,
                    value: stats == null ? '—' : '${stats.inspirationCount}',
                    label: '灵感',
                  ),
                ),
                _Divider(color: colors.outlineVariant),
                Expanded(
                  child: _StatCell(
                    icon: Icons.image_outlined,
                    value: stats == null
                        ? '—'
                        : BackupService.formatBytes(stats.imageBytes),
                    label: '图片',
                  ),
                ),
              ],
            ),
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

class _StatCell extends StatelessWidget {
  const _StatCell({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 18, color: colors.primary),
        const SizedBox(height: 4),
        Text(
          value,
          style: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: colors.onSurface,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 40,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: color,
    );
  }
}
