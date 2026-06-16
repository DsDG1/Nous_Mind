import 'package:flutter/material.dart';

/// 24x24 circular color dot with a soft `Colors.black26` border.
/// Used as the leading element in settings tiles that need to
/// surface a single representative color (seed color picker,
/// appearance swatch, etc.).
class ColorDot extends StatelessWidget {
  const ColorDot({super.key, required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black26),
      ),
    );
  }
}
