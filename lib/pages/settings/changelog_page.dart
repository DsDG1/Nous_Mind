import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

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
            const SizedBox(height: 16),
            Center(
              child: TextButton.icon(
                onPressed: () => context.push('/settings/changelog/history'),
                icon: const Icon(Icons.history),
                label: Text('查看历史版本 (${_changelogHistory.length})'),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Future<void> _copyAll(BuildContext context) async {
    await Clipboard.setData(
      ClipboardData(text: _formatListForClipboard(_changelog)),
    );
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

/// History subpage. Mirrors [ChangelogPage] but renders the older
/// versions list (1.2.x and below). The hero block is intentionally
/// omitted — there is no "latest" concept on this page; every entry is
/// historical. The "复制全部" button copies the history list only.
class ChangelogHistoryPage extends StatelessWidget {
  const ChangelogHistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('历史版本'),
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
            for (final v in _changelogHistory)
              _ChangelogEntry(
                entry: v,
                isLatest: false,
                onCopy: () => _copyOne(context, v),
              ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Future<void> _copyAll(BuildContext context) async {
    await Clipboard.setData(
      ClipboardData(text: _formatListForClipboard(_changelogHistory)),
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('已复制全部历史版本')));
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

/// Newest-first list of human-facing release notes for the *current*
/// and the immediately previous major series (1.5.x + 1.4.0). Edit this
/// list when shipping a new 1.5.x patch. When the next major bumps to
/// 1.6, the choice is yours: either keep 1.5.x + 1.4.0 on the main page
/// (current policy) or graduate 1.5.x into [_changelogHistory] to keep
/// the main page focused on just the latest.
const List<_ChangelogVersion> _changelog = <_ChangelogVersion>[
  _ChangelogVersion(
    version: '1.5.2',
    notes: <String>[
      '编辑器「AI 自动调整」拆为独立 ReminderAiAdjustController,流程更稳定,修复偶发灰屏',
      'AI 助手新增「调用前确认」弹窗,防止误触烧额度',
      'AI 助手新增「今日用量」上限与 10 秒冷却,可一键开关与调整',
      '加入 ML Kit ProGuard keep 规则,发布包中文 OCR 不再静默回退到「截图识别失败」',
      '隐私政策 / 用户协议统一收纳到「设置 → 关于 → 协议」,AppBar 右上角翻译图标可在中/英之间切换',
      '用户协议改写为基于 MIT 开源协议,补充预编译 App 注意事项',
      '提醒列表新增「加入系统日历」入口,失败时给出提示与跳转系统设置的入口',
      '错误日志支持一键 AI 诊断',
    ],
  ),
  _ChangelogVersion(
    version: '1.5.1',
    notes: <String>[
      '新增用户协议页面:设置 → 关于 → 协议 → 用户协议,中英双语 Markdown + 右上角语言切换',
      '隐私政策与用户协议统一收纳到"协议"段,AppBar 右上角翻译图标可在中/英之间切换',
    ],
  ),
  _ChangelogVersion(
    version: '1.5.0',
    notes: <String>[
      '新增「加入日历」功能:提醒列表右侧日历图标一键写入系统日历,失败时给出明确提示与跳转系统设置的入口',
      'AI 防滥用加固:每日调用上限 + 10 秒冷却窗口,「设置 → AI 助手 → 今日 AI 用量」可一键开关与调整上限',
      'AI 误触防护:编辑页 AI 按钮改为弹窗确认后调用,避免手抖烧额度',
      'AI 输入清洗:自动截断过长输入、剥离控制字符、附加反信息抽取附录,自定义提示词加 2000 字上限并支持渲染预览',
      '新增隐私政策页面:设置 → 关于 → 隐私政策,中英双语 Markdown',
    ],
  ),
  _ChangelogVersion(
    version: '1.4.0',
    notes: <String>[
      '真·可以用了！好用了',
      '合并「新增提醒」和「新增提醒（AI）」为统一页面，不再弹出选择弹窗',
      'AI 按钮移至编辑页右上角，连按 2 次触发，防止误触',
      'AI 根据截图 OCR + 已填标题/描述，自动调整标题、描述、时间',
      '截图含多条提醒时弹出确认弹窗，支持勾选后批量创建',
      'AI 返回的描述字段现在正确解析，不再丢失',
      '新增「提醒调整」prompt 自定义（设置 → AI 助手 → 提示词）',
      '清理废弃代码：旧 AI 助手页面、文本润色功能及其相关组件',
    ],
  ),
];

/// Versions retired from the main changelog page. They still ship with
/// the app and are reachable via the "查看历史版本" button. Kept in the
/// same newest-first ordering for visual consistency.
const List<_ChangelogVersion> _changelogHistory = <_ChangelogVersion>[
  _ChangelogVersion(
    version: '1.3.1',
    notes: <String>[
      '修复滑动删除提醒时产生 Flutter framework 错误日志的问题',
      '新增「错误日志 AI 分析」: 设置 → 关于 → 错误日志,每条错误可一键调 AI 给出诊断与排查建议',
      '新增「AI 提示词自定义」: 设置 → AI 助手 → 提示词,可改写「提醒提取 / 文本润色 / 错误分析」三段 prompt,留空或点击"恢复默认"即用内置 prompt',
      '默认打开本地中文 OCR(已升级的旧用户保持原状)',
      'AI 助手及其子页面布局拉宽,与其他设置页对齐',
      '更新日志主页只显示 1.3.x 系列,旧版本归入「查看历史版本」子页',
    ],
  ),
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

String _formatListForClipboard(List<_ChangelogVersion> list) {
  return list.map(_formatForClipboard).join('\n\n');
}
