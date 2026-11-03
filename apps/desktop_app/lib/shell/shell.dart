import 'package:flutter/material.dart';
import 'package:neolink_ui/neolink_ui.dart';
import 'package:provisioning_session/provisioning_session.dart';

import '../l10n/app_localizations.dart';
import '../l10n/labels.dart';
import '../provisioning/provisioning_controller.dart';
import 'pages.dart';
import 'pages/caps_page.dart';
import 'pages/connect_page.dart';
import 'pages/empty_page.dart';
import 'pages/form_page.dart';
import 'pages/result_page.dart';
import 'pages/scan_page.dart';
import 'pages/selfcheck_page.dart';

final class _NavItem {
  const _NavItem(this.id);
  final String id;
}

const _groups = <(String, List<_NavItem>)>[
  (
    'navGroupFlow',
    [
      _NavItem('selfcheck'),
      _NavItem('scan'),
      _NavItem('empty'),
      _NavItem('guide'),
      _NavItem('connect'),
      _NavItem('caps'),
    ],
  ),
  ('navGroupConfig', [_NavItem('wifi'), _NavItem('cat1'), _NavItem('svc')]),
  ('navGroupDeliver', [_NavItem('deliver'), _NavItem('result')]),
];

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.controller,
    required this.dark,
    required this.onToggleTheme,
    required this.langLabel,
    required this.onToggleLocale,
  });

  final ProvisioningController controller;
  final bool dark;
  final VoidCallback onToggleTheme;
  final String langLabel;
  final VoidCallback onToggleLocale;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  String _page = 'selfcheck';
  SessionPhase _phase = SessionPhase.selfChecking;

  @override
  void initState() {
    super.initState();
    // Phase-driven page following: jump only when the session phase actually
    // migrates (candidate found, link advancing). Plain refresh notifications
    // (scan sweep ticks, staleness re-render, recheck) must not drag the user
    // back to the phase page — round-2 A2 found the selfcheck page became
    // unreachable mid-scan because every notify reset the manual selection.
    _phase = widget.controller.phase;
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    final phase = widget.controller.phase;
    // Same phase = plain refresh: keep the user's manual page selection.
    if (phase == _phase) return;
    _phase = phase;
    final target = widget.controller.pageForPhase;
    if (target != _page) setState(() => _page = target);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nl;
    return Scaffold(
      backgroundColor: c.background,
      body: Row(
        children: [
          _sidebar(c),
          VerticalDivider(width: 1, thickness: 1, color: c.border),
          Expanded(
            child: Column(
              children: [
                _topbar(c),
                Divider(height: 1, thickness: 1, color: c.border),
                Expanded(child: _content()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Phase-driven pages; guide and per-section config pages stay behind
  /// later milestones.
  Widget _content() {
    switch (_page) {
      case 'selfcheck':
        return SelfcheckPage(controller: widget.controller);
      case 'scan':
        return ScanPage(controller: widget.controller);
      case 'empty':
        return EmptyPage(controller: widget.controller);
      case 'connect':
        return ConnectPage(controller: widget.controller);
      case 'caps':
        return CapsPage(controller: widget.controller);
      case 'deliver':
        return FormPage(controller: widget.controller);
      case 'result':
        return ResultPage(controller: widget.controller);
      default:
        return PlaceholderPage(pageId: _page);
    }
  }

  Widget _sidebar(NLColors c) {
    final l = AppLocalizations.of(context)!;
    return Container(
      width: 232,
      color: c.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    NLLogo(size: 22),
                    SizedBox(width: 8),
                    Text(
                      'NeoLink',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  l.brandSubtitle,
                  style: TextStyle(fontSize: 10, color: c.mutedForeground),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              children: [
                for (final (g, items) in _groups) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
                    child: Text(
                      l.groupLabel(g),
                      style: TextStyle(fontSize: 11, color: c.mutedForeground),
                    ),
                  ),
                  for (final it in items) _navItem(c, l, it),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _navItem(NLColors c, AppLocalizations l, _NavItem it) {
    final active = it.id == _page;
    // M2 起按会话相位解锁：自检恒可达；扫描/空态在离开自检后可达；
    // 连接与能力页仅在链路推进到对应阶段时开放（controller 判定）。
    final locked = !widget.controller.isNavUnlocked(it.id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: active ? c.muted : Colors.transparent,
        borderRadius: BorderRadius.circular(NLRadii.radiusMd),
        child: InkWell(
          borderRadius: BorderRadius.circular(NLRadii.radiusMd),
          onTap: locked ? null : () => setState(() => _page = it.id),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    l.navLabel(it.id),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: locked
                          ? c.mutedForeground
                          : (active ? c.foreground : c.mutedForeground),
                      fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
                if (locked) ...[
                  const Spacer(),
                  Text(
                    '·',
                    style: TextStyle(fontSize: 13, color: c.mutedForeground),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _topbar(NLColors c) {
    final l = AppLocalizations.of(context)!;
    // 链路存活期间（连接建立直到本次配置会话结束）顶栏亮已连接。
    final connected = switch (widget.controller.phase) {
      SessionPhase.connecting ||
      SessionPhase.readingCapabilities ||
      SessionPhase.choosingSections ||
      SessionPhase.editingConfig ||
      SessionPhase.delivering ||
      SessionPhase.completed ||
      SessionPhase.operationError => true,
      _ => false,
    };
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: c.background,
      child: Row(
        children: [
          NLBadge(
            label: connected ? l.topbarConnected : l.topbarNotConnected,
            variant: connected ? NLBadgeVariant.success : NLBadgeVariant.muted,
          ),
          const Spacer(),
          NLButton(
            label: widget.langLabel,
            variant: NLButtonVariant.ghost,
            size: NLButtonSize.sm,
            onPressed: widget.onToggleLocale,
          ),
          const SizedBox(width: 6),
          NLButton(
            label: widget.dark ? l.themeToLight : l.themeToDark,
            variant: NLButtonVariant.ghost,
            size: NLButtonSize.sm,
            onPressed: widget.onToggleTheme,
          ),
        ],
      ),
    );
  }
}
