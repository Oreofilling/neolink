import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:neolink_ui/neolink_ui.dart';

/// Scanning visual (v6): a rotating radar sweep whose beam lights up static
/// blips as it passes them — a nod to what the page actually does (listen on
/// three channels, mark what answers). Outline-only rings keep it inside the
/// NeoMind border-first system; the loop is infinite on purpose because the
/// scan itself is continuous.
class ScanRadar extends StatefulWidget {
  const ScanRadar({super.key, this.size = 200});

  final double size;

  @override
  State<ScanRadar> createState() => _ScanRadarState();
}

class _ScanRadarState extends State<ScanRadar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nl;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => CustomPaint(
        size: Size.square(widget.size),
        painter: _RadarPainter(
          progress: _controller.value,
          ring: c.border,
          sweep: c.info,
          blip: c.success,
        ),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter({
    required this.progress,
    required this.ring,
    required this.sweep,
    required this.blip,
  });

  final double progress;
  final Color ring;
  final Color sweep;
  final Color blip;

  /// Static blip positions as (radius fraction, angle fraction of a turn) —
  /// the beam re-lights each one on every pass.
  static const List<(double, double)> _blips = [
    (0.62, 0.18),
    (0.38, 0.55),
    (0.75, 0.82),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2 - 1;

    // Dish outline: three rings plus a faint crosshair, no fills.
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = ring;
    for (final factor in const [0.34, 0.67, 1.0]) {
      canvas.drawCircle(center, radius * factor, ringPaint);
    }
    final crossPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = ring.withValues(alpha: 0.5);
    canvas.drawLine(
      Offset(center.dx - radius, center.dy),
      Offset(center.dx + radius, center.dy),
      crossPaint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - radius),
      Offset(center.dx, center.dy + radius),
      crossPaint,
    );

    // Rotating comet: brightest at the beam angle, trailing off behind it.
    final angle = math.pi * 2 * progress;
    final sweepPaint = Paint()
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: math.pi * 2,
        colors: [sweep.withValues(alpha: 0), sweep.withValues(alpha: 0.26)],
        stops: const [0.72, 1.0],
        transform: GradientRotation(angle),
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, sweepPaint);

    // The beam edge itself — a hair brighter than the wedge tail.
    final beamPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = sweep.withValues(alpha: 0.85);
    canvas.drawLine(
      center,
      center + Offset(math.cos(angle), math.sin(angle)) * radius,
      beamPaint,
    );
    canvas.drawCircle(
      center,
      2.5,
      Paint()..color = sweep.withValues(alpha: 0.9),
    );

    // Blips: each lights up when the beam passes, then decays until the
    // next lap — the "device answered" moment, in miniature.
    for (final (radiusFraction, angleFraction) in _blips) {
      final sincePass = (progress - angleFraction) % 1.0;
      final glow = math.max(0.0, 1.0 - sincePass * 2.4);
      if (glow <= 0) continue;
      final position =
          center +
          Offset(
            math.cos(math.pi * 2 * angleFraction),
            math.sin(math.pi * 2 * angleFraction),
          ) *
              radius *
              radiusFraction;
      canvas.drawCircle(
        position,
        3.5,
        Paint()..color = blip.withValues(alpha: glow),
      );
      // Fresh catches get an expanding halo so the pass is noticeable.
      if (glow > 0.75) {
        canvas.drawCircle(
          position,
          7,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = blip.withValues(alpha: (glow - 0.75) * 1.6),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_RadarPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
