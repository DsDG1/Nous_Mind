import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../services/chinese_ocr_installer.dart';
import '../../viewmodels/settings_view_model.dart';

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
          padding: const EdgeInsets.all(16),
          children: const <Widget>[
            Padding(
              padding: EdgeInsets.fromLTRB(8, 0, 8, 12),
              child: Text(
                '选择并配置要使用的 AI 助手',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ),
            _LocalOcrCard(),
            SizedBox(height: 12),
            _DeepSeekProviderCard(),
          ],
        ),
      ),
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
