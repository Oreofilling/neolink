import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import '../tokens.dart';

enum NLButtonVariant { primary, secondary, ghost, destructive }

enum NLButtonSize { md, sm, xs }

/// 按钮体系：primary 单色实心 / secondary 仅边框 / ghost 透明 / destructive 错误实心。
/// 高度 md=40 / sm=36 / xs=28。
///
/// v7d interaction states: hover and pressed each shift the surface one
/// step (overlay tint on solid variants, border + fill on outlined ones),
/// keyboard focus draws a brand-cyan ring, Enter/Space activate the focused
/// button, and every transition runs at [NLDurations.fast] — desktop
/// feedback, not web flourish.
class NLButton extends StatefulWidget {
  const NLButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.variant = NLButtonVariant.primary,
    this.size = NLButtonSize.md,
  });

  final String label;
  final VoidCallback? onPressed;

  /// Optional leading icon (topbar toggles, decorated actions). Icon-only
  /// buttons stay outside this widget — keep a text label for accessibility.
  final IconData? icon;
  final NLButtonVariant variant;
  final NLButtonSize size;

  @override
  State<NLButton> createState() => _NLButtonState();
}

class _NLButtonState extends State<NLButton> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  void _activate() {
    final onPressed = widget.onPressed;
    if (onPressed == null) return;
    onPressed();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nl;
    final (h, fs) = switch (widget.size) {
      NLButtonSize.md => (40.0, 14.0),
      NLButtonSize.sm => (36.0, 13.0),
      NLButtonSize.xs => (28.0, 12.0),
    };
    final enabled = widget.onPressed != null;

    // Solid variants tint toward their foreground on hover/press (light
    // buttons darken, dark buttons lighten — one code path for both
    // themes); outlined variants deepen the border and add a fill.
    final (baseFg, baseBg, outlined) = switch (widget.variant) {
      NLButtonVariant.primary => (c.primaryForeground, c.primary, false),
      NLButtonVariant.secondary => (c.foreground, Colors.transparent, true),
      NLButtonVariant.ghost => (c.mutedForeground, Colors.transparent, false),
      NLButtonVariant.destructive => (
        c.destructiveForeground,
        c.destructive,
        false,
      ),
    };
    final solidTint = widget.variant == NLButtonVariant.destructive
        ? c.destructiveForeground
        : c.primaryForeground;
    var fg = baseFg;
    var bg = baseBg;
    var borderColor = c.border;
    if (!enabled) {
      fg = baseFg.withValues(alpha: 0.45);
      borderColor = c.border.withValues(alpha: 0.6);
    } else if (_pressed) {
      if (outlined) {
        bg = c.hoverBg;
        borderColor = c.borderHover;
      } else {
        bg = Color.alphaBlend(solidTint.withValues(alpha: 0.16), baseBg);
      }
    } else if (_hovered) {
      if (outlined) {
        bg = c.cardHoverBg;
        borderColor = c.borderHover;
        if (widget.variant == NLButtonVariant.ghost) fg = c.foreground;
      } else {
        bg = Color.alphaBlend(solidTint.withValues(alpha: 0.08), baseBg);
      }
    }

    return FocusableActionDetector(
      enabled: enabled,
      mouseCursor: enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onShowHoverHighlight: (value) => setState(() => _hovered = value),
      onFocusChange: (value) => setState(() => _focused = value),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            _activate();
            return null;
          },
        ),
      },
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: () => setState(() => _pressed = false),
        onTap: _activate,
        child: AnimatedContainer(
          duration: NLDurations.fast,
          height: h,
          padding: EdgeInsets.symmetric(
            horizontal: widget.size == NLButtonSize.xs ? 10 : 14,
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(NLRadii.radiusMd),
            border: outlined ? Border.all(color: borderColor) : null,
            // Focus ring (v7d): a 1.5px brand-cyan spread hugging the box —
            // cyan is the one focus color, status colors never play this
            // role. Rendered as a zero-blur shadow so it never shifts size.
            boxShadow: _focused && enabled
                ? [
                    BoxShadow(
                      color: c.accentCyan.withValues(alpha: 0.75),
                      blurRadius: 0,
                      spreadRadius: 1.5,
                    ),
                  ]
                : null,
          ),
          child: Center(
            // Icon (optional) rides ahead of the label at a size matched to
            // the button scale; color always follows the variant fg.
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.icon != null) ...[
                  Icon(
                    widget.icon,
                    size: widget.size == NLButtonSize.xs ? 14 : 16,
                    color: fg,
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: fs,
                    fontWeight: FontWeight.w600,
                    color: fg,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
