import 'package:ap_discovery_adapter/ap_discovery_adapter.dart';
import 'package:discovery_domain/discovery_domain.dart';
import 'package:flutter/material.dart';
import 'package:neolink_ui/neolink_ui.dart';
import 'package:provisioning_session/provisioning_session.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/channel_labels.dart';
import '../../provisioning/provisioning_controller.dart';
import '../../services/environment_probe.dart';
import '../../services/wifi_settings_opener.dart';
import '../widgets/scan_radar.dart';

/// Device scan page (v6): a one-line channel status strip up top, then the
/// live device table as the first visual focus. Continuous scan semantics —
/// rows appear as devices are found and age out by TTL; the QR guide
/// highlight marks the row the user is looking for. Busy devices stay
/// visible but cannot be selected (§4.2.2).
///
/// v7d: the three channel cards collapsed into a compact strip (details on
/// demand via the toggle); rows fade in, hover-highlight and hold a quiet
/// connect action that only strengthens on hover/focus.
class ScanPage extends StatefulWidget {
  const ScanPage({
    super.key,
    required this.controller,
    this.onOpenGuide,
    this.wifiSettingsOpener,
  });

  final ProvisioningController controller;
  final VoidCallback? onOpenGuide;

  /// Test injection for the "open system Wi-Fi settings" action; null
  /// uses the real [openWifiSettings] service.
  final WifiSettingsOpener? wifiSettingsOpener;

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  /// Channel detail cards expanded (v7d). Collapsed by default — the
  /// device table is the page's business, the environment is a footnote.
  bool _channelsExpanded = false;

  /// Candidate whose row is under the pointer (v7d row emphasis).
  String? _hoveredCandidateId;

  /// Result-table view state (M5): the device / channel column headers
  /// double as dropdown filters (model family, discovery channel); the
  /// table pages once rows overflow one page.
  String? _modelFilter;
  DiscoveryChannel? _channelFilter;
  int _page = 0;
  static const int _pageSize = 8;

  ProvisioningController get controller => widget.controller;

  /// Launch failure is non-fatal (the OS owns that page); log and move
  /// on rather than surfacing a dead-end error dialog.
  Future<void> _openWifiSettings() async {
    final opener = widget.wifiSettingsOpener ?? openWifiSettings;
    try {
      await opener();
    } catch (error) {
      debugPrint('open Wi-Fi settings failed: $error');
    }
  }

