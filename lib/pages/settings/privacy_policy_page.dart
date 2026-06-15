import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

/// Renders the bundled `assets/privacy_policy.md` document. The
/// Markdown is loaded asynchronously on first build and the page falls
/// back to a spinner if the asset read is still in flight (which is
/// essentially never on warm starts — the asset is bundled into the
/// APK/IPA and Flutter caches it).
///
/// Edit the file at `assets/privacy_policy.md` and rebuild to update
/// the policy — no Dart changes needed.
class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  static const String _assetPath = 'assets/privacy_policy.md';

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('隐私政策')),
      body: SafeArea(
        child: FutureBuilder<String>(
          future: rootBundle.loadString(_assetPath),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    '加载隐私政策失败:${snapshot.error}',
                    style: TextStyle(color: colors.error),
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            final markdown = snapshot.data ?? '';
            return Markdown(
              data: markdown,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              selectable: true,
            );
          },
        ),
      ),
    );
  }
}