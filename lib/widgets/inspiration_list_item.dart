import 'dart:io';

import 'package:flutter/material.dart';

import 'package:nousmind/models/inspiration.dart';
import 'package:nousmind/utils/date_format.dart';

/// A swipe-to-delete list row representing a single [Inspiration].
///
/// Renders a 56×56 thumbnail (or a placeholder icon when the file is
/// missing or the inspiration has no image), the inspiration text, and the
/// formatted creation timestamp. Tapping the row triggers [onTap]; tapping
/// the thumbnail triggers [onImageTap] (used to open a fullscreen preview);
/// a left swipe triggers [onDelete].
class InspirationListItem extends StatelessWidget {
  const InspirationListItem({
    super.key,
    required this.inspiration,
    required this.onTap,
    required this.onDelete,
    this.onImageTap,
  });

  final Inspiration inspiration;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  /// Called when the user taps the thumbnail. Should be null when
  /// [inspiration] has no image — the thumbnail renders a non-interactive
  /// placeholder in that case.
  final void Function(Inspiration)? onImageTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Dismissible(
      key: ValueKey<String>(inspiration.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: colors.error,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Icon(Icons.delete, color: colors.onError),
      ),
      onDismissed: (_) => onDelete(),
      child: ListTile(
        onTap: onTap,
        leading: _Thumbnail(
          imagePath: inspiration.imagePath,
          heroTag: 'inspiration-thumb:${inspiration.id}',
          onTap: onImageTap == null || inspiration.imagePath == null
              ? null
              : () => onImageTap!(inspiration),
        ),
        title: Text(
          inspiration.text,
          style: Theme.of(context).textTheme.titleMedium,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(formatDateTime(inspiration.createdAt)),
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.imagePath, this.onTap, this.heroTag});

  final String? imagePath;
  final VoidCallback? onTap;
  final Object? heroTag;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: 56,
      height: 56,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: imagePath == null
            ? _Placeholder(colors: colors)
            : GestureDetector(
                onTap: onTap,
                behavior: HitTestBehavior.opaque,
                child: _buildImage(colors),
              ),
      ),
    );
  }

  Widget _buildImage(ColorScheme colors) {
    final fileImage = Image.file(
      File(imagePath!),
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) =>
          _Placeholder(colors: colors),
    );
    if (heroTag == null) {
      return fileImage;
    }
    return Hero(tag: heroTag!, child: fileImage);
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.colors});

  final ColorScheme colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: colors.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(Icons.image_outlined, color: colors.outline),
    );
  }
}
