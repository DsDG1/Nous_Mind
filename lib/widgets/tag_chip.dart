import 'package:flutter/material.dart';

import 'package:nousmind/models/tag.dart';

/// A small, color-keyed badge showing a [Tag]'s name. Used in the
/// list row, the reminder editor, the AI batch confirm sheet, and
/// the tag settings subpage.
///
/// The chip has two sizes:
///   * default: full size, sits comfortably in a list-row subtitle
///     and the editor form.
///   * [compact]: smaller padding / font, used in dense rows where
///     the default size would overflow.
///
/// The foreground text color is computed from a luminance check on
/// the tag color so the label stays readable on light *and* dark
/// background swatches. A soft 50%-opacity fill gives a tinted-pill
/// look that respects the seed color without clashing with the
/// surrounding `colorScheme.surface`.
class TagChip extends StatelessWidget {
  const TagChip({
    super.key,
    required this.tag,
    this.compact = false,
    this.selected = false,
  });

  final Tag tag;
  final bool compact;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final swatch = Color(tag.color);
    final fg = _readableForeground(swatch);
    final hPad = compact ? 6.0 : 10.0;
    final vPad = compact ? 2.0 : 4.0;
    final dotSize = compact ? 6.0 : 8.0;
    final fontSize = compact ? 11.0 : 13.0;
    final bg = selected
        ? swatch.withValues(alpha: 0.22)
        : swatch.withValues(alpha: 0.12);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: swatch.withValues(alpha: 0.55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: dotSize,
            height: dotSize,
            decoration: BoxDecoration(color: swatch, shape: BoxShape.circle),
          ),
          SizedBox(width: compact ? 4 : 6),
          Text(
            tag.name,
            style: TextStyle(
              color: fg,
              fontSize: fontSize,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  /// W3C-style luminance test on the RGB channels. Returns a dark
  /// grey on light backgrounds, white on dark. Threshold tuned to
  /// keep both Material 600/700 swatches and the softer 500s
  /// readable.
  static Color _readableForeground(Color bg) {
    final r = (bg.r * 255.0).round() & 0xFF;
    final g = (bg.g * 255.0).round() & 0xFF;
    final b = (bg.b * 255.0).round() & 0xFF;
    final luma = (0.299 * r + 0.587 * g + 0.114 * b);
    return luma > 160
        ? const Color(0xFF1F2937) // slate-800
        : const Color(0xFFFFFFFF);
  }
}
