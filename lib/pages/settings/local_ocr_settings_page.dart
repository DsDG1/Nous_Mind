import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/chinese_ocr_installer.dart';
import '../../viewmodels/settings_view_model.dart';
import '../../widgets/settings_section.dart';

/// Detail page for the on-device Chinese OCR model. Hosts the
/// per-language enable switch and a status row.
///
/// With the current *bundled* integration the model ships inside the
/// APK / IPA — there is nothing to download at runtime. The page
/// still surfaces the [ChineseOcrInstaller] status so the user can
/// see "model is ready", and the [OcrModuleStatus] enum keeps slots
/// for a future move to an unbundled distribution without an
/// additional UI redesign.
class LocalOcrSettingsPage extends StatefulWidget {
  const LocalOcrSettingsPage({super.key});

  @override
  State<LocalOcrSettingsPage> createState() => _LocalOcrSettingsPageState();
}

class _LocalOcrSettingsPageState extends State<LocalOcrSettingsPage> {
  @override
  void initState() {
    super.initState();
    // Re-check the model state every time the page opens. Cheap (one
    // channel roundtrip) and keeps the UI honest on platforms where
    // the status could legitimately change.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final installer = context.read<ChineseOcrInstaller>();
      installer.refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('本地 OCR')),
      body: SafeArea(
        child: Consumer2<SettingsViewModel, ChineseOcrInstaller>(
          builder: (context, vm, installer, _) {
            final enabled = vm.settings.chineseOcrEnabled;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                SettingsSection(
                  title: '启用 中文 OCR',
                  icon: Icons.translate_outlined,
                  children: <Widget>[
                    SwitchListTile(
                      title: const Text('启用中文识别'),
                      subtitle: Text(
                        enabled ? '已启用 · 截图含中文时优先使用中文模型' : '未启用 · 仅使用通用拉丁脚本',
                      ),
                      secondary: const Icon(Icons.power_settings_new_outlined),
                      value: enabled,
                      onChanged: (value) => vm.setChineseOcrEnabled(value),
                    ),
                  ],
                ),
                SettingsSection(
                  title: '中文模型',
                  icon: Icons.storage_outlined,
                  children: <Widget>[_StatusTile(installer: installer)],
                ),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: <Widget>[
                      Icon(Icons.info_outline, color: colors.primary),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          '模型随 App 一起打包(约 4 MB),无需联网下载,'
                          '离线可用。',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colors.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        Icons.warning_amber_rounded,
                        color: colors.onErrorContainer,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '中文识别失败时,会自动回退到通用脚本,'
                          'OCR 仍可工作,只是中文识别效果会下降。',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _StatusTile extends StatelessWidget {
  const _StatusTile({required this.installer});

  final ChineseOcrInstaller installer;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.check_circle_outline),
      title: const Text('当前状态'),
      subtitle: Text(_label(installer.status)),
    );
  }

  static String _label(OcrModuleStatus status) {
    return switch (status) {
      OcrModuleStatus.installed => '已就绪 · 随 App 打包',
      OcrModuleStatus.downloading => '下载中…',
      OcrModuleStatus.pending => '等待下载',
      OcrModuleStatus.notInstalled => '未下载',
      OcrModuleStatus.unsupported => '当前设备不支持中文模型',
      OcrModuleStatus.unknown => '检查中…',
    };
  }
}
