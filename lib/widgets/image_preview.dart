import 'dart:io';

import 'package:flutter/material.dart';

/// Reusable image preview area with an optional remove button.
///
/// When [imagePath] is null the widget shows a placeholder; otherwise it
/// displays the image at that path. If [onRemove] is non-null a small
/// floating close button is rendered over the top-right corner.
class ImagePreview extends StatelessWidget {
  const ImagePreview({super.key, required this.imagePath, this.onRemove});

  final String? imagePath;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AspectRatio(
      aspectRatio: 4 / 3,
      child: Container(
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: imagePath == null
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(Icons.image_outlined, size: 48, color: colors.outline),
                    const SizedBox(height: 8),
                    Text(
                      '尚未选择图片',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              )
            : Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  Image.file(
                    File(imagePath!),
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Center(
                      child: Icon(
                        Icons.broken_image_outlined,
                        size: 48,
                        color: colors.outline,
                      ),
                    ),
                  ),
                  if (onRemove != null)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Material(
                        color: colors.surface.withValues(alpha: 0.8),
                        shape: const CircleBorder(),
                        child: IconButton(
                          icon: Icon(Icons.close, color: colors.onSurface),
                          tooltip: '移除图片',
                          onPressed: onRemove,
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
