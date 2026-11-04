import 'package:flutter/material.dart';

import '../theme.dart';
import '../tokens.dart';

enum NLButtonVariant { primary, secondary, ghost, destructive }
enum NLButtonSize { md, sm, xs }

/// 按钮体系：primary 单色实心 / secondary 仅边框 / ghost 透明 / destructive 错误实心。
/// 高度 md=40 / sm=36 / xs=28；悬停动效 M2 完善。
class NLButton extends StatelessWidget {
  const NLButton({super.key, required this.label, this.onPressed, this.icon, this.variant = NLButtonVariant.primary, this.size = NLButtonSize.md});

  final String label;
  final VoidCallback? onPressed;

  /// Optional leading icon (topbar toggles, decorated actions). Icon-only
  /// buttons stay outside this widget — keep a text label for accessibility.
  final IconData? icon;
  final NLButtonVariant variant;
  final NLButtonSize size;

  @override
  Widget build(BuildContext context) {
    final c = context.nl;
    final (h, fs) = switch (size) {
      NLButtonSize.md => (40.0, 14.0),
      NLButtonSize.sm => (36.0, 13.0),
      NLButtonSize.xs => (28.0, 12.0),
    };
    final (fg, bg, border) = switch (variant) {
      NLButtonVariant.primary => (c.primaryForeground, c.primary, false),
      NLButtonVariant.secondary => (c.foreground, Colors.transparent, true),
      NLButtonVariant.ghost => (c.mutedForeground, Colors.transparent, false),
      NLButtonVariant.destructive => (c.primaryForeground, c.error, false),
    };
    return MouseRegion(
      cursor: onPressed == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          height: h,
          padding: EdgeInsets.symmetric(horizontal: size == NLButtonSize.xs ? 10 : 14),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(NLRadii.radiusMd),
            border: border ? Border.all(color: c.border) : null,
          ),
          child: Center(
            // Icon (optional) rides ahead of the label at a size matched to
            // the button scale; color always follows the variant fg.
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: size == NLButtonSize.xs ? 14 : 16, color: fg),
                  const SizedBox(width: 6),
                ],
                Text(label, style: TextStyle(fontSize: fs, fontWeight: FontWeight.w600, color: fg)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
