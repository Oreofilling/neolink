import 'package:flutter/material.dart';

import 'tokens.dart';

/// NL 设计系统主题：静态卡片仅边框、下划线 tabs、单色 primary、骨架屏加载。
/// 状态/扩展色通过 ThemeExtension（NLColors）下发，Widget 用 context.nl 访问。
ThemeData nlTheme(Brightness brightness) {
  final colors = brightness == Brightness.light ? NLColors.light : NLColors.dark;
  final base = ThemeData(brightness: brightness, useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: colors.background,
    colorScheme: base.colorScheme.copyWith(
      primary: colors.primary,
      onPrimary: colors.primaryForeground,
      surface: colors.card,
      onSurface: colors.foreground,
      surfaceContainerHighest: colors.muted,
      onSurfaceVariant: colors.mutedForeground,
      error: colors.error,
      outline: colors.border,
      outlineVariant: colors.border,
    ),
    textTheme: base.textTheme.apply(
      bodyColor: colors.foreground,
      displayColor: colors.foreground,
      fontFamily: 'Plus Jakarta Sans',
      fontFamilyFallback: const ['Noto Sans SC', 'Microsoft YaHei'],
    ),
    dividerTheme: DividerThemeData(color: colors.border, thickness: 1, space: 1),
    tabBarTheme: const TabBarThemeData(
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: Colors.transparent,
    ),
    splashFactory: NoSplash.splashFactory,
    extensions: [colors],
  );
}

extension NLContext on BuildContext {
  /// 设计令牌快捷访问：`context.nl.primary`。
  NLColors get nl => Theme.of(this).extension<NLColors>()!;
}
