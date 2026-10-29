import 'package:flutter/material.dart';

import '../tokens.dart';
import '../theme.dart';

/// 品牌标「链·N」：N 的对角线在中心断开，由节点圆续接——正在建立的链路。
///
/// - 单墨成立：accent 只允许出现在中心节点；
/// - 尺寸 < 26 自动切换简化形（连续对角线），保证 16/22px 可辨；
/// - [onPrimary] 用于主色砖反白场景，节点取砖面（暗/亮）对应的 accent 令牌。
class NLLogo extends StatelessWidget {
  const NLLogo({super.key, this.size = 22, this.onPrimary = false});

  final double size;
  final bool onPrimary;

  @override
  Widget build(BuildContext context) {
    final c = context.nl;
    final light = Theme.of(context).brightness == Brightness.light;
    final node = onPrimary
        ? (light ? NLColors.dark.accentCyan : NLColors.light.accentCyan)
        : c.accentCyan;
    return CustomPaint(
      size: Size.square(size),
      painter: _NLinkPainter(
        ink: onPrimary ? c.primaryForeground : c.foreground,
        node: node,
        simple: size < 26,
      ),
    );
  }
}

class _NLinkPainter extends CustomPainter {
  const _NLinkPainter({required this.ink, required this.node, required this.simple});

  final Color ink;
  final Color node;
  final bool simple;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 96;
    final paint = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = (simple ? 11 : 9) * s
      ..strokeCap = StrokeCap.round;
    void bar(double x) =>
        canvas.drawLine(Offset(x * s, 22 * s), Offset(x * s, 74 * s), paint);
    bar(24);
    bar(72);
    if (simple) {
      canvas.drawLine(Offset(24 * s, 22 * s), Offset(72 * s, 74 * s), paint);
    } else {
      canvas.drawLine(Offset(26 * s, 24 * s), Offset(40 * s, 39 * s), paint);
      canvas.drawLine(Offset(56 * s, 57 * s), Offset(70 * s, 72 * s), paint);
    }
    canvas.drawCircle(Offset(48 * s, 48 * s), 8 * s, Paint()..color = node);
  }

  @override
  bool shouldRepaint(_NLinkPainter old) =>
      old.ink != ink || old.node != node || old.simple != simple;
}
