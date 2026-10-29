import 'package:flutter/material.dart';

import '../tokens.dart';

/// 静态卡片：仅边框、无阴影（NeoMind 规范）。[interactive] 提供手型光标（悬停描边动效 M2 完善）。
class NLCard extends StatelessWidget {
  const NLCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.interactive = false, this.onTap});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool interactive;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.nl;
    final card = DecoratedBox(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(NLRadii.radiusLg),
        border: Border.all(color: c.border),
      ),
      child: Padding(padding: padding, child: child),
    );
    if (onTap == null && !interactive) return card;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: card),
    );
  }
}
