import 'package:flutter/material.dart';

import '../theme.dart';
import '../tokens.dart';

enum NLBadgeVariant { success, warning, error, info, muted }

/// 状态徽章：小字号（11px）、圆角 sm、可选状态点。文本用前景色，不用纯色字。
class NLBadge extends StatelessWidget {
  const NLBadge({super.key, required this.label, this.variant = NLBadgeVariant.muted, this.dot = false});

  final String label;
  final NLBadgeVariant variant;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    final c = context.nl;
    final (fg, bg) = switch (variant) {
      NLBadgeVariant.success => (c.success, c.successBg),
      NLBadgeVariant.warning => (c.warning, c.warningBg),
      NLBadgeVariant.error => (c.error, c.errorBg),
      NLBadgeVariant.info => (c.info, c.infoBg),
      NLBadgeVariant.muted => (c.mutedForeground, c.muted),
    };
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(NLRadii.radiusSm)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (dot) ...[
          Container(width: 6, height: 6, decoration: BoxDecoration(color: fg, shape: BoxShape.circle)),
          const SizedBox(width: 5),
        ],
        // Width-constrained parents (topbar Flexible) ellipsize instead of
        // overflowing.
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg),
          ),
        ),
      ]),
    );
  }
}
