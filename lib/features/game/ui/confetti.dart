import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// A lightweight confetti burst drawn with a [CustomPainter]. Driven by an
/// [AnimationController] (no timers), so tests can settle it.
class ConfettiBurst extends StatefulWidget {
  final Duration duration;
  final VoidCallback? onDone;
  final int pieces;

  const ConfettiBurst({
    super.key,
    this.duration = const Duration(milliseconds: 2200),
    this.onDone,
    this.pieces = 90,
  });

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<ConfettiBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  late final List<_Piece> _pieces;

  @override
  void initState() {
    super.initState();
    final rnd = math.Random(7);
    final colors = [
      AppColors.sunshine,
      AppColors.coral,
      AppColors.mint,
      AppColors.sky,
      AppColors.grape,
      ...HabitPalette.colors.take(4),
    ];
    _pieces = [
      for (var i = 0; i < widget.pieces; i++)
        _Piece(
          x: 0.5 + (rnd.nextDouble() - 0.5) * 0.3,
          vx: (rnd.nextDouble() - 0.5) * 1.4,
          vy: -0.9 - rnd.nextDouble() * 0.9,
          spin: (rnd.nextDouble() - 0.5) * 20,
          size: 6 + rnd.nextDouble() * 6,
          color: colors[i % colors.length],
        ),
    ];
    _controller.forward().whenCompleteOrCancel(() {
      if (mounted) widget.onDone?.call();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: RepaintBoundary(
      child: CustomPaint(
        key: const ValueKey('confetti'),
        size: Size.infinite,
        painter: _ConfettiPainter(_controller, _pieces),
      ),
    ),
  );
}

class _Piece {
  final double x, vx, vy, spin, size;
  final Color color;

  const _Piece({
    required this.x,
    required this.vx,
    required this.vy,
    required this.spin,
    required this.size,
    required this.color,
  });
}

class _ConfettiPainter extends CustomPainter {
  final Animation<double> t;
  final List<_Piece> pieces;

  _ConfettiPainter(this.t, this.pieces) : super(repaint: t);

  @override
  void paint(Canvas canvas, Size size) {
    final time = t.value * 2.2; // seconds-ish
    final fade = t.value < 0.75 ? 1.0 : (1 - t.value) / 0.25;
    final paint = Paint();
    for (final p in pieces) {
      // Launched from slightly below the middle, falling with gravity.
      final x = (p.x + p.vx * time * 0.35) * size.width;
      final y =
          (0.55 + p.vy * time * 0.45 + 0.6 * time * time * 0.45) * size.height;
      paint.color = p.color.withValues(alpha: fade.clamp(0.0, 1.0));
      canvas
        ..save()
        ..translate(x, y)
        ..rotate(p.spin * time);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset.zero,
            width: p.size,
            height: p.size * 0.5,
          ),
          const Radius.circular(2),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => false;
}
