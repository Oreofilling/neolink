import 'package:flutter/material.dart';
import 'package:neolink_ui/neolink_ui.dart';

import 'l10n/app_localizations.dart';
import 'provisioning/provisioning_controller.dart';
import 'shell/shell.dart';

/// M0 空壳 + M2 会话接线：侧栏导航 + 顶栏主题/语言切换 + 相位驱动页面
/// （文案全部经 AppLocalizations，中英双语）。控制器默认自建（桌面真机
/// 依赖），测试可注入替身。
class NeoLinkApp extends StatefulWidget {
  const NeoLinkApp({super.key, this.controller});

  /// 测试注入用；为空时自建并随组件销毁释放。
  final ProvisioningController? controller;

  @override
  State<NeoLinkApp> createState() => _NeoLinkAppState();
}

class _NeoLinkAppState extends State<NeoLinkApp> {
  ThemeMode _mode = ThemeMode.light;
  Locale _locale = const Locale('zh'); // M2 起作为工具设置持久化
  ProvisioningController? _owned;

  ProvisioningController get _controller => widget.controller ?? _owned!;

  @override
  void initState() {
    super.initState();
    _owned = widget.controller == null ? ProvisioningController() : null;
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
        onToggleTheme: () => setState(
          () => _mode = _mode == ThemeMode.light
              ? ThemeMode.dark
              : ThemeMode.light,
        ),
        langLabel: _locale.languageCode == 'zh' ? 'EN' : '中文',
        onToggleLocale: () => setState(
          () => _locale = _locale.languageCode == 'zh'
              ? const Locale('en')
              : const Locale('zh'),
        ),
      ),
    );
  }
}
