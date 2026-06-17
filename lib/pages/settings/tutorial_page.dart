import 'package:flutter/material.dart';

/// User Guide page showcasing key features of NousMind with a clean,
/// modern design following Material 3 guidelines.
class TutorialPage extends StatelessWidget {
  const TutorialPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('新手教程')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: <Widget>[
            // Hero Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colors.primaryContainer.withValues(alpha: 0.2),
                border: Border.all(color: colors.primaryContainer, width: 1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(Icons.school_outlined, size: 48, color: colors.primary),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '欢迎使用 Nous 记事',
                          style: textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colors.primary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '这是一个结合 AI 辅助的日程提醒与灵感捕捉工具。请花 2 分钟阅读以下指引，助您快速上手！',
                          style: textTheme.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Reminders Section
            _buildGuideCard(
              context,
              title: '1. 提醒事项与日历同步',
              icon: Icons.notifications_active_outlined,
              iconColor: Colors.blue,
              bullets: const [
                '设置日程：点击右下角「+」即可新建提醒事项，支持自定义标题、时间、描述及标签。',
                '状态控制：在列表左侧勾选复选框，可直接标记为完成。已完成的事项会自动沉底，保持界面清爽。',
                '同步系统日历：点击条目右侧的日历图标，一键将日程写入系统日历中，即便不打开 App 也能在系统日历中接收通知（需授予日历权限）。',
              ],
            ),
            const SizedBox(height: 12),

            // Tags Section
            _buildGuideCard(
              context,
              title: '2. 标签分类与看板过滤',
              icon: Icons.label_outline,
              iconColor: Colors.orange,
              bullets: const [
                '新建标签：前往「设置 → 标签」管理您的自定义标签，设置名称和专属颜色。',
                '快速过滤：点击主页左上角「筛选」按钮，可一键切换展示全部、特定标签或已完成的提醒，帮您分门别类聚焦当前任务。',
              ],
            ),
            const SizedBox(height: 12),

            // Inspirations Section
            _buildGuideCard(
              context,
              title: '3. 灵感随手记与 OCR 图片搜索',
              icon: Icons.lightbulb_outline,
              iconColor: Colors.amber,
              bullets: const [
                '抓取灵感：切换至「灵感」标签页，记录瞬时的火花，并可附加相册图片或直接拍照。',
                '自动识别 (OCR)：灵感中带有截图或照片时，App 会在后台自动执行文字识别 (OCR)。',
                '无缝搜索：在灵感主页搜索时，系统不仅会匹配您打的字，还会检索图片中识别出的文字，实现「找图只需搜图中的字」。',
                '日期筛选：主页右上角日历按钮支持按日期区间筛选灵感，方便回溯。',
              ],
            ),
            const SizedBox(height: 12),

            // AI Section
            _buildGuideCard(
              context,
              title: '4. AI 智能助手与提示词自定义',
              icon: Icons.auto_awesome_outlined,
              iconColor: Colors.indigo,
              bullets: const [
                '配置 API Key：在「设置 → AI 助手 → DeepSeek」中填入您的 DeepSeek API Key 即可开启（秘钥仅存在本机，请放心使用）。',
                '智能提醒调整：新建/编辑提醒时，右上角 AI 按钮可一键帮您从截图或长文本中提取日程，自动填入标题、描述和时间。',
                '灵感批量导入：点击灵感主页右上角 AI 按钮，可一次性勾选多条灵感导入分析。支持一键生成总结、待办清单、核心主题，并能「一键自动批量导入为提醒事项」，免去手动创建的烦恼。',
                '自定义提示词：在「设置 → AI 助手 → 自定义 prompt」中，您可以深度自定义「错误日志分析」「提醒自动调整」「灵感智能分析」三处 AI 提示词，创造属于您自己的智能工作流。',
              ],
            ),
            const SizedBox(height: 12),

            // Recycle Bin Section
            _buildGuideCard(
              context,
              title: '5. 双标签回收站与数据备份',
              icon: Icons.delete_sweep_outlined,
              iconColor: Colors.red,
              bullets: const [
                '删除保留 30 天：提醒与灵感左滑删除后不会直接消失，而是会放入「回收站」，保留 30 天以供后悔药，过期将自动清除。',
                '防误触撤销：在主页左滑删除时，底部会弹出 SnackBar，点击「撤销」可瞬间恢复。',
                '回收站双标签页：在「设置 → 数据 → 回收站」中，提醒与灵感分栏存放，均支持一键全部恢复或永久删除。点击卡片还可以直接查看已删除条目的内容。',
                '备份管理：数据页面支持一键将所有提醒、灵感、标签及配置以加密 JSON 文件形式导出分享，换机时导入即可无缝恢复。',
              ],
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildGuideCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color iconColor,
    required List<String> bullets,
  }) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: colors.outlineVariant, width: 1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: iconColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            for (final bullet in bullets)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 7),
                      child: Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: colors.onSurfaceVariant.withValues(alpha: 0.6),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        bullet,
                        style: textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
