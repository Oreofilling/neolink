import 'package:flutter/material.dart';

import '../tokens.dart';

/// 骨架屏（加载态不用转圈）：shimmer 渐变横移，动画只动 transform/渐变相位。
class NLSkeleton extends StatefulWidget {
  const NLSkeleton({super.key, this.width = double.infinity, this.height = 12, this.radius});

  final double width;
  final double height;
  final double? radius;

  @override
  State<NLSkeleton> createState() => _NLSkeletonState();
}

class _NLSkeletonState extends State<NLSkeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nl;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius ?? NLRadii.radiusSm),
          gradient: LinearGradient(
            begin: Alignment(-1 + 2 * _c.value, 0),
            end: Alignment(0 + 2 * _c.value, 0),
            colors: [c.muted, c.cardHoverBg, c.muted],
          ),
        ),
      ),
    );
  }
}