  /// Pre-join consent for AP-only rows (M5): joining the device hotspot
  /// disconnects the machine's current Wi-Fi, so the dialog names both
  /// networks and promises the automatic restore. Cancel keeps the list.
  Future<void> _confirmApJoin(DiscoveryCandidate device) async {
    final ssid =
        apSsidFromCandidateId(device.candidateId) ?? device.candidateId;
    final current = await controller.currentWifiSsid();
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _apJoinDialog(dialogContext, ssid, current),
    );
    if (confirmed == true) {
      await controller.selectCandidate(device);
    }
  }

  Widget _apJoinDialog(BuildContext dialogContext, String ssid, String? current) {
    final dc = dialogContext.nl;
    final dl = AppLocalizations.of(dialogContext)!;
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(20),
        // v7d: only overlays get the light shadow — this one surface
        // floats, everything below stays flat.
        decoration: BoxDecoration(
          color: dc.card,
          borderRadius: BorderRadius.circular(NLRadii.radiusLg),
          boxShadow: NLShadows.overlay,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.wifi, size: 18, color: dc.accentCyan),
                const SizedBox(width: 8),
                Text(
                  dl.scanApDialogTitle,
                  style: NLType.cardTitle.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              dl.scanApDialogBody(ssid),
              style: NLType.body.copyWith(color: dc.mutedForeground),
            ),
            const SizedBox(height: 6),
            Text(
              current != null
                  ? dl.scanApDialogOffline(current)
                  : dl.scanApDialogNoCurrent,
              style: NLType.body.copyWith(color: dc.mutedForeground),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                NLButton(
                  label: dl.scanApDialogCancel,
                  variant: NLButtonVariant.ghost,
                  size: NLButtonSize.sm,
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                ),
                const SizedBox(width: 8),
                NLButton(
                  label: dl.scanApDialogConfirm,
                  size: NLButtonSize.sm,
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nl;
    final l = AppLocalizations.of(context)!;

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final scanning = controller.phase == SessionPhase.scanning;
        // v7c: empty result no longer swaps pages — the scan page shows the
        // no-devices hint in place; add-by-QR-code is the main way out
        // (wake the device -> enter its code -> connect) and rescan covers
        // "it just woke up".
        final empty = controller.phase == SessionPhase.scanEmpty;
        final candidates = controller.candidates;
        // v7c: the QR strip is pinned to the viewport bottom and never
        // scrolls with content — the empty panel or a long device table in
        // a short window (the 800x600 test canvas is the worst case) cannot
        // push it off-screen.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 960),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(l.scanTitle, style: NLType.pageTitle),
                          const SizedBox(width: 12),
                          if (scanning)
                            NLBadge(
                              label: l.badgeChecking,
                              variant: NLBadgeVariant.info,
                              dot: true,
                            )
                          else
                            NLBadge(
                              label: l.scanCandidateCount(candidates.length),
                              variant: NLBadgeVariant.muted,
                            ),
                          const Spacer(),
                          NLButton(
                            label: l.scanRescan,
                            variant: NLButtonVariant.secondary,
                            size: NLButtonSize.sm,
                            onPressed: controller.rescan,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        l.scanSub,
                        style: NLType.pageTitleSub.copyWith(
                          color: c.mutedForeground,
                        ),
                      ),
                      const SizedBox(height: 14),
                      _channelSection(c, l, candidates),
                      const SizedBox(height: 14),
                      // M5: the QR doorway is no longer a pinned boxed
                      // strip (it competed with the rows); it lives inside
                      // the empty panel and as a quiet footnote under the
                      // table. The radar state carries no entry at all.
                      if (empty)
                        _emptyPanel(c, l)
                      else if (candidates.isEmpty && scanning)
                        _scanningPanel(c, l)
                      else
                        _resultsSection(c, l, candidates),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Empty-result panel (v7c): the scan window burnt out with nothing
  /// found — the hint lives on this page (no separate empty screen). The
  /// QR strip below and the header rescan cover the actions.
  Widget _emptyPanel(NLColors c, AppLocalizations l) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(NLRadii.radiusLg),
      ),
      padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 20),
      child: Column(
        children: [
          Icon(Icons.wifi_find_outlined, size: 30, color: c.mutedForeground),
          const SizedBox(height: 12),
          Text(
            l.emptyTitle,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            l.emptyHint,
            textAlign: TextAlign.center,
            style: NLType.aux.copyWith(color: c.mutedForeground),
          ),
          const SizedBox(height: 14),
          // The empty state's way out: wake the device and add it by code.
          NLButton(
            label: l.btnQrAddShort,
            variant: NLButtonVariant.secondary,
            size: NLButtonSize.sm,
            onPressed: widget.onOpenGuide,
          ),
        ],
      ),
    );
  }

  /// In-flight panel (v6): radar sweep instead of generic skeleton rows —
  /// the beam re-lights a blip on every lap, echoing "listening for
  /// answers" rather than "loading bytes".
  Widget _scanningPanel(NLColors c, AppLocalizations l) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(NLRadii.radiusLg),
      ),
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        children: [
          const ScanRadar(size: 180),
          const SizedBox(height: 14),
          NLBadge(
            label: l.badgeChecking,
            variant: NLBadgeVariant.info,
            dot: true,
          ),
          const SizedBox(height: 8),
          Text(
            l.scanRadarHint,
            style: NLType.aux.copyWith(color: c.mutedForeground),
          ),
        ],
      ),
    );
  }

  /// Channel environment (v7d): one compact status strip by default —
  /// "BLE 可用 · AP 受限 · CT-Disc 不可用" at a glance; 查看详情 unfolds
  /// the three detail cards. Readiness dot colors follow the status
  /// palette (green/amber/red), never brand cyan.
  Widget _channelSection(
    NLColors c,
    AppLocalizations l,
    List<DiscoveryCandidate> candidates,
  ) {
    final report = controller.environmentReport;
    final channels = report?.channels ?? const <ChannelReadiness>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: c.border),
            borderRadius: BorderRadius.circular(NLRadii.radiusLg),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (var i = 0; i < channels.length; i++) ...[
                      if (i > 0)
                        Text(
                          '·',
                          style: NLType.aux.copyWith(color: c.mutedForeground),
                        ),
                      _channelSegment(c, l, channels[i]),
                    ],
                  ],
                ),
              ),
              NLButton(
                label: _channelsExpanded
                    ? l.scanChannelsLess
                    : l.scanChannelsMore,
                icon: _channelsExpanded ? Icons.expand_less : Icons.expand_more,
                variant: NLButtonVariant.ghost,
                size: NLButtonSize.xs,
                onPressed: () =>
                    setState(() => _channelsExpanded = !_channelsExpanded),
              ),
            ],
          ),
        ),
        if (_channelsExpanded) ...[
          const SizedBox(height: 10),
          _channelCards(c, l, candidates),
        ],
      ],
    );
  }

  /// One "channel state" segment of the compact strip: status dot + short
  /// channel name + readiness word.
  Widget _channelSegment(
    NLColors c,
    AppLocalizations l,
    ChannelReadiness entry,
  ) {
    final color = switch (entry.capability) {
      ChannelCapability.available => c.success,
      ChannelCapability.limited => c.warning,
      ChannelCapability.unavailable => c.error,
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          '${_shortChannel(l, entry.channel)} ${l.capabilityLabel(entry.capability)}',
          style: NLType.aux.copyWith(color: c.mutedForeground),
        ),
      ],
    );
  }

  /// One card per discovery channel: readiness + live candidate count +
  /// the remark line from the mockup copy (v7d: shown only expanded).
  Widget _channelCards(
    NLColors c,
    AppLocalizations l,
    List<DiscoveryCandidate> candidates,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columnWidth = (constraints.maxWidth - 24) / 3;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final entry
                in controller.environmentReport?.channels ??
                    const <ChannelReadiness>[])
              SizedBox(
                width: columnWidth.clamp(220.0, double.infinity),
                child: _channelCard(c, l, entry, candidates),
              ),
          ],
        );
      },
    );
  }

  Widget _channelCard(
    NLColors c,
    AppLocalizations l,
    ChannelReadiness entry,
    List<DiscoveryCandidate> candidates,
  ) {
    final count = candidates
        .where((candidate) => candidate.channels.contains(entry.channel))
        .length;
    final variant = switch (entry.capability) {
      ChannelCapability.available => NLBadgeVariant.success,
      ChannelCapability.limited => NLBadgeVariant.warning,
      ChannelCapability.unavailable => NLBadgeVariant.error,
    };
    final remark = switch (entry.channel) {
      DiscoveryChannel.ble => l.chRemarkBle,
      DiscoveryChannel.accessPoint => l.chRemarkAp,
      DiscoveryChannel.ctDisc => l.chRemarkDisc,
    };
    return NLCard(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  switch (entry.channel) {
                    DiscoveryChannel.ble => Icons.bluetooth,
                    DiscoveryChannel.accessPoint => Icons.wifi,
                    DiscoveryChannel.ctDisc => Icons.hub_outlined,
                  },
                  size: 15,
                  color: c.mutedForeground,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l.channelLabel(entry.channel),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NLType.cardTitle,
                  ),
                ),
                NLBadge(label: l.chCount(count), variant: NLBadgeVariant.muted),
              ],
            ),
            const SizedBox(height: 8),
            NLBadge(
              label: entry.capability == ChannelCapability.available
                  ? l.chActive
                  : l.capabilityLabel(entry.capability),
              variant: variant,
              dot: entry.capability == ChannelCapability.available,
            ),
            const SizedBox(height: 8),
            Text(remark, style: NLType.aux.copyWith(color: c.mutedForeground)),
            // M5 task 1: a disabled WLAN adapter is user-fixable, so the
            // degraded card offers the system Wi-Fi page directly.
            if (entry.channel == DiscoveryChannel.accessPoint &&
                entry.reason == kWlanDisabledReason) ...[
              const SizedBox(height: 8),
              NLButton(
                label: l.scanChannelOpenWifiSettings,
                icon: Icons.open_in_new,
                variant: NLButtonVariant.ghost,
                size: NLButtonSize.xs,
                onPressed: _openWifiSettings,
              ),
            ],
            // §13.1: with several NICs / VPN / virtual adapters around, the
            // user can see which interfaces (and subnets) the listener
            // joined. Hidden while empty (before the scan starts).
            if (entry.channel == DiscoveryChannel.ctDisc &&
                controller.ctDiscNicLabels.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final label in controller.ctDiscNicLabels)
                    Text(
                      label,
                      style: NLType.mono.copyWith(color: c.mutedForeground),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Rows passing the header dropdown filters (model family + channel).
  List<DiscoveryCandidate> _filteredRows(
    List<DiscoveryCandidate> candidates, {
    String? modelFilter,
    DiscoveryChannel? channelFilter,
  }) {
    return [
      for (final device in candidates)
        if (modelFilter == null || device.modelHint == modelFilter)
          if (channelFilter == null ||
              device.channels.contains(channelFilter))
            device,
    ];
  }

  /// Model families the live list can offer (unknowns last) — the device
  /// column dropdown never shows a family nothing answers on.
  List<String> _modelOptions(List<DiscoveryCandidate> candidates) {
    final hints = candidates.map((device) => device.modelHint ?? '').toSet();
    final known = hints.where((model) => model.isNotEmpty).toList()..sort();
    return hints.contains('') ? [...known, ''] : known;
  }

  /// Discovery channels present in the live list, in enum order.
  List<DiscoveryChannel> _channelOptions(List<DiscoveryCandidate> candidates) {
    return [
      for (final channel in DiscoveryChannel.values)
        if (candidates.any((d) => d.channels.contains(channel))) channel,
    ];
  }

  /// Results area (M5): match badge while a dropdown filter is active, one
  /// page of rows, then a single bottom line — pager on the left, the quiet
  /// QR doorway on the right. The QR focus wins the page choice — a
  /// highlighted row on another page jumps into view instead of hiding
  /// behind the pager.
  Widget _resultsSection(
    NLColors c,
    AppLocalizations l,
    List<DiscoveryCandidate> candidates,
  ) {
    // A filter can outlive its rows after a rescan — treat a selection
    // nothing currently answers on as "no filter" rather than an empty
    // table the user cannot explain.
    final modelFilter = _modelOptions(candidates).contains(_modelFilter)
        ? _modelFilter
        : null;
    final channelFilter = _channelOptions(candidates).contains(_channelFilter)
        ? _channelFilter
        : null;
    final filtering = modelFilter != null || channelFilter != null;
    final filtered = _filteredRows(
      candidates,
      modelFilter: modelFilter,
      channelFilter: channelFilter,
    );
    final totalPages = filtered.isEmpty
        ? 1
        : (filtered.length / _pageSize).ceil();
    final focusedIndex = controller.qrFocusSuffix == null
        ? -1
        : filtered.indexWhere(
            (device) => device.macSuffix == controller.qrFocusSuffix,
          );
    final page = (focusedIndex >= 0 ? focusedIndex ~/ _pageSize : _page)
        .clamp(0, totalPages - 1);
    final visible = filtered
        .skip(page * _pageSize)
        .take(_pageSize)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (filtering) ...[
          NLBadge(
            label: l.scanFilterCount(filtered.length, candidates.length),
            variant: NLBadgeVariant.muted,
          ),
          const SizedBox(height: 8),
        ],
        _deviceTable(
          c,
          l,
          visible,
          allCandidates: candidates,
          modelFilter: modelFilter,
          channelFilter: channelFilter,
          allMatched: filtered.isNotEmpty,
        ),
        _tableFooter(c, l, page: page, totalPages: totalPages),
      ],
    );
  }

  /// One quiet bottom line under the table: the pager on the left, the QR
  /// doorway on the right — sharing a row keeps the area on one baseline
  /// instead of two ragged rows. The pager always renders (its buttons
  /// disable at the bounds) so the page state stays visible even when all
  /// rows fit on a single page.
  Widget _tableFooter(
    NLColors c,
    AppLocalizations l, {
    required int page,
    required int totalPages,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          _tablePager(c, l, page: page, totalPages: totalPages),
          const Spacer(),
          Text(
            l.noHit,
            style: NLType.aux.copyWith(color: c.mutedForeground),
          ),
          const SizedBox(width: 6),
          _footnoteLink(c, l),
        ],
      ),
    );
  }

  /// The footnote's QR doorway: same type size as the question beside it,
  /// bold + accent + underline — reads as a link without dragging button
  /// chrome onto this quiet line.
  Widget _footnoteLink(NLColors c, AppLocalizations l) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onOpenGuide,
        child: Text(
          l.btnQrAddShort,
          style: NLType.aux.copyWith(
            fontWeight: FontWeight.w700,
            color: c.accentCyan,
            decoration: TextDecoration.underline,
            decorationColor: c.accentCyan,
          ),
        ),
      ),
    );
  }

  /// Pager on the footer line — ghost buttons + "page x of y".
  Widget _tablePager(
    NLColors c,
    AppLocalizations l, {
    required int page,
    required int totalPages,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        NLButton(
          label: l.scanPrevPage,
          icon: Icons.chevron_left,
          variant: NLButtonVariant.ghost,
          size: NLButtonSize.xs,
          onPressed: page > 0 ? () => setState(() => _page = page - 1) : null,
        ),
        const SizedBox(width: 10),
        Text(
          l.scanPageInfo(page + 1, totalPages),
          style: NLType.aux.copyWith(color: c.mutedForeground),
        ),
        const SizedBox(width: 10),
        NLButton(
          label: l.scanNextPage,
          icon: Icons.chevron_right,
          variant: NLButtonVariant.ghost,
          size: NLButtonSize.xs,
          onPressed: page < totalPages - 1
              ? () => setState(() => _page = page + 1)
              : null,
        ),
      ],
    );
  }

  /// Sentinel menu value for the "match everything" choice. PopupMenuButton
  /// routes a null pop value to onCanceled (same as tapping outside the
  /// menu), so the all-option needs a real value that onSelected maps back
  /// to "no filter".
  static const String kFilterAll = '\u0000all';

  /// Column-header dropdown (M5): the closed state keeps the column name;
  /// picking a value filters the table and recolors the header to signal
  /// the active filter. The open menu is themed to the page tokens — flat
  /// border-only card, compact rows, a tiny accent dot as the selected
  /// mark — instead of the default Material checkmark surface.
  Widget _headerDropdown({
    required NLColors c,
    required String keyName,
    required String closedLabel,
    required String allLabel,
    required Map<String, String> options,
    required String? selected,
    required ValueChanged<String> onSelected,
  }) {
    final active = selected != null && options.containsKey(selected);
    return Theme(
      data: Theme.of(context).copyWith(
        popupMenuTheme: PopupMenuThemeData(
          color: c.card,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(NLRadii.radiusMd),
            side: BorderSide(color: c.border),
          ),
        ),
      ),
      child: PopupMenuButton<String>(
        key: ValueKey(keyName),
        padding: EdgeInsets.zero,
        initialValue: active ? selected : kFilterAll,
        onSelected: onSelected,
        tooltip: closedLabel,
        position: PopupMenuPosition.under,
        constraints: const BoxConstraints(minWidth: 132),
        itemBuilder: (context) => [
          _filterMenuRow(c, kFilterAll, allLabel, checked: !active),
          for (final entry in options.entries)
            _filterMenuRow(
              c,
              entry.key,
              entry.value,
              checked: active && entry.key == selected,
            ),
        ],
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              active ? options[selected]! : closedLabel,
              style: NLType.aux.copyWith(
                fontWeight: FontWeight.w600,
                color: active ? c.accentCyan : c.mutedForeground,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.expand_more,
              size: 14,
              color: active ? c.accentCyan : c.mutedForeground,
            ),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<String> _filterMenuRow(
    NLColors c,
    String value,
    String label, {
    required bool checked,
  }) {
    return PopupMenuItem<String>(
      key: ValueKey('filter-option-$value'),
      value: value,
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Selected mark: a 5px accent dot — quieter than a Material
          // checkmark and in the same accent language as the rest of the
          // page.
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: checked ? c.accentCyan : Colors.transparent,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: NLType.aux.copyWith(
              fontWeight: checked ? FontWeight.w700 : FontWeight.w500,
              color: checked ? c.accentCyan : c.foreground,
            ),
          ),
        ],
      ),
    );
  }

  Widget _deviceTable(
    NLColors c,
    AppLocalizations l,
    List<DiscoveryCandidate> rows, {
    required List<DiscoveryCandidate> allCandidates,
    String? modelFilter,
    DiscoveryChannel? channelFilter,
    bool allMatched = true,
  }) {
    final modelOptions = _modelOptions(allCandidates);
    final channelOptions = _channelOptions(allCandidates);
    return NLCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          // Header row. The device / channel headers are the dropdown
          // filters (M5) — the columns they filter are the ones they name.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: _headerDropdown(
                    c: c,
                    keyName: 'scan-model-filter',
                    closedLabel: l.tbDevice,
                    allLabel: l.scanFilterAllModels,
                    options: {
                      for (final model in modelOptions)
                        model: model.isEmpty ? l.scanUnknownModel : model,
                    },
                    selected: modelFilter,
                    onSelected: (value) => setState(() {
                      _modelFilter = value == kFilterAll ? null : value;
                      _page = 0; // a fresh filter starts on the first page
                    }),
                  ),
                ),
                SizedBox(
                  width: 92,
                  child: _headerDropdown(
                    c: c,
                    keyName: 'scan-channel-filter',
                    closedLabel: l.tbChannel,
                    allLabel: l.scanFilterAllChannels,
                    options: {
                      for (final channel in channelOptions)
                        channel.name: _shortChannel(l, channel),
                    },
                    selected: channelFilter?.name,
                    onSelected: (value) => setState(() {
                      _channelFilter = value == kFilterAll
                          ? null
                          : DiscoveryChannel.values.byName(value);
                      _page = 0;
                    }),
                  ),
                ),
                SizedBox(width: 120, child: _headText(c, l.tbSignalCol)),
                SizedBox(width: 110, child: _headText(c, l.tbStatus)),
                Expanded(flex: 2, child: _headText(c, l.tbLastSeen)),
                SizedBox(width: 84, child: _headText(c, l.tbAction)),
              ],
            ),
          ),
          Divider(height: 1, thickness: 1, color: c.border),
          if (!allMatched && rows.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
                child: Text(
                  l.scanNoMatch,
                  style: NLType.aux.copyWith(color: c.mutedForeground),
                ),
              )
            else
              for (final candidate in rows)
                _deviceRow(
                  c,
                  l,
                  candidate,
                  hovered: _hoveredCandidateId == candidate.candidateId,
                ),
        ],
      ),
    );
  }

  Widget _headText(NLColors c, String text) => Text(
    text,
    style: NLType.aux.copyWith(
      fontWeight: FontWeight.w600,
      color: c.mutedForeground,
    ),
  );

  /// One device row (v7d): fade+slide in on arrival, hover surface, QR
  /// focus painted as a cyan left bar over a light cyan fill (was: ring
  /// border), and the connect action staying quiet until the row is
  /// hovered — a full column of primary buttons is noise, one strengthened
  /// button under the pointer is a target.
  Widget _deviceRow(
    NLColors c,
    AppLocalizations l,
    DiscoveryCandidate device, {
    required bool hovered,
  }) {
    final selectable = device.provisionable && !device.busy;
    // M5: BLE rows connect straight through the GATT chain; AP-only rows
    // go through the join dialog first (the machine's Wi-Fi moves — the
    // user must know). CT-Disc-only rows stay display candidates until
    // their transport lands.
    final bleConnectable = device.channels.contains(DiscoveryChannel.ble);
    final apConnectable = !bleConnectable &&
        device.channels.contains(DiscoveryChannel.accessPoint);
    final age = DateTime.now().difference(device.lastSeen);
    final stale = age > controller.ttl;
    final focused =
        device.macSuffix != null &&
        device.macSuffix == controller.qrFocusSuffix;
    final signal = device.signal;
    return TweenAnimationBuilder<double>(
      key: ValueKey('row-${device.candidateId}'),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 200),
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 4 * (1 - t)),
          child: child,
        ),
      ),
      child: MouseRegion(
        onEnter: (_) =>
            setState(() => _hoveredCandidateId = device.candidateId),
        onExit: (_) => setState(() => _hoveredCandidateId = null),
        child: Column(
          children: [
            AnimatedContainer(
              duration: NLDurations.fast,
              decoration: BoxDecoration(
                color: focused
                    ? c.accentCyanBg
                    : hovered
                    ? c.hoverBg
                    : Colors.transparent,
                // A transparent 3px left border on every row keeps the
                // column aligned when the focused row shows its cyan bar.
                border: Border(
                  left: BorderSide(
                    color: focused ? c.accentCyan : Colors.transparent,
                    width: 3,
                  ),
                ),
              ),
              child: Opacity(
                opacity: stale ? 0.62 : 1,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    device.modelHint ?? l.scanUnknownModel,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                if (focused) ...[
                                  const SizedBox(width: 6),
                                  NLBadge(
                                    label: l.qrLocated,
                                    variant: NLBadgeVariant.info,
                                  ),
                                ],
                              ],
                            ),
                            if (device.macSuffix != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                device.macSuffix!,
                                style: NLType.mono.copyWith(
                                  color: c.mutedForeground,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 92,
                        child: Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            for (final channel in device.channels)
                              Text(
                                _shortChannel(l, channel),
                                style: NLType.mono.copyWith(
                                  color: c.mutedForeground,
                                ),
                              ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 120,
                        child: signal == null
                            ? Text(
                                '—',
                                style: NLType.aux.copyWith(
                                  color: c.mutedForeground,
                                ),
                              )
                            : Row(
                                children: [
                                  SignalBars(signal: signal),
                                  const SizedBox(width: 8),
                                  Text(
                                    l.scanSignal(signal),
                                    style: NLType.mono.copyWith(
                                      color: c.mutedForeground,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                      SizedBox(
                        width: 110,
                        child: stale
                            ? NLBadge(
                                label: l.scanStale,
                                variant: NLBadgeVariant.warning,
                              )
                            : device.busy
                            ? NLBadge(
                                label: l.scanBusy,
                                variant: NLBadgeVariant.error,
                              )
                            : !device.provisionable
                            ? NLBadge(
                                label: l.scanNotProvisionable,
                                variant: NLBadgeVariant.warning,
                              )
                            // v6: a healthy connectable row gets a positive
                            // mark too — but quiet: bare dot + muted text,
                            // no chip background (exception states keep the
                            // loud badges).
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: c.success,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    l.scanIdle,
                                    style: NLType.aux.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: c.mutedForeground,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                      Expanded(
                        flex: 2,
                        child: age.inSeconds >= 3
                            ? Text(
                                l.scanLastSeen(age.inSeconds),
                                style: NLType.mono.copyWith(
                                  color: c.mutedForeground,
                                ),
                              )
                            // v6: sub-3s rows say "just now" instead of
                            // sitting blank while the age counter warms up.
                            : Text(
                                l.scanJustNow,
                                style: NLType.mono.copyWith(
                                  color: c.mutedForeground,
                                ),
                              ),
                      ),
                      SizedBox(
                        width: 84,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: bleConnectable || apConnectable
                              ? NLButton(
                                  label: l.scanSelect,
                                  size: NLButtonSize.sm,
                                  variant: hovered
                                      ? NLButtonVariant.primary
                                      : NLButtonVariant.secondary,
                                  onPressed: selectable
                                      ? () => bleConnectable
                                            ? controller.selectCandidate(
                                                device,
                                              )
                                            : _confirmApJoin(device)
                                      : null,
                                )
                              : Text(
                                  l.scanChannelPending,
                                  style: NLType.aux.copyWith(
                                    color: c.mutedForeground,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Divider(height: 1, thickness: 1, color: c.border),
          ],
        ),
      ),
    );
  }

  static String _shortChannel(AppLocalizations l, DiscoveryChannel channel) =>
      switch (channel) {
        DiscoveryChannel.ble => l.chanShortBle,
        DiscoveryChannel.accessPoint => l.chanShortAp,
        DiscoveryChannel.ctDisc => l.chanShortDisc,
      };
}

/// Four-bar RSSI indicator: filled bar count follows the dBm band, the exact
/// value is printed beside it so color/height never carries the reading
/// alone (dataviz: text wears text tokens, marks stay thin with gaps).
class SignalBars extends StatelessWidget {
  const SignalBars({super.key, required this.signal});

  final int signal;

  int get _filledBars => switch (signal) {
    >= -55 => 4,
    >= -67 => 3,
    >= -80 => 2,
    _ => 1,
  };

  @override
  Widget build(BuildContext context) {
    final c = context.nl;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var index = 0; index < 4; index++)
          Padding(
            padding: EdgeInsets.only(right: index == 3 ? 0 : 2),
            child: Container(
              width: 4,
              height: 5.0 + index * 3,
              decoration: BoxDecoration(
                color: index < _filledBars ? c.success : c.muted,
                borderRadius: const BorderRadius.all(Radius.circular(1)),
              ),
            ),
          ),
      ],
    );
  }
}
