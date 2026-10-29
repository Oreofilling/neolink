import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:neolink_ui/neolink_ui.dart';

import '../l10n/labels.dart';
import 'pages.dart';

final class _NavItem {
  const _NavItem(this.id, {this.locked = false});
  final String id;
  final bool locked;
}

const _groups = <(String, List<_NavItem>)>[
  ('navGroupFlow', [
    _NavItem('selfcheck'),
    _NavItem('scan'),
    _NavItem('empty'),
    _NavItem('guide'),
    _NavItem('connect', locked: true),
    _NavItem('caps', locked: true),
  ]),
  ('navGroupConfig', [
    _NavItem('wifi', locked: true),
    _NavItem('cat1', locked: true),
    _NavItem('svc', locked: true),
  ]),
  ('navGroupDeliver', [
    _NavItem('deliver', locked: true),
    _NavItem('result', locked: true),
  ]),
];

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.dark,
    required this.onToggleTheme,
    required this.langLabel,
    required this.onToggleLocale,
  });

  final bool dark;
  final VoidCallback onToggleTheme;
  final String langLabel;
  final VoidCallback onToggleLocale;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  String _page = 'selfcheck';

  @override
  Widget build(BuildContext context) {
    final c = context.nl;
    return Scaffold(
      backgroundColor: c.background,
      body: Row(
        children: [
          _sidebar(c),
          VerticalDivider(width: 1, thickness: 1, color: c.border),
          Expanded(child: Column(children: [
            _topbar(c),
            Divider(height: 1, thickness: 1, color: c.border),
            Expanded(child: PlaceholderPage(pageId: _page)),
          ])),
        ],
      ),
    );
  }

  Widget _sidebar(NLColors c) {
    final l = AppLocalizations.of(context)!;
    return Container(
      width: 232,
      color: c.card,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(width: 22, height: 22, decoration: BoxDecoration(color: c.primary, borderRadius: BorderRadius.circular(6))),
              const SizedBox(width: 8),
              Text('NeoLink', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 4),
            Text(l.brandSubtitle, style: TextStyle(fontSize: 10, color: c.mutedForeground)),
          ]),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            children: [
              for (final (g, items) in _groups) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
                  child: Text(l.groupLabel(g), style: TextStyle(fontSize: 11, color: c.mutedForeground)),
                ),
                for (final it in items) _navItem(c, l, it),
              ],
            ],
          ),
        ),
      ]),
    );
  }

  Widget _navItem(NLColors c, AppLocalizations l, _NavItem it) {
    final active = it.id == _page;
    final locked = it.locked; // M0：配置/下发组连接设备前置灰（M2 接入真实状态）
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: active ? c.muted : Colors.transparent,
        borderRadius: BorderRadius.circular(NLRadii.radiusMd),
        child: InkWell(
          borderRadius: BorderRadius.circular(NLRadii.radiusMd),
          onTap: () => setState(() => _page = it.id),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(children: [
              Text(l.navLabel(it.id),
                  style: TextStyle(
                      fontSize: 13,
                      color: locked ? c.mutedForeground : (active ? c.foreground : c.mutedForeground),
                      fontWeight: active ? FontWeight.w600 : FontWeight.w500)),
              if (locked) ...[const Spacer(), Text('·', style: TextStyle(fontSize: 13, color: c.mutedForeground))],
            ]),
          ),
        ),
      ),
    );
  }

  Widget _topbar(NLColors c) {
    final l = AppLocalizations.of(context)!;
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: c.background,
      child: Row(children: [
        NLBadge(label: l.topbarNotConnected, variant: NLBadgeVariant.muted),
        const Spacer(),
        NLButton(label: widget.langLabel, variant: NLButtonVariant.ghost, size: NLButtonSize.sm, onPressed: widget.onToggleLocale),
        const SizedBox(width: 6),
        NLButton(
          label: widget.dark ? l.themeToLight : l.themeToDark,
          variant: NLButtonVariant.ghost,
          size: NLButtonSize.sm,
          onPressed: widget.onToggleTheme,
        ),
      ]),
    );
  }
}
