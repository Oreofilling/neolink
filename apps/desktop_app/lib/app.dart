import 'dart:async';

import 'package:flutter/material.dart';
import 'package:neolink_ui/neolink_ui.dart';

import 'l10n/app_localizations.dart';
import 'provisioning/provisioning_controller.dart';
import 'services/settings_store.dart';
import 'services/wifi_settings_opener.dart';
import 'shell/shell.dart';

/// M0 空壳 + M2 会话接线：侧栏导航 + 顶栏主题/语言切换 + 相位驱动页面
/// （文案全部经 AppLocalizations，中英双语）。
///
/// 语言默认跟随系统首选语言列表（E5：不硬编码中文）；用户在顶栏切换后
/// 写入 %APPDATA% 持久化，重启保持。控制器默认自建（桌面真机依赖），
/// 测试可注入替身与禁用的设置存储。
class NeoLinkApp extends StatefulWidget {
  const NeoLinkApp({
    super.key,
    this.controller,
    this.settings,
    this.wifiSettingsOpener,
  });

  /// 测试注入用；为空时自建并随组件销毁释放。
  final ProvisioningController? controller;

  /// 设置存储；为空时用 %APPDATA% 默认路径，测试传 [SettingsStore.none]。
  final SettingsStore? settings;

  /// 直通扫描页的「打开系统 Wi-Fi 设置」动作（测试注入）。
  final WifiSettingsOpener? wifiSettingsOpener;

  @override
  State<NeoLinkApp> createState() => _NeoLinkAppState();
}

class _NeoLinkAppState extends State<NeoLinkApp> {
  ThemeMode _mode = ThemeMode.light;
  // null = 跟随系统首选语言列表（语言与主题均持久化，M2 注释承诺补齐）。
  Locale? _locale;
  ProvisioningController? _owned;
  late final SettingsStore _settings;

  ProvisioningController get _controller => widget.controller ?? _owned!;

  @override
  void initState() {
    super.initState();
    // The embedded web console (web mode) stays dormant for now: the
    // controller's webConsoleBuilder seam defaults to null, so a softAP
    // join opens the system browser instead. Re-wire
    // defaultWebConsoleBuilder() from services/device_web_console.dart
    // here to ship the embed.
    _owned = widget.controller == null ? ProvisioningController() : null;
    _settings = widget.settings ?? SettingsStore();
    final stored = _settings.load();
    if (stored?.theme != null) _mode = stored!.theme!;
    _locale = stored?.locale;
  }

  @override
  void dispose() {
    _owned?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (_) => 'NeoLink',
      debugShowCheckedModeBanner: false,
      theme: nlTheme(Brightness.light),
      darkTheme: nlTheme(Brightness.dark),
      themeMode: _mode,
      locale: _locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: AppShell(
        controller: _controller,
        dark: _mode == ThemeMode.dark,
        wifiSettingsOpener: widget.wifiSettingsOpener,
        onToggleTheme: () {
          setState(
            () => _mode = _mode == ThemeMode.light
                ? ThemeMode.dark
                : ThemeMode.light,
          );
          _persist();
        },
        // v6: the button shows the CURRENT interface language (state, not
        // target — a "中文" label while the UI is English reads as a bug);
        // tapping still swaps zh/en. The tooltip carries the action.
        langLabel: _effectiveLocale.languageCode == 'zh' ? '中文' : 'EN',
        onToggleLocale: () {
          setState(
            () => _locale = _effectiveLocale.languageCode == 'zh'
                ? const Locale('en')
                : const Locale('zh'),
          );
          _persist();
        },
      ),
    );
  }

  /// Currently shown locale: the explicit choice, or the first supported
  /// match against the system preference list.
  Locale get _effectiveLocale =>
      _locale ??
      basicLocaleListResolution(
        WidgetsBinding.instance.platformDispatcher.locales,
        AppLocalizations.supportedLocales,
      );

  void _persist() {
    unawaited(_settings.save(AppSettings(theme: _mode, locale: _locale)));
  }
}
