import 'package:discovery_domain/discovery_domain.dart';
import 'package:flutter/material.dart';
import 'package:neolink_ui/neolink_ui.dart';
import 'package:provisioning_session/provisioning_session.dart';

import '../app_metadata.dart';
import '../l10n/app_localizations.dart';
import '../provisioning/provisioning_controller.dart';
import '../services/wifi_settings_opener.dart';
import 'pages/config_page.dart';
import 'pages/connect_page.dart';
import 'pages/history_page.dart';
import 'pages/qr_guide_page.dart';
import 'pages/result_page.dart';
import 'pages/scan_page.dart';
import 'pages/selfcheck_page.dart';
import 'pages/settings_page.dart';

/// v6 shell: 3-destination sidebar (scan / history / settings) + topbar
/// (BLE adapter badge + session phase badge on the left, lang/theme on the
/// right). The scan destination hosts the phase-driven flow pages as one
/// full-page workspace; the QR guide is a shell-level page so the session
/// machine never needs guide phases for a UI-only walkthrough.
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.controller,
    required this.dark,
    required this.onToggleTheme,
    required this.langLabel,
    required this.onToggleLocale,
    this.wifiSettingsOpener,
  });

  final ProvisioningController controller;

  /// Passed through to the scan page (test injection).
  final WifiSettingsOpener? wifiSettingsOpener;

  final bool dark;
  final VoidCallback onToggleTheme;
  final String langLabel;
  final VoidCallback onToggleLocale;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  /// 'flow' (phase-driven workspace), 'qrguide', 'history', 'settings'.
  String _page = 'flow';
  SessionPhase _phase = SessionPhase.selfChecking;

  ProvisioningController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    // Phase-driven page following: jump only when the session phase actually
    // migrates. Plain refresh notifications (sweep ticks, staleness repaint,
    // recheck) must not drag the user off history/settings — round-2 A2.
    _phase = controller.phase;
    controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    final phase = controller.phase;
    if (phase == _phase) return;
    _phase = phase;
    // The guide belongs to the scan family; once the session moves past it
    // (candidate selected, link advancing) snap back to the flow workspace.
    final guideOrphan = _page == 'qrguide' && !_isScanFamilyPhase(phase);
    if (_page == 'flow' || guideOrphan) {
      setState(() {
        if (guideOrphan) _page = 'flow';
      });
    }
  }

  /// The scan family spans the whole discover loop, including the two
  /// transient phases: `cleaning` always lands back in scanning (it is the
  /// rescan path), so a guide open during a rescan must NOT be treated as
  /// orphaned — snapping it shut mid-walk made the empty-page "add by code"
  /// entry look dead (the guide opened and closed within one frame).
  static bool _isScanFamilyPhase(SessionPhase phase) => switch (phase) {
    SessionPhase.selfChecking ||
    SessionPhase.scanning ||
    SessionPhase.resultsAvailable ||
    SessionPhase.scanEmpty ||
    SessionPhase.guideScanning ||
    SessionPhase.showingGuide ||
    SessionPhase.cleaning => true,
    _ => false,
  };

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

  /// Phase-driven flow workspace under the scan destination.
  Widget _content() {
    switch (_page) {
      case 'flow':
        return switch (controller.pageForPhase) {
          'selfcheck' => SelfcheckPage(controller: controller),
          'connect' => ConnectPage(controller: controller),
          'config' => ConfigPage(controller: controller),
          'result' => ResultPage(controller: controller),
          _ => ScanPage(
              controller: controller,
              onOpenGuide: _openGuide,
              wifiSettingsOpener: widget.wifiSettingsOpener,
            ),
        };
      case 'qrguide':
        return QrGuidePage(
          controller: controller,
          onExit: () => setState(() => _page = 'flow'),
        );
      case 'history':
        return HistoryPage(controller: controller);
      case 'settings':
        return SettingsPage(
          controller: controller,
          dark: widget.dark,
          langLabel: widget.langLabel,
          onToggleTheme: widget.onToggleTheme,
          onToggleLocale: widget.onToggleLocale,
        );
      default:
        return ScanPage(
          controller: controller,
          onOpenGuide: _openGuide,
          wifiSettingsOpener: widget.wifiSettingsOpener,
        );
    }
  }

  void _openGuide() => setState(() => _page = 'qrguide');

  Widget _sidebar(NLColors c) {
    final l = AppLocalizations.of(context)!;
    // v7d: the sidebar narrows to 180 and gets its own surface (one step
    // above the page background, below cards) so the workspace reads as a
    // separate column instead of a stretched widget rail.
    return Container(
      width: 180,
      color: c.sidebar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Brand header gets extra breathing room above the nav — the
          // logo block is a header, not the first list row.
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 22, 14, 16),
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
                const SizedBox(height: 5),
                Text(
                  l.brandSubtitle,
                  style: NLType.aux.copyWith(color: c.mutedForeground),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              children: [
                _navItem(
                  c,
                  l.navScan,
                  icon: Icons.radar_outlined,
                  active: _page == 'flow' || _page == 'qrguide',
                  onTap: () => setState(() => _page = 'flow'),
                ),
                _navItem(
                  c,
                  l.navHistory,
                  icon: Icons.history,
                  active: _page == 'history',
                  onTap: () => setState(() => _page = 'history'),
                ),
                _navItem(
                  c,
                  l.navSettings,
                  icon: Icons.settings_outlined,
                  active: _page == 'settings',
                  onTap: () => setState(() => _page = 'settings'),
                ),
              ],
            ),
          ),
          _sidebarFooter(c, l),
        ],
      ),
    );
  }

  /// Fixed footer under the nav: the shipped version plus the BLE adapter
  /// state (mirrors the topbar badge so the sidebar stands alone). The
  /// version string also ships as the exe's version resource.
  Widget _sidebarFooter(NLColors c, AppLocalizations l) {
    final (label, color) = _bleState(l);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Divider(height: 1, thickness: 1, color: c.border),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'NeoLink v$appVersion',
                style: NLType.mono.copyWith(color: c.mutedForeground),
              ),
              const SizedBox(height: 5),
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: NLType.aux.copyWith(color: c.mutedForeground),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// BLE adapter readiness from the last environment report as a plain
  /// (label, dot-color) pair — shared by the topbar badge and the sidebar
  /// footer.
  (String, Color) _bleState(AppLocalizations l) {
    final c = context.nl;
    final entry = controller.environmentReport?.channels
        .where((channel) => channel.channel == DiscoveryChannel.ble)
        .firstOrNull;
    return switch (entry?.capability) {
      null => (l.topbarBleChecking, c.info),
      ChannelCapability.available => (l.topbarBleReady, c.success),
      ChannelCapability.limited => (l.topbarBleLimited, c.warning),
      ChannelCapability.unavailable => (l.topbarBleUnavailable, c.error),
    };
  }

  Widget _navItem(
    NLColors c,
    String label, {
    required IconData icon,
    required bool active,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: AnimatedContainer(
        duration: NLDurations.fast,
        decoration: BoxDecoration(
          // v7d: the active destination gets a very light cyan fill plus a
          // 3px brand-cyan bar on its left edge — the "you are here" mark
          // is cyan, never a status color.
          color: active ? c.accentCyanBg : Colors.transparent,
          borderRadius: BorderRadius.circular(NLRadii.radiusMd),
          border: Border(
            left: BorderSide(
              color: active ? c.accentCyan : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(NLRadii.radiusMd),
          child: InkWell(
            borderRadius: BorderRadius.circular(NLRadii.radiusMd),
            hoverColor: c.hoverBg,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: 16,
                    color: active ? c.accentCyan : c.mutedForeground,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: active ? c.foreground : c.mutedForeground,
                        fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
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
      child: Row(
        children: [
          // The badges group owns all free space so the two toggles hug the
          // right edge (v6 right-corner ask); each badge ellipsizes when the
          // bar gets narrow instead of pushing the toggles off-screen.
          Expanded(
            child: Row(
              children: [
                Flexible(child: _bleBadge(c, l)),
                const SizedBox(width: 8),
                Flexible(child: _phaseBadge(c, l)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Tooltip(
            // The label states the current language; the tooltip names the
            // action so the toggle never reads as a status-only chip.
            message: l.tipToggleLang,
            child: NLButton(
              label: widget.langLabel,
              icon: Icons.translate,
              variant: NLButtonVariant.ghost,
              size: NLButtonSize.sm,
              onPressed: widget.onToggleLocale,
            ),
          ),
          const SizedBox(width: 6),
          // v7c: the chip states the CURRENT theme (same convention as the
          // language button — a "Dark" chip on a light UI reads as a bug);
          // the tooltip names the action.
          Tooltip(
            message: l.tipToggleTheme,
            child: NLButton(
              label: widget.dark ? l.themeDark : l.themeLight,
              icon: widget.dark
                  ? Icons.dark_mode_outlined
                  : Icons.light_mode_outlined,
              variant: NLButtonVariant.ghost,
              size: NLButtonSize.sm,
              onPressed: widget.onToggleTheme,
            ),
          ),
        ],
      ),
    );
  }

  /// BLE adapter readiness straight from the last environment report (the
  /// provisioning link itself is covered by the phase badge).
  Widget _bleBadge(NLColors c, AppLocalizations l) {
    final entry = controller.environmentReport?.channels
        .where((channel) => channel.channel == DiscoveryChannel.ble)
        .firstOrNull;
    final variant = switch (entry?.capability) {
      null => NLBadgeVariant.info,
      ChannelCapability.available => NLBadgeVariant.success,
      ChannelCapability.limited => NLBadgeVariant.warning,
      ChannelCapability.unavailable => NLBadgeVariant.error,
    };
    final (label, _) = _bleState(l);
    return NLBadge(label: label, variant: variant, dot: entry == null);
  }

  Widget _phaseBadge(NLColors c, AppLocalizations l) {
    final phase = controller.phase;
    final label = switch (phase) {
      SessionPhase.selfChecking => l.tbStateSelfcheck,
      SessionPhase.scanEmpty => l.tbStateEmpty,
      SessionPhase.connecting ||
      SessionPhase.readingCapabilities => l.tbStateConnecting,
      SessionPhase.connectionError ||
      SessionPhase.capabilityError => l.tbStateConnectFailed,
      SessionPhase.choosingSections ||
      SessionPhase.editingConfig => l.tbStateConfig,
      SessionPhase.delivering => l.tbStateDelivering,
      SessionPhase.operationError => l.tbStateDeliverFailed,
      SessionPhase.completed => l.tbStateDone,
      _ => l.tbStateScanning,
    };
    final variant = switch (phase) {
      SessionPhase.connectionError ||
      SessionPhase.capabilityError ||
      SessionPhase.operationError => NLBadgeVariant.error,
      SessionPhase.completed => NLBadgeVariant.success,
      SessionPhase.connecting ||
      SessionPhase.readingCapabilities ||
      SessionPhase.delivering ||
      SessionPhase.selfChecking => NLBadgeVariant.info,
      _ => NLBadgeVariant.muted,
    };
    return NLBadge(label: label, variant: variant);
  }
}
