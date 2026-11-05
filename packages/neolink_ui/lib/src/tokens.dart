// v7d design pass (2026-11): hand-tuned from the v6 generated baseline.
// Source of truth is now docs/design-rules.md — do NOT regenerate with
// tool/gen_tokens.py (the mockup HTML no longer reflects this token set).
//
// Surface model (v7d): page background sits one step below cards so
// content lifts without shadows — light #F6F7F9 / dark #0B0D12; cards stay
// pure white / #12151B; hover + input surface #191D24 in dark. Brand cyan
// (#00919B / #14BBC2) is the ONLY focus/selection color; status colors
// (success/warning/error) never mix with it.
import 'package:flutter/material.dart';

/// 全量色彩令牌（亮/暗两套），经 ThemeExtension 注册；Widget 侧用 `context.nl.xxx` 访问。
class NLColors extends ThemeExtension<NLColors> {
  const NLColors({
    required this.accentCyan,
    required this.accentCyanBg,
    required this.accentEmerald,
    required this.accentEmeraldBg,
    required this.accentIndigo,
    required this.accentIndigoBg,
    required this.accentOrange,
    required this.accentOrangeBg,
    required this.accentPurple,
    required this.accentPurpleBg,
    required this.background,
    required this.border,
    required this.borderHover,
    required this.card,
    required this.cardForeground,
    required this.cardHoverBg,
    required this.destructive,
    required this.destructiveForeground,
    required this.error,
    required this.errorBg,
    required this.foreground,
    required this.hoverBg,
    required this.info,
    required this.infoBg,
    required this.muted,
    required this.mutedForeground,
    required this.primary,
    required this.primaryForeground,
    required this.ring,
    required this.secondary,
    required this.secondaryForeground,
    required this.sidebar,
    required this.success,
    required this.successBg,
    required this.warning,
    required this.warningBg,
  });

  final Color accentCyan;
  final Color accentCyanBg;
  final Color accentEmerald;
  final Color accentEmeraldBg;
  final Color accentIndigo;
  final Color accentIndigoBg;
  final Color accentOrange;
  final Color accentOrangeBg;
  final Color accentPurple;
  final Color accentPurpleBg;

  /// Page background — one step below [card] so content lifts by contrast.
  final Color background;

  /// Hairline border for cards and dividers.
  final Color border;

  /// Border color on hover (clickable rows, inputs, secondary buttons).
  final Color borderHover;
  final Color card;
  final Color cardForeground;
  final Color cardHoverBg;
  final Color destructive;
  final Color destructiveForeground;
  final Color error;
  final Color errorBg;
  final Color foreground;

  /// Row/list hover surface — flat fill, no border change implied.
  final Color hoverBg;
  final Color info;
  final Color infoBg;
  final Color muted;
  final Color mutedForeground;
  final Color primary;
  final Color primaryForeground;

  /// Legacy focus ring (foreground-tinted); keyboard focus uses
  /// [accentCyan] per the v7d rules — kept for the QR-locate marker.
  final Color ring;
  final Color secondary;
  final Color secondaryForeground;

  /// Sidebar surface — between background and card.
  final Color sidebar;
  final Color success;
  final Color successBg;
  final Color warning;
  final Color warningBg;

