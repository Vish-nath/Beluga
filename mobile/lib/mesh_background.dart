import 'dart:math';
import 'package:flutter/material.dart';

class MeshBackground extends StatefulWidget {
  final bool isDarkMode;
  const MeshBackground({required this.isDarkMode, super.key});

  @override
  State<MeshBackground> createState() => _MeshBackgroundState();
}

class _MeshBackgroundState extends State<MeshBackground> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 10))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          painter: _MeshPainter(
            isDarkMode: widget.isDarkMode,
            progress: _controller.value,
          ),
          size: Size.infinite,
        );
      },
    );
  }
}

class _MeshPainter extends CustomPainter {
  final bool isDarkMode;
  final double progress;

  _MeshPainter({required this.isDarkMode, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isDarkMode
            ? [
                const Color(0xff121412),
                const Color(0xff1c201e),
                const Color(0xff2a322e),
                const Color(0xff121412),
              ]
            : [
                const Color(0xffe0f7fa),
                const Color(0xffb2ebf2),
                const Color(0xff80deea),
                const Color(0xffe0f7fa),
              ],
        stops: const [0.0, 0.3, 0.7, 1.0],
        transform: GradientRotation(progress * 2 * pi),
      ).createShader(rect);

    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(covariant _MeshPainter oldDelegate) =>
      oldDelegate.isDarkMode != isDarkMode || oldDelegate.progress != progress;
}
