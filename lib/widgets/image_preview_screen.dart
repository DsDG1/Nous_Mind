import 'dart:io';

import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';

/// Fullscreen image preview that supports pinch-to-zoom, double-tap to
/// zoom, single-tap to close, and a vertical-drag-to-dismiss gesture.
///
/// The screen is meant to be pushed onto the root navigator (so it sits
/// above the tab bar). The [heroTag] should match the [Hero] tag of the
/// thumbnail that opened it, so the transition animates smoothly in
/// both directions.
class ImagePreviewScreen extends StatefulWidget {
  const ImagePreviewScreen({
    super.key,
    required this.imagePath,
    required this.heroTag,
  });

  final String imagePath;
  final Object heroTag;

  @override
  State<ImagePreviewScreen> createState() => _ImagePreviewScreenState();
}

class _ImagePreviewScreenState extends State<ImagePreviewScreen> {
  /// Distance (in logical pixels) the user has dragged the photo
  /// downward. Only positive values matter — swipes up are ignored so
  /// the gesture doesn't fight the pinch / pan logic of [PhotoView].
  double _dragOffset = 0;

  /// Opacity of the black backdrop. Fades out as the user drags the
  /// photo toward dismissal.
  double _bgOpacity = 1;

  /// Threshold (logical pixels) past which a downward drag is
  /// committed as a dismiss rather than a snap-back.
  static const double _dismissThreshold = 120;

  /// Drag distance at which the backdrop is fully transparent.
  static const double _fadeDistance = 400;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(context).pop(),
          onVerticalDragUpdate: (details) {
            // Only accumulate downward motion; ignore upward swipes
            // entirely so [PhotoView] can keep handling them.
            final dy = details.delta.dy;
            if (dy <= 0) return;
            setState(() {
              _dragOffset += dy;
              _bgOpacity = (1 - _dragOffset / _fadeDistance).clamp(0.0, 1.0);
            });
          },
          onVerticalDragEnd: (details) {
            final velocity = details.primaryVelocity ?? 0;
            if (_dragOffset > _dismissThreshold || velocity > 800) {
              Navigator.of(context).pop();
            } else {
              // Snap back to origin.
              setState(() {
                _dragOffset = 0;
                _bgOpacity = 1;
              });
            }
          },
          child: Stack(
            children: <Widget>[
              AnimatedContainer(
                duration: const Duration(milliseconds: 80),
                color: Colors.black.withValues(alpha: _bgOpacity),
              ),
              Transform.translate(
                offset: Offset(0, _dragOffset),
                child: PhotoView(
                  imageProvider: FileImage(File(widget.imagePath)),
                  backgroundDecoration: const BoxDecoration(),
                  minScale: PhotoViewComputedScale.contained,
                  maxScale: PhotoViewComputedScale.covered * 4,
                  initialScale: PhotoViewComputedScale.contained,
                  heroAttributes: PhotoViewHeroAttributes(tag: widget.heroTag),
                  loadingBuilder: (_, _) => const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                  errorBuilder: (_, _, _) => const _MissingImagePlaceholder(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MissingImagePlaceholder extends StatelessWidget {
  const _MissingImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(
            Icons.broken_image_outlined,
            size: 64,
            color: Colors.white,
          ),
          const SizedBox(height: 12),
          Text(
            '图片文件已被删除',
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}

/// Returns the [PageRoute] used to push [ImagePreviewScreen] as a
/// fullscreen overlay. The route is opaque on a black barrier so the
/// transition feels like a sheet taking over the screen, and the call
/// sites consistently push it onto the root navigator (so it sits
/// above any tab bar).
Route<void> openImagePreviewRoute({
  required String imagePath,
  required Object heroTag,
}) {
  return PageRouteBuilder<void>(
    opaque: false,
    barrierColor: Colors.black,
    pageBuilder: (_, _, _) => ImagePreviewScreen(
      imagePath: imagePath,
      heroTag: heroTag,
    ),
  );
}
