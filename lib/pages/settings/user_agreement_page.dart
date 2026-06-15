import 'package:flutter/material.dart';

import 'package:nousmind/widgets/bilingual_markdown_page.dart';

/// Renders the bundled `assets/user_agreement.md` document. The actual
/// loading, language toggle and Markdown rendering live in
/// [BilingualMarkdownPage] — this class is a thin shell so the route can
/// stay stable if the rendering widget is later swapped out.
///
/// Edit the file at `assets/user_agreement.md` and rebuild to update the
/// agreement — no Dart changes needed.
class UserAgreementPage extends StatelessWidget {
  const UserAgreementPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const BilingualMarkdownPage(
      assetPath: 'assets/user_agreement.md',
      title: '用户协议',
      loadErrorPrefix: '加载用户协议失败:',
    );
  }
}
