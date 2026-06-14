import 'package:flutter/foundation.dart';
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
          leading: const Icon(Icons.update),
          title: '更新日志',
          subtitle: '查看版本更新内容',
          onTap: () => _showChangelog(context),
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

  void _showChangelog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('更新日志'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (final entry in _changelog) _ChangelogEntry(entry: entry),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}

/// Single version's release notes. Kept as a plain immutable record so the
/// changelog can grow as a static list ordered newest-first.
class _ChangelogVersion {
  const _ChangelogVersion({required this.version, required this.notes});

  final String version;
  final List<String> notes;
}

/// Newest-first list of human-facing release notes. Keep entries brief —
/// the dialog wraps them in a scrolling column but it should fit on one
/// screen for the latest version.
const List<_ChangelogVersion> _changelog = <_ChangelogVersion>[
  _ChangelogVersion(
    version: '1.1.1',
    notes: <String>[
      '优化设置页性能,切换设置不再卡顿',
      '备份导入改用批量事务,大备份导入大幅加速',
      '备份导出改在后台线程编码,UI 不再阻塞',
      '错误日志复制改为异步处理',
    ],
  ),
  _ChangelogVersion(
    version: '1.1.0',
    notes: <String>[
      '新增 AI 助手:接入 DeepSeek,可从文本与截图自动解析提醒',
      '数据持久化迁移到 SQLite,启动与查询更快',
      '设置页重做:外观、通知、数据、AI、关于五个子页',
      '新增数据备份与恢复(导出/导入 JSON)',
      '新增错误日志收集,可在"关于"页查看与复制',
      '提醒支持附加图片,通知点击可直接查看',
      '通知设置精简:免打扰时段、贪睡时长、震动开关',
    ],
  ),
];

/// Renders one version block (header + bullet list) inside the changelog dialog.
class _ChangelogEntry extends StatelessWidget {
  const _ChangelogEntry({required this.entry});

  final _ChangelogVersion entry;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'v${entry.version}',
            style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          for (final note in entry.notes)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text('• $note', style: textTheme.bodySmall),
            ),
        ],
      ),
    );
  }
}

/// Section showing the collected errors, plus copy / clear actions.
///
/// The header tile subscribes via [Selector] to just `(isEmpty, count)` so
/// it does not rebuild for unrelated [ErrorLogService] notifications. The
/// action rows + recent entries still use a [Consumer] because they need
/// the full service to invoke handlers and iterate the entries list.
class _ErrorLogSection extends StatelessWidget {
  const _ErrorLogSection();

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      title: '错误日志',
      icon: Icons.bug_report_outlined,
      children: <Widget>[
        Selector<ErrorLogService, _LogHeader>(
          selector: (_, log) =>
              _LogHeader(isEmpty: log.isEmpty, count: log.count),
          builder: (context, header, _) {
            return SettingsTile(
              leading: const Icon(Icons.list_alt),
              title: '已收集错误',
              subtitle: header.isEmpty ? '暂无错误' : '共 ${header.count} 条',
            );
          },
        ),
        Consumer<ErrorLogService>(
          builder: (context, log, _) {
            if (log.isEmpty) return const SizedBox.shrink();
            return Column(
              children: <Widget>[
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
            );
          },
        ),
      ],
    );
  }

  Future<void> _copyAll(BuildContext context, ErrorLogService log) async {
    // Capture a snapshot so the isolate input is stable even if a new
    // entry lands while we are formatting.
    final entries = log.entries.toList(growable: false);
    final text = await compute(_formatLogEntries, entries);
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('日志已复制')));
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

/// Joins every captured entry into a single clipboard-ready string. Runs in
/// a background isolate via [compute] so a full 200-entry buffer with stack
/// traces does not stall the UI thread.
String _formatLogEntries(List<ErrorLogEntry> entries) {
  return entries.map((e) => e.format()).join('\n\n');
}

/// Selector key for the error-log header tile. Two scalar fields with
/// explicit value equality so [Selector] only triggers a rebuild when the
/// count or empty state actually changes.
class _LogHeader {
  const _LogHeader({required this.isEmpty, required this.count});

  final bool isEmpty;
  final int count;

  @override
  bool operator ==(Object other) =>
      other is _LogHeader && other.isEmpty == isEmpty && other.count == count;

  @override
  int get hashCode => Object.hash(isEmpty, count);
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