  static const light = NLColors(
    accentCyan: Color(0xFF00919B),
    accentCyanBg: Color(0x1A00919B),
    accentEmerald: Color(0xFF008D59),
    accentEmeraldBg: Color(0x1A008D59),
    accentIndigo: Color(0xFF4F42C9),
    accentIndigoBg: Color(0x1A4F42C9),
    accentOrange: Color(0xFFDA0000),
    accentOrangeBg: Color(0x1ADA0000),
    accentPurple: Color(0xFF7D40C8),
    accentPurpleBg: Color(0x1A7D40C8),
    background: Color(0xFFF6F7F9),
    border: Color(0x1D16181D),
    borderHover: Color(0x2E16181D),
    card: Color(0xFFFFFFFF),
    cardForeground: Color(0xFF16181D),
    cardHoverBg: Color(0xFFF6F7F9),
    destructive: Color(0xFFE7000F),
    destructiveForeground: Color(0xFFFFFFFF),
    error: Color(0xFFE7000F),
    errorBg: Color(0x14E7000F),
    foreground: Color(0xFF16181D),
    hoverBg: Color(0xFFF1F2F4),
    info: Color(0xFF00919B),
    infoBg: Color(0x1A00919B),
    muted: Color(0xFFF1F2F4),
    mutedForeground: Color(0xFF5A5E65),
    primary: Color(0xFF0C0E13),
    primaryForeground: Color(0xFFFFFFFF),
    ring: Color(0x5916181D),
    secondary: Color(0xFFF1F2F4),
    secondaryForeground: Color(0xFF16181D),
    sidebar: Color(0xFFFAFAFB),
    success: Color(0xFF008D59),
    successBg: Color(0x1A008D59),
    warning: Color(0xFFD29A00),
    warningBg: Color(0x24D29A00),
  );
  static const dark = NLColors(
    accentCyan: Color(0xFF14BBC2),
    accentCyanBg: Color(0x1F14BBC2),
    accentEmerald: Color(0xFF00C38B),
    accentEmeraldBg: Color(0x1F00C38B),
    accentIndigo: Color(0xFF878BF2),
    accentIndigoBg: Color(0x1F878BF2),
    accentOrange: Color(0xFFFB7852),
    accentOrangeBg: Color(0x1FFB7852),
    accentPurple: Color(0xFFB58BF9),
    accentPurpleBg: Color(0x1FB58BF9),
    background: Color(0xFF0B0D12),
    border: Color(0xFF262B34),
    borderHover: Color(0xFF343B46),
    card: Color(0xFF12151B),
    cardForeground: Color(0xFFEDEEF3),
    cardHoverBg: Color(0x0AFFFFFF),
    destructive: Color(0xFFE7000F),
    destructiveForeground: Color(0xFFFFFFFF),
    error: Color(0xFFFA5754),
    errorBg: Color(0x1FFA5754),
    foreground: Color(0xFFEDEEF3),
    hoverBg: Color(0xFF191D24),
    info: Color(0xFF14BBC2),
    infoBg: Color(0x1F14BBC2),
    muted: Color(0xFF191D24),
    mutedForeground: Color(0xFF898C95),
    primary: Color(0xFFEDEEF3),
    primaryForeground: Color(0xFF07080C),
    ring: Color(0x59EDEEF3),
    secondary: Color(0xFF191D24),
    secondaryForeground: Color(0xFFEDEEF3),
    sidebar: Color(0xFF0D1016),
    success: Color(0xFF00C38B),
    successBg: Color(0x1F00C38B),
    warning: Color(0xFFE3AE28),
    warningBg: Color(0x24E3AE28),
  );

  @override
  NLColors copyWith({
    Color? accentCyan,
    Color? accentCyanBg,
    Color? accentEmerald,
    Color? accentEmeraldBg,
    Color? accentIndigo,
    Color? accentIndigoBg,
    Color? accentOrange,
    Color? accentOrangeBg,
    Color? accentPurple,
    Color? accentPurpleBg,
    Color? background,
    Color? border,
    Color? borderHover,
    Color? card,
    Color? cardForeground,
    Color? cardHoverBg,
    Color? destructive,
    Color? destructiveForeground,
    Color? error,
    Color? errorBg,
    Color? foreground,
    Color? hoverBg,
    Color? info,
    Color? infoBg,
    Color? muted,
    Color? mutedForeground,
    Color? primary,
    Color? primaryForeground,
    Color? ring,
    Color? secondary,
    Color? secondaryForeground,
    Color? sidebar,
    Color? success,
    Color? successBg,
    Color? warning,
    Color? warningBg,
  }) => NLColors(
    accentCyan: accentCyan ?? this.accentCyan,
    accentCyanBg: accentCyanBg ?? this.accentCyanBg,
    accentEmerald: accentEmerald ?? this.accentEmerald,
    accentEmeraldBg: accentEmeraldBg ?? this.accentEmeraldBg,
    accentIndigo: accentIndigo ?? this.accentIndigo,
    accentIndigoBg: accentIndigoBg ?? this.accentIndigoBg,
    accentOrange: accentOrange ?? this.accentOrange,
    accentOrangeBg: accentOrangeBg ?? this.accentOrangeBg,
    accentPurple: accentPurple ?? this.accentPurple,
    accentPurpleBg: accentPurpleBg ?? this.accentPurpleBg,
    background: background ?? this.background,
    border: border ?? this.border,
    borderHover: borderHover ?? this.borderHover,
    card: card ?? this.card,
    cardForeground: cardForeground ?? this.cardForeground,
    cardHoverBg: cardHoverBg ?? this.cardHoverBg,
    destructive: destructive ?? this.destructive,
    destructiveForeground: destructiveForeground ?? this.destructiveForeground,
    error: error ?? this.error,
    errorBg: errorBg ?? this.errorBg,
    foreground: foreground ?? this.foreground,
    hoverBg: hoverBg ?? this.hoverBg,
    info: info ?? this.info,
    infoBg: infoBg ?? this.infoBg,
    muted: muted ?? this.muted,
    mutedForeground: mutedForeground ?? this.mutedForeground,
    primary: primary ?? this.primary,
    primaryForeground: primaryForeground ?? this.primaryForeground,
    ring: ring ?? this.ring,
    secondary: secondary ?? this.secondary,
    secondaryForeground: secondaryForeground ?? this.secondaryForeground,
    sidebar: sidebar ?? this.sidebar,
    success: success ?? this.success,
    successBg: successBg ?? this.successBg,
    warning: warning ?? this.warning,
    warningBg: warningBg ?? this.warningBg,
  );

