import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:nousmind/services/chinese_ocr_installer.dart';
import 'package:nousmind/viewmodels/settings_view_model.dart';
import 'package:nousmind/widgets/settings_section.dart';

/// Settings subpage that lists the configured AI assistant providers.
/// Each provider renders as a tappable card with an inline enable
/// switch; tapping the body of the card pushes the provider's detail
/// page where its connection credentials are edited.
class AiSettingsPage extends StatelessWidget {
  const AiSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI 助手')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 16),
          children: const <Widget>[
            Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                '选择并配置要使用的 AI 助手',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: _LocalOcrCard(),
            ),
            SizedBox(height: 12),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: _DeepSeekProviderCard(),
            ),
            SizedBox(height: 12),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: _AiUsageCard(),
            ),
            SizedBox(height: 12),
            _PromptsSection(),
          ],
        ),
      ),
    );
  }
}

/// "提示词" entry: routes to [AiPromptsSettingsPage] where the user can
/// override the three built-in prompts. Subtitle indicates how many of
/// the three are customized so the umbrella page tells the user at a
/// glance whether anything has been changed.
class _PromptsSection extends StatelessWidget {
  const _PromptsSection();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsViewModel>().settings;
    final customCount = <bool>[
      settings.aiErrorAnalysisPrompt != null,
      settings.aiAdjustPrompt != null,
    ].where((c) => c).length;
    return SettingsSection(
      title: '提示词',
      icon: Icons.edit_note_outlined,
      children: <Widget>[
        SettingsTile(
          leading: const Icon(Icons.tune_outlined),
          title: '自定义 prompt',
          subtitle: customCount == 0 ? '全部使用默认' : '已自定义 $customCount / 2',
          onTap: () => context.push('/settings/ai/prompts'),
        ),
      ],
    );
  }
}

/// DeepSeek brand color, with a darker variant for dark mode. Hard-coded
/// rather than derived from the theme so the "this is DeepSeek" identity
/// stays consistent regardless of the user's seed color.
class _DeepSeekBrand {
  const _DeepSeekBrand._();
  static const Color light = Color(0xFF4D6BFE);
  static const Color dark = Color(0xFF2B4BCE);
}

Color _brandBlue(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark ? _DeepSeekBrand.dark : _DeepSeekBrand.light;
}

/// A tappable, rounded rectangle that introduces the DeepSeek provider.
/// The entire surface is an [InkWell] that pushes the detail page; the
/// trailing switch is wrapped in a transparent [GestureDetector] so its
/// taps do not bubble up to the InkWell.
class _DeepSeekProviderCard extends StatelessWidget {
  const _DeepSeekProviderCard();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SettingsViewModel>();
    final settings = vm.settings;
    final enabled = settings.aiAssistantEnabled;
    final hasKey = settings.aiApiKey != null;
    final brand = _brandBlue(context);

    return Material(
      color: brand,
      borderRadius: BorderRadius.circular(16),
      elevation: 2,
      shadowColor: brand.withValues(alpha: 0.5),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/settings/ai/deepseek'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: <Widget>[
              const _ProviderLogo(),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Text(
                      'DeepSeek',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _statusLabel(enabled: enabled, hasKey: hasKey),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              _SwitchInterceptor(
                value: enabled,
                onChanged: (v) => vm.setAiAssistantEnabled(v),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _statusLabel({required bool enabled, required bool hasKey}) {
    if (!enabled) return '未启用';
    if (!hasKey) return '已启用 · 未填密钥';
    return '已启用';
  }
}

class _ProviderLogo extends StatelessWidget {
  const _ProviderLogo();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(Icons.auto_awesome, color: Colors.white, size: 26),
    );
  }
}

/// Wraps a [Switch.adaptive] in a transparent [GestureDetector] that
/// absorbs hits so they do not bubble to the surrounding [InkWell].
class _SwitchInterceptor extends StatelessWidget {
  const _SwitchInterceptor({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: Switch.adaptive(
        value: value,
        onChanged: onChanged,
        activeThumbColor: Colors.white,
        activeTrackColor: Colors.white24,
        inactiveThumbColor: Colors.white,
        inactiveTrackColor: Colors.white24,
      ),
    );
  }
}

/// Local OCR card. Highlights the on-device Chinese OCR preference
/// alongside the model-download status so users can see at a glance
/// whether they need to fetch the model before enabling the script.
class _LocalOcrCard extends StatelessWidget {
  const _LocalOcrCard();

