import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../viewmodels/settings_view_model.dart';
import '../../widgets/settings_section.dart';

/// Settings subpage for the AI assistant. Hosts a single editable
/// `TextField` for the DeepSeek API key with an eye toggle, plus a
/// "清除" shortcut when a key is currently stored.
class AiSettingsPage extends StatefulWidget {
  const AiSettingsPage({super.key});

  @override
  State<AiSettingsPage> createState() => _AiSettingsPageState();
}

class _AiSettingsPageState extends State<AiSettingsPage> {
  final TextEditingController _controller = TextEditingController();
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    // Seed the controller once from the view model so the build method
    // stays free of side effects. Subsequent edits live in the controller
    // until the user explicitly saves or clears.
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
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('已保存')));
  }

  Future<void> _clear(BuildContext context, SettingsViewModel vm) async {
    _controller.clear();
    await vm.setAiApiKey(null);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('已清除')));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('AI 助手')),
      body: SafeArea(
        child: Consumer<SettingsViewModel>(
          builder: (context, vm, _) {
            final stored = vm.settings.aiApiKey;
            final isConfigured = stored != null;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
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
                          'AI 助手使用 DeepSeek-V4 Flash 解析文本与截图,'
                          '需要联网。',
                          style: TextStyle(fontSize: 12),
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
