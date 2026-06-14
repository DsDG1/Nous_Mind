import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Full-page release notes reachable from
/// `设置 → 关于 → 更新日志`. Renders a hero block at the top announcing
/// the latest version, followed by a card per release, newest first.
///
/// The AppBar exposes a "copy all" action; each card carries its own
/// per-version copy button. Both flows land the result on the system
/// clipboard with a brief snackbar confirmation.
class ChangelogPage extends StatelessWidget {
  const ChangelogPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('更新日志'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.content_copy),
            tooltip: '复制全部',
            onPressed: () => _copyAll(context),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: <Widget>[
            _ChangelogHero(latest: _changelog.first, total: _changelog.length),
            const SizedBox(height: 8),
            for (var i = 0; i < _changelog.length; i++)
              _ChangelogEntry(
                entry: _changelog[i],
                isLatest: i == 0,
                onCopy: () => _copyOne(context, _changelog[i]),
              ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Future<void> _copyAll(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: _formatAllForClipboard()));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('已复制全部版本')));
  }

  Future<void> _copyOne(BuildContext context, _ChangelogVersion v) async {
    await Clipboard.setData(ClipboardData(text: _formatForClipboard(v)));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('已复制 v${v.version}')));
  }
}

/// Hero block at the top of the changelog. Surfaces the latest version
/// in oversized typography plus the entry count, so the user lands
/// knowing what is current before scrolling.
class _ChangelogHero extends StatelessWidget {
  const _ChangelogHero({required this.latest, required this.total});

  final _ChangelogVersion latest;
  final int total;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '最新版本',
              style: textTheme.labelLarge?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'v${latest.version}',
              style: textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: colors.primary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              latest.notes.first,
              style: textTheme.bodyMedium?.copyWith(
                color: colors.onSurface,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '共 $total 个版本',
              style: textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Card-style release block. The newest entry gets a colored accent
/// border on the leading edge and a slightly deeper shadow to lift it
/// above the historical entries; the rest sit flat on the surface.
class _ChangelogEntry extends StatelessWidget {
  const _ChangelogEntry({
    required this.entry,
    required this.isLatest,
    required this.onCopy,
  });

  final _ChangelogVersion entry;
  final bool isLatest;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final cardColor = isLatest ? colors.surface : colors.surfaceContainer;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Material(
        color: cardColor,
        elevation: isLatest ? 2 : 0,
        shadowColor: colors.primary.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: isLatest
                ? Border(left: BorderSide(color: colors.primary, width: 4))
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                child: Row(
                  children: <Widget>[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isLatest
                            ? colors.primary
                            : colors.primaryContainer,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'v${entry.version}',
                        style: textTheme.labelLarge?.copyWith(
                          color: isLatest
                              ? colors.onPrimary
                              : colors.onPrimaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.content_copy, size: 20),
                      tooltip: '复制此版本',
                      onPressed: onCopy,
                    ),
                  ],
                ),
              ),
              Divider(
                height: 1,
                color: colors.outlineVariant.withValues(alpha: 0.4),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    for (final note in entry.notes)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: colors.primary,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                note,
                                style: textTheme.bodyMedium?.copyWith(
                                  height: 1.6,
                                ),
                              ),
                            ),
                          ],
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

/// Single version's release notes. Kept as a plain immutable record so the
/// changelog can grow as a static list ordered newest-first.
class _ChangelogVersion {
  const _ChangelogVersion({required this.version, required this.notes});

  final String version;
  final List<String> notes;
}

/// Newest-first list of human-facing release notes. Edit this list when
/// shipping a new version; the rest of the page renders from here.
const List<_ChangelogVersion> _changelog = <_ChangelogVersion>[
  _ChangelogVersion(
    version: '1.3.0',
    notes: <String>[
      '删除提醒改为「软删除」,可从回收站恢复 30 天',
      '新增回收站页,可全部恢复或永久删除,过期自动清理',
      '设置 → 数据 中新增回收站入口',
      '备份导出不再包含已删除的提醒',
    ],
  ),
  _ChangelogVersion(
    version: '1.2.6',
    notes: <String>[
      '提醒新增描述字段,通知内容更详细',
      '描述支持 AI 一键润色,自动改顺口、整结构、轻微优化措辞',
      '通知新增「稍后提醒」与「完成」按钮,无需打开 App 即可处理',
      '修复提醒弹窗的「稍后提醒」按钮时长与设置不一致的问题',
    ],
  ),
  _ChangelogVersion(
    version: '1.2.5',
    notes: <String>[
      '新增本地中文 OCR 识别能力,可在「设置 → AI → 本地 OCR」启用,模型随 App 打包,离线可用,失败时自动回退到拉丁文识别',
      '修复 AI 助手解析的提醒时间在非 UTC 时区下显示为 UTC 时间的错误,现在与设备本地时区一致',
      '优化 AI 助手输入界面布局,文字输入框移至图片选择之后',
    ],
  ),
  _ChangelogVersion(
    version: '1.2.4',
    notes: <String>['升级多项第三方依赖至最新版，适配新版 API', '修复 Android release 构建失败问题'],
  ),
  _ChangelogVersion(
    version: '1.2.3',
    notes: <String>['「更新日志」改造为独立整页,支持一键复制全部与单条复制'],
  ),
  _ChangelogVersion(
    version: '1.2.2',
    notes: <String>[
      'AI 助手设置页改造为 DeepSeek 蓝色长方形卡片,支持一键启用与详情配置',
      'AI 助手新增反滥用保护:连续认证失败自动锁定,频繁点击自动限流',
    ],
  ),
  _ChangelogVersion(
    version: '1.2.1',
    notes: <String>['修复快速添加提醒磁贴在某些设备上无法打开应用的问题'],
  ),
  _ChangelogVersion(
    version: '1.2.0',
    notes: <String>['新增快速添加提醒磁贴,可在通知栏快速创建提醒', '新增 DeepSeek 教程链接和 AI 风险提示'],
  ),
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

String _formatForClipboard(_ChangelogVersion v) {
  final buffer = StringBuffer('v${v.version}\n');
  for (final note in v.notes) {
    buffer.writeln('  • $note');
  }
  return buffer.toString().trimRight();
}

String _formatAllForClipboard() {
  return _changelog.map(_formatForClipboard).join('\n\n');
}
