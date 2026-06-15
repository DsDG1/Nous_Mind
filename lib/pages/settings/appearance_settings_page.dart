import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:nousmind/models/app_settings.dart';
import 'package:nousmind/viewmodels/settings_view_model.dart';
import 'package:nousmind/widgets/settings_section.dart';

/// Settings subpage for theme mode and accent (seed) color.
///
/// All edits go through [SettingsViewModel] and become visible app-wide
/// immediately because the MaterialApp reads from the same view model.
class AppearanceSettingsPage extends StatelessWidget {
  const AppearanceSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('外观')),
      body: SafeArea(
        child: Consumer<SettingsViewModel>(
          builder: (context, vm, _) {
            final settings = vm.settings;
            return ListView(
              children: <Widget>[
                SettingsSection(
                  title: '显示',
                  icon: Icons.palette_outlined,
                  children: <Widget>[
                    SettingsTile(
                      title: '主题模式',
                      subtitle: themeModeLabel(settings.themeMode),
                      leading: const Icon(Icons.brightness_6_outlined),
                      onTap: () =>
                          _pickThemeMode(context, vm, settings.themeMode),
                    ),
                    SettingsTile(
                      title: '主题色',
                      subtitle: appSeedColorLabel(settings.seedColor),
                      leading: _ColorSwatch(color: settings.seedColor.color),
                      onTap: () =>
                          _pickSeedColor(context, vm, settings.seedColor),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _pickThemeMode(
    BuildContext context,
    SettingsViewModel vm,
    ThemeMode current,
  ) async {
    final selected = await showDialog<ThemeMode>(
      context: context,
      builder: (ctx) {
        return SimpleDialog(
          title: const Text('选择主题模式'),
          children: <Widget>[
            RadioGroup<ThemeMode>(
              groupValue: current,
              onChanged: (value) => Navigator.of(ctx).pop(value),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  for (final mode in ThemeMode.values)
                    RadioListTile<ThemeMode>(
                      title: Text(themeModeLabel(mode)),
                      value: mode,
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
    if (selected != null) {
      await vm.setThemeMode(selected);
    }
  }

  Future<void> _pickSeedColor(
    BuildContext context,
    SettingsViewModel vm,
    AppSeedColor current,
  ) async {
    final selected = await showDialog<AppSeedColor>(
      context: context,
      builder: (ctx) {
        return SimpleDialog(
          title: const Text('选择主题色'),
          children: <Widget>[
            RadioGroup<AppSeedColor>(
              groupValue: current,
              onChanged: (value) => Navigator.of(ctx).pop(value),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  for (final color in AppSeedColor.values)
                    RadioListTile<AppSeedColor>(
                      title: Text(appSeedColorLabel(color)),
                      secondary: _ColorSwatch(color: color.color),
                      value: color,
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
    if (selected != null) {
      await vm.setSeedColor(selected);
    }
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black26),
      ),
    );
  }
}
