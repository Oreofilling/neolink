import 'package:flutter/material.dart';

import '../tokens.dart';

/// 下划线 tabs（非胶囊）：指示线为前景色 2px，无背景条。
class NLTabBar extends StatelessWidget implements PreferredSizeWidget {
  const NLTabBar({super.key, required this.tabs, this.controller});

  final List<String> tabs;
  final TabController? controller;

  @override
  Size get preferredSize => const Size.fromHeight(40);

  @override
  Widget build(BuildContext context) {
    final c = context.nl;
    return TabBar(
      controller: controller,
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      dividerColor: Colors.transparent,
      indicator: UnderlineTabIndicator(borderSide: BorderSide(width: 2, color: c.foreground)),
      indicatorSize: TabBarIndicatorSize.label,
      labelColor: c.foreground,
      unselectedLabelColor: c.mutedForeground,
      labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      unselectedLabelStyle: const TextStyle(fontSize: 13),
      tabs: [for (final t in tabs) Tab(text: t)],
    );
  }
}
