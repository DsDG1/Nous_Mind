import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../../services/error_log_service.dart';
import '../../widgets/settings_section.dart';

/// Settings subpage that surfaces app branding, version metadata, the
/// in-memory error log, and a link to the open-source licenses page.
class AboutSettingsPage extends StatefulWidget {
  const AboutSettingsPage({super.key});

  @override
  State<AboutSettingsPage> createState() => _AboutSettingsPageState();
}

class _AboutSettingsPageState extends State<AboutSettingsPage> {
  PackageInfo? _packageInfo;

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
  }

  Future<void> _loadPackageInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _packageInfo = info);
    } on Exception {
      // Leave as null; the UI shows "未知" rather than crashing.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 24),
          children: <Widget>[
            const _AppHeader(),
            _VersionSection(info: _packageInfo),
            const _ErrorLogSection(),
            const _AboutSection(),
          ],
        ),
      ),
    );
  }
}

/// Centered circular logo + app name at the top of the page.
class _AppHeader extends StatelessWidget {
  const _AppHeader();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        children: <Widget>[
          CircleAvatar(
            radius: 48,
            backgroundColor: colors.primaryContainer,
            child: Icon(
              Icons.notifications_active,
              size: 40,
              color: colors.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Nous 记事',
            style: textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '提醒事项',
            style: textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Section showing version, build number, and a license page shortcut.
class _VersionSection extends StatelessWidget {
  const _VersionSection({required this.info});

  final PackageInfo? info;

  @override
  Widget build(BuildContext context) {
    final version = info == null ? '未知' : info!.version;
    final build = info == null ? '未知' : info!.buildNumber;
    return SettingsSection(
      title: '版本',
      icon: Icons.tag_outlined,
      children: <Widget>[
        SettingsTile(
          leading: const Icon(Icons.info_outline),
          title: '版本',
          subtitle: version,
          onTap: () => _copyToClipboard(context, '版本 $version'),
        ),
        SettingsTile(
          leading: const Icon(Icons.numbers_outlined),
          title: '构建号',
          subtitle: build,
          onTap: () => _copyToClipboard(context, '构建号 $build'),
        ),
        SettingsTile(
          leading: const Icon(Icons.description_outlined),
          title: '开源许可',
          subtitle: '查看本应用使用的第三方库的许可',
          onTap: () => _showLicenses(context),
        ),
      ],
    );
  }

  Future<void> _copyToClipboard(BuildContext context, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已复制')));
  }

  void _showLicenses(BuildContext context) {
    showLicensePage(
      context: context,
      applicationName: 'Nous 记事',
      applicationVersion: info?.version,
      applicationIcon: const Padding(
        padding: EdgeInsets.all(8),
        child: Icon(Icons.notifications_active, size: 40),
      ),
    );
  }
}

/// Section showing the collected errors, plus copy / clear actions.
class _ErrorLogSection extends StatelessWidget {
  const _ErrorLogSection();

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      title: '错误日志',
      icon: Icons.bug_report_outlined,
      children: <Widget>[
        Consumer<ErrorLogService>(
          builder: (context, log, _) {
            return Column(
              children: <Widget>[
                SettingsTile(
                  leading: const Icon(Icons.list_alt),
                  title: '已收集错误',
                  subtitle: log.isEmpty ? '暂无错误' : '共 ${log.count} 条',
                ),
                if (!log.isEmpty) ...<Widget>[
                  SettingsTile(
                    leading: const Icon(Icons.copy_outlined),
                    title: '复制全部日志',
                    onTap: () => _copyAll(context, log),
                  ),
                  SettingsTile(
                    leading: const Icon(Icons.delete_outline),
                    title: '清空日志',
                    onTap: () => _confirmClear(context, log),
                  ),
                  ...log.entries.take(5).map((e) => _ErrorEntryCard(entry: e)),
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  Future<void> _copyAll(BuildContext context, ErrorLogService log) async {
    final text = log.entries.map((e) => e.format()).join('\n\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('日志已复制')));
  }

  Future<void> _confirmClear(BuildContext context, ErrorLogService log) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('清空日志？'),
        content: const Text('此操作不可撤销。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      log.clear();
    }
  }
}

/// Compact card rendering one captured error entry.
class _ErrorEntryCard extends StatelessWidget {
  const _ErrorEntryCard({required this.entry});

  final ErrorLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text(
                  entry.source,
                  style: textTheme.labelMedium?.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  _shortTime(entry.timestamp),
                  style: textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              entry.message,
              style: textTheme.bodySmall,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  static String _shortTime(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }
}

/// Static branding copy.
class _AboutSection extends StatelessWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      title: '关于',
      icon: Icons.info_outline,
      children: const <Widget>[
        SettingsTile(leading: Icon(Icons.code), title: '由 DsDogs 制作'),
        SettingsTile(
          leading: Icon(Icons.bolt_outlined),
          title: '主要使用 Vibe Coding 开发',
        ),
      ],
    );
  }
}
