import 'dart:math';

import 'package:flutter/material.dart';

/// Clips a widget to a circle with the specified [center] and [radius].
///
/// When the radius is 0 the child is completely hidden; as it grows the
/// child becomes visible in an outward-spreading fashion.
///
/// Typically driven by an [AnimationController] to produce a material-style
/// circular-reveal transition.
class CircularRevealClipper extends CustomClipper<Path> {
  const CircularRevealClipper({required this.center, required this.radius});

  final Offset center;
  final double radius;

  @override
  Path getClip(Size size) =>
      Path()..addOval(Rect.fromCircle(center: center, radius: radius));

  @override
  bool shouldReclip(CircularRevealClipper oldClipper) =>
      center != oldClipper.center || radius != oldClipper.radius;
}

/// Wraps [child] in a [ClipPath] driven by [animation] so that it appears to
/// grow outward from [center].
///
/// The [animation] value should go from 0.0 (fully hidden) to 1.0 (fully
/// visible). Internally it multiplies the value by the screen diagonal so
/// the circle eventually covers every corner.
class CircularRevealTransition extends StatelessWidget {
  const CircularRevealTransition({
    super.key,
    required this.animation,
    required this.center,
    required this.child,
  });

  final Animation<double> animation;
  final Offset center;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final size = MediaQuery.of(context).size;
        // Compute the farthest distance from [center] to any corner so the
        // circle fully covers the screen at the end.
        final dx = max(center.dx, size.width - center.dx);
        final dy = max(center.dy, size.height - center.dy);
        final cornerRadius = sqrt(dx * dx + dy * dy);
        return ClipPath(
          clipper: CircularRevealClipper(
            center: center,
            radius: animation.value * cornerRadius,
          ),
          child: child,
        );
      },
      child: child,
    );
  }
}
