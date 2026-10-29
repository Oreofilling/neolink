import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:neolink_ui/neolink_ui.dart';

import 'shell/shell.dart';

/// M0 空壳：侧栏导航 + 顶栏主题/语言切换 + 页面占位（文案全部经 AppLocalizations，中英双语）。
class NeoLinkApp extends StatefulWidget {
  const NeoLinkApp({super.key});

  @override
  State<NeoLinkApp> createState() => _NeoLinkAppState();
}

class _NeoLinkAppState extends State<NeoLinkApp> {
  ThemeMode _mode = ThemeMode.light;
  Locale _locale = const Locale('zh'); // M2 起作为工具设置持久化

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (_, __) => 'NeoLink',
      debugShowCheckedModeBanner: false,
      theme: nlTheme(Brightness.light),
      darkTheme: nlTheme(Brightness.dark),
      themeMode: _mode,
      locale: _locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: AppShell(
        dark: _mode == ThemeMode.dark,
        onToggleTheme: () => setState(() => _mode = _mode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light),
        langLabel: _locale.languageCode == 'zh' ? 'EN' : '中文',
        onToggleLocale: () => setState(() => _locale = _locale.languageCode == 'zh' ? const Locale('en') : const Locale('zh')),
      ),
    );
  }
}
