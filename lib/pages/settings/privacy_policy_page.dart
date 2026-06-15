import 'package:flutter/material.dart';

import 'package:nousmind/widgets/bilingual_markdown_page.dart';

/// Renders the bundled `assets/privacy_policy.md` document. The actual
/// loading, language toggle and Markdown rendering live in
/// [BilingualMarkdownPage] — this class is a thin shell so the route can
/// stay stable if the rendering widget is later swapped out.
///
/// Edit the file at `assets/privacy_policy.md` and rebuild to update the
/// policy — no Dart changes needed.
class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const BilingualMarkdownPage(
      assetPath: 'assets/privacy_policy.md',
      title: '隐私政策',
      loadErrorPrefix: '加载隐私政策失败:',
    );
  }
}
