import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

/// The languages a [BilingualMarkdownPage] can render. Add new entries here
/// and matching `## <Marker>` lines to the source markdown to extend.
enum _Lang { zh, en }

/// Renders a bundled bilingual markdown document (Simplified Chinese +
/// English) with a language toggle in the AppBar.
///
/// The source file is expected to contain two top-level `##` headings
/// `## 简体中文` and `## English` (case-sensitive, on their own line) that
/// split the body into the two localisable sections. The preamble (lines
/// before the first `## 简体中文`) is shown regardless of the selected
/// language.
///
/// Use this widget for any long-form legal or informational text that the
/// User might want to read in either language without leaving the page.
/// The [PrivacyPolicyPage] and [UserAgreementPage] are thin wrappers around
/// it.
class BilingualMarkdownPage extends StatefulWidget {
  const BilingualMarkdownPage({
    super.key,
    required this.assetPath,
    required this.title,
    required this.loadErrorPrefix,
  });

  /// Asset path to the markdown file, e.g. `assets/privacy_policy.md`.
  final String assetPath;

  /// Title shown in the AppBar.
  final String title;

  /// Localised prefix for the load-error text. The runtime error string is
  /// appended after this prefix.
  final String loadErrorPrefix;

  @override
  State<BilingualMarkdownPage> createState() => _BilingualMarkdownPageState();
}

class _BilingualMarkdownPageState extends State<BilingualMarkdownPage> {
  _Lang _lang = _Lang.zh;

  /// Matches `## 简体中文` or `## English` on its own line. Anchored with
  /// `^…$` and `multiLine: true` so partial matches inside paragraphs are
  /// ignored. Whitespace at end-of-line is tolerated.
  static final RegExp _sectionSplit = RegExp(
    r'^## (?:简体中文|English)\s*$',
    multiLine: true,
  );

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.translate),
            tooltip: _lang == _Lang.zh ? 'English' : '简体中文',
            onPressed: () {
              setState(() {
                _lang = _lang == _Lang.zh ? _Lang.en : _Lang.zh;
              });
            },
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<String>(
          future: rootBundle.loadString(widget.assetPath),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    '${widget.loadErrorPrefix}${snapshot.error}',
                    style: TextStyle(color: colors.error),
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            final markdown = snapshot.data ?? '';
            return Markdown(
              data: _extractSection(markdown, _lang),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              selectable: true,
            );
          },
        ),
      ),
    );
  }

  /// Returns the preamble + the requested language section. If the markers
  /// are missing the entire document is returned unchanged as a graceful
  /// fallback so a malformed asset does not produce a blank page.
  String _extractSection(String markdown, _Lang lang) {
    final parts = markdown.split(_sectionSplit);
    // parts[0] = preamble, parts[1] = zh, parts[2] = en
    final preamble = parts.isNotEmpty ? parts.first : '';
    final String section;
    if (lang == _Lang.zh) {
      section = parts.length > 1 ? parts[1] : '';
    } else {
      section = parts.length > 2 ? parts[2] : '';
    }
    if (section.isEmpty) {
      return markdown;
    }
    return '$preamble$section';
  }
}
