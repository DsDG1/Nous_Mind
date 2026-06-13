import 'dart:io';

import 'package:flutter/material.dart';

import '../models/inspiration.dart';
import '../utils/date_format.dart';

/// A swipe-to-delete list row representing a single [Inspiration].
///
/// Renders a 56×56 thumbnail (or a placeholder icon when the file is
/// missing or the inspiration has no image), the inspiration text, and the
/// formatted creation timestamp. Tapping the row triggers [onTap]; a left
/// swipe triggers [onDelete].
class InspirationListItem extends StatelessWidget {
  const InspirationListItem({
    super.key,
    required this.inspiration,
    required this.onTap,
    required this.onDelete,
  });

  final Inspiration inspiration;
  final VoidCallback onTap;
  final VoidCallback onDelete;

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
        leading: _Thumbnail(imagePath: inspiration.imagePath),
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
  const _Thumbnail({required this.imagePath});

  final String? imagePath;

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
            : Image.file(
                File(imagePath!),
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    _Placeholder(colors: colors),
              ),
      ),
    );
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
