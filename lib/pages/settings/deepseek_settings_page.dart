import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:nousmind/utils/snackbar_x.dart';
import 'package:nousmind/viewmodels/settings_view_model.dart';
import 'package:nousmind/widgets/settings_section.dart';

/// Detail page for the DeepSeek provider. Hosts the per-provider switches
/// and the API key editor. The enable switch here mirrors the one on the
/// parent AI settings page so users can toggle without leaving the page.
class DeepSeekSettingsPage extends StatefulWidget {
  const DeepSeekSettingsPage({super.key});

  @override
  State<DeepSeekSettingsPage> createState() => _DeepSeekSettingsPageState();
}

class _DeepSeekSettingsPageState extends State<DeepSeekSettingsPage> {
  final TextEditingController _controller = TextEditingController();
  bool _obscure = true;

  static final Uri _tutorialUri = Uri.parse(
    'https://api-docs.deepseek.com/zh-cn/',
  );

  @override
  void initState() {
    super.initState();
    final stored = context.read<SettingsViewModel>().settings.aiApiKey;
    _controller.text = stored ?? '';
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? _maskedPreview(String key) {
    if (key.length <= 8) return '••••••••';
    return '${key.substring(0, 4)}••••${key.substring(key.length - 4)}';
  }

  Future<void> _save(BuildContext context, SettingsViewModel vm) async {
    await vm.setAiApiKey(_controller.text);
    if (!context.mounted) return;
    context.showAppSnackBar('已保存');
  }

  Future<void> _clear(BuildContext context, SettingsViewModel vm) async {
    _controller.clear();
    await vm.setAiApiKey(null);
    if (!context.mounted) return;
    context.showAppSnackBar('已清除');
  }

  Future<void> _openTutorial() async {
    final ok = await launchUrl(
      _tutorialUri,
      mode: LaunchMode.externalApplication,
    );
    if (!ok && mounted) {
      context.showAppSnackBar('无法打开浏览器');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('DeepSeek')),
      body: SafeArea(
        child: Consumer<SettingsViewModel>(
          builder: (context, vm, _) {
            final stored = vm.settings.aiApiKey;
            final isConfigured = stored != null;
            return ListView(
              padding: const EdgeInsets.symmetric(vertical: 16),
              children: <Widget>[
                SettingsSection(
                  title: '启用 AI 助手',
                  icon: Icons.power_settings_new_outlined,
                  children: <Widget>[
                    SwitchListTile(
                      title: const Text('启用 DeepSeek'),
                      subtitle: Text(
                        vm.settings.aiAssistantEnabled ? '已启用' : '未启用',
                      ),
                      secondary: const Icon(Icons.auto_awesome_outlined),
                      value: vm.settings.aiAssistantEnabled,
                      onChanged: (value) => vm.setAiAssistantEnabled(value),
                    ),
                  ],
                ),
                SettingsSection(
                  title: 'DeepSeek API 密钥',
                  icon: Icons.auto_awesome_outlined,
                  children: <Widget>[
                    ListTile(
                      leading: const Icon(Icons.key_outlined),
                      title: const Text('当前状态'),
                      subtitle: Text(
                        isConfigured ? '已配置（${_maskedPreview(stored)}）' : '未配置',
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: TextField(
                        controller: _controller,
                        obscureText: _obscure,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: InputDecoration(
                          labelText: 'API 密钥',
                          hintText: 'sk-...',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Row(
                        children: <Widget>[
                          FilledButton.icon(
                            onPressed: () => _save(context, vm),
                            icon: const Icon(Icons.save_outlined),
                            label: const Text('保存'),
                          ),
                          const SizedBox(width: 12),
                          if (isConfigured)
                            TextButton.icon(
                              onPressed: () => _clear(context, vm),
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('清除'),
                            ),
                        ],
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.menu_book_outlined),
                      title: const Text('查看 DeepSeek 文档教程'),
                      subtitle: const Text('了解如何获取 API 密钥、可用模型与参数'),
                      trailing: const Icon(Icons.open_in_new, size: 18),
                      onTap: _openTutorial,
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: SelectableText(
                        '从 https://platform.deepseek.com/api_keys/ 获取 API 密钥。'
                        '密钥仅保存在本机,不会上传到任何服务器。',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
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
                            'AI 助手使用 DeepSeek-V4 Flash 解析文本与截图,'
                            '需要联网。',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
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
                            'AI 生成内容可能不准确或不完整,请自行核对,使用风险自负。',
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.onErrorContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
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
