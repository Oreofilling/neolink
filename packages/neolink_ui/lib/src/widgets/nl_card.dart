import 'package:flutter/material.dart';

import '../theme.dart';
import '../tokens.dart';

/// 静态卡片：仅边框、无阴影（NL 设计规范 v7d：内容靠底色差浮起，卡片不加投影）。
/// [interactive] 提供手型光标 + 悬停描边加深（150ms）；[elevated] 仅供弹窗/
/// 浮层使用（轻阴影，见 [NLShadows.overlay]）。
class NLCard extends StatefulWidget {
  const NLCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.interactive = false,
    this.onTap,
    this.elevated = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool interactive;
  final VoidCallback? onTap;

  /// Overlay surface (dialogs, popovers): card fill + light shadow instead
  /// of the flat border-only treatment.
  final bool elevated;

  @override
  State<NLCard> createState() => _NLCardState();
}

class _NLCardState extends State<NLCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final c = context.nl;
    final clickable = widget.onTap != null || widget.interactive;
    final highlight = clickable && _hovered;
    final card = AnimatedContainer(
      duration: NLDurations.fast,
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(NLRadii.radiusLg),
        border: Border.all(color: highlight ? c.borderHover : c.border),
        boxShadow: widget.elevated ? NLShadows.overlay : null,
      ),
      child: Padding(padding: widget.padding, child: widget.child),
    );
    if (!clickable) return card;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(onTap: widget.onTap, child: card),
    );
  }
}