  /// Seed-green so the card is visually distinct from the DeepSeek
  /// brand card without being a system color the user might already
  /// have selected as their seed.
  static const Color _accentLight = Color(0xFF2E7D32);
  static const Color _accentDark = Color(0xFF66BB6A);

  Color _accent(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? _accentDark : _accentLight;
  }

  @override
  Widget build(BuildContext context) {
    final accent = _accent(context);
    final settings = context.watch<SettingsViewModel>().settings;
    final installer = context.watch<ChineseOcrInstaller>();
    final enabled = settings.chineseOcrEnabled;

    return Material(
      color: accent,
      borderRadius: BorderRadius.circular(16),
      elevation: 2,
      shadowColor: accent.withValues(alpha: 0.5),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/settings/ai/local-ocr'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: <Widget>[
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.translate_outlined,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Text(
                      '本地 OCR',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _subtitle(enabled: enabled, status: installer.status),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white70),
            ],
          ),
        ),
      ),
    );
  }

  static String _subtitle({
    required bool enabled,
    required OcrModuleStatus status,
  }) {
    if (!enabled) {
      return '未启用 · 截图识别将使用拉丁脚本';
    }
    return switch (status) {
      OcrModuleStatus.installed => '已启用 · 模型随 App 打包',
      OcrModuleStatus.downloading => '已启用 · 模型下载中…',
      OcrModuleStatus.pending => '已启用 · 等待下载',
      OcrModuleStatus.notInstalled => '已启用 · 模型未下载',
      OcrModuleStatus.unsupported => '已启用 · 当前设备不支持中文模型',
      OcrModuleStatus.unknown => '已启用 · 检查模型状态…',
    };
  }
}

/// Surfaces the daily-call counter that backs [AiUsageGuard]. Lets the
/// user toggle the per-day ceiling on or off from one place; when the
/// switch is on, the current usage reads as "X / Y" and the limit is
/// editable through the existing dialog. When the switch is off, the
/// card surfaces "今日不限制" and hides the edit affordance, while the
/// in-process cooldown and the analyzer-level sanitization remain.
class _AiUsageCard extends StatelessWidget {
  const _AiUsageCard();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SettingsViewModel>();
    final settings = vm.settings;
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final used = settings.aiCallsToday;
    final limit = settings.aiDailyLimit;
    final quotaOn = settings.aiDailyLimitEnabled;

    return Card(
      elevation: 0,
      color: colors.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.bar_chart_outlined, color: colors.primary),
                const SizedBox(width: 12),
                Expanded(child: Text('今日 AI 用量', style: textTheme.titleMedium)),
                Text(
                  quotaOn ? '$used / $limit' : '今日不限制',
                  style: textTheme.titleMedium?.copyWith(
                    color: quotaOn && used >= limit
                        ? colors.error
                        : colors.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('启用每日限额'),
              subtitle: Text(
                quotaOn ? '开启后按每日上限拦截 AI 调用' : '关闭后今日不限制调用次数（仅保留冷却）',
              ),
              value: quotaOn,
              onChanged: (value) => vm.setAiDailyLimitEnabled(value),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('每日上限'),
              trailing: quotaOn
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text('$limit 次/天'),
                        TextButton(
                          onPressed: () =>
                              _showDailyLimitDialog(context, vm, limit),
                          child: const Text('修改上限'),
                        ),
                      ],
                    )
                  : null,
              subtitle: quotaOn ? null : const Text('已关闭 — 今日不设上限'),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: <Widget>[
                  OutlinedButton.icon(
                    onPressed: () async {
                      await vm.resetAiUsage();
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(
                          const SnackBar(content: Text('今日用量已重置')),
                        );
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('重置今日用量'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDailyLimitDialog(
    BuildContext context,
    SettingsViewModel vm,
    int currentLimit,
  ) async {
    final controller = TextEditingController(text: currentLimit.toString());
    final result = await showDialog<int>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('每日 AI 调用上限'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '次数 (1-999)',
              helperText: '留空或填 0 视为放弃修改',
              border: OutlineInputBorder(),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final parsed = int.tryParse(controller.text.trim());
                if (parsed == null || parsed < 1 || parsed > 999) {
                  Navigator.of(dialogContext).pop();
                  return;
                }
                Navigator.of(dialogContext).pop(parsed);
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
    if (result == null) return;
    await vm.setAiDailyLimit(result);
  }
}