  @override
  NLColors lerp(NLColors? other, double t) => other == null
      ? this
      : NLColors(
          accentCyan: Color.lerp(accentCyan, other.accentCyan, t)!,
          accentCyanBg: Color.lerp(accentCyanBg, other.accentCyanBg, t)!,
          accentEmerald: Color.lerp(accentEmerald, other.accentEmerald, t)!,
          accentEmeraldBg: Color.lerp(
            accentEmeraldBg,
            other.accentEmeraldBg,
            t,
          )!,
          accentIndigo: Color.lerp(accentIndigo, other.accentIndigo, t)!,
          accentIndigoBg: Color.lerp(accentIndigoBg, other.accentIndigoBg, t)!,
          accentOrange: Color.lerp(accentOrange, other.accentOrange, t)!,
          accentOrangeBg: Color.lerp(accentOrangeBg, other.accentOrangeBg, t)!,
          accentPurple: Color.lerp(accentPurple, other.accentPurple, t)!,
          accentPurpleBg: Color.lerp(accentPurpleBg, other.accentPurpleBg, t)!,
          background: Color.lerp(background, other.background, t)!,
          border: Color.lerp(border, other.border, t)!,
          borderHover: Color.lerp(borderHover, other.borderHover, t)!,
          card: Color.lerp(card, other.card, t)!,
          cardForeground: Color.lerp(cardForeground, other.cardForeground, t)!,
          cardHoverBg: Color.lerp(cardHoverBg, other.cardHoverBg, t)!,
          destructive: Color.lerp(destructive, other.destructive, t)!,
          destructiveForeground: Color.lerp(
            destructiveForeground,
            other.destructiveForeground,
            t,
          )!,
          error: Color.lerp(error, other.error, t)!,
          errorBg: Color.lerp(errorBg, other.errorBg, t)!,
          foreground: Color.lerp(foreground, other.foreground, t)!,
          hoverBg: Color.lerp(hoverBg, other.hoverBg, t)!,
          info: Color.lerp(info, other.info, t)!,
          infoBg: Color.lerp(infoBg, other.infoBg, t)!,
          muted: Color.lerp(muted, other.muted, t)!,
          mutedForeground: Color.lerp(
            mutedForeground,
            other.mutedForeground,
            t,
          )!,
          primary: Color.lerp(primary, other.primary, t)!,
          primaryForeground: Color.lerp(
            primaryForeground,
            other.primaryForeground,
            t,
          )!,
          ring: Color.lerp(ring, other.ring, t)!,
          secondary: Color.lerp(secondary, other.secondary, t)!,
          secondaryForeground: Color.lerp(
            secondaryForeground,
            other.secondaryForeground,
            t,
          )!,
          sidebar: Color.lerp(sidebar, other.sidebar, t)!,
          success: Color.lerp(success, other.success, t)!,
          successBg: Color.lerp(successBg, other.successBg, t)!,
          warning: Color.lerp(warning, other.warning, t)!,
          warningBg: Color.lerp(warningBg, other.warningBg, t)!,
        );
}

/// 圆角令牌（rem→logical px）。
abstract final class NLRadii {
  static const double radiusLg = 8;
  static const double radiusMd = 6;
  static const double radiusSm = 4;
  static const double radiusXl = 12;
}

/// 动画时长令牌（v7d: interaction motion stays in the 150–200ms band —
/// anything slower reads "web", not desktop）。
abstract final class NLDurations {
  static const fast = Duration(milliseconds: 150);
  static const normal = Duration(milliseconds: 300);
}

/// v7d typography scale (design rules): page title 22 / card title 15 /
/// body 13 / aux 11.5 / mono 11. Colors are call-site concerns — these
/// styles only fix size, weight and line height.
abstract final class NLType {
  /// Page title (scan / config / history headers).
  static const TextStyle pageTitle = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    height: 1.25,
  );

  /// One-line page subtitle under the title.
  static const TextStyle pageTitleSub = TextStyle(fontSize: 12.5, height: 1.4);

  /// Card / section title.
  static const TextStyle cardTitle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
  );

  /// Body copy and form labels.
  static const TextStyle body = TextStyle(fontSize: 13, height: 1.5);

  /// Secondary hints and metadata.
  static const TextStyle aux = TextStyle(fontSize: 11.5, height: 1.45);

  /// MAC suffixes, serials, protocol fields, timestamps.
  static const TextStyle mono = TextStyle(
    fontSize: 11,
    fontFamily: 'JetBrains Mono',
    height: 1.4,
  );
}

/// Shadow tokens (v7d): flat cards keep zero elevation — only overlays
/// (dialogs, popovers) get the light shadow so they read as floating
/// above the page, not as heavier cards.
abstract final class NLShadows {
  static const List<BoxShadow> overlay = [
    BoxShadow(color: Color(0x1F000000), blurRadius: 24, offset: Offset(0, 8)),
    BoxShadow(color: Color(0x14000000), blurRadius: 8, offset: Offset(0, 2)),
  ];
}
