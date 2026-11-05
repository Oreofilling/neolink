import 'package:discovery_domain/discovery_domain.dart';
import 'package:flutter/material.dart';
import 'package:neolink_ui/neolink_ui.dart';
import 'package:provisioning_session/provisioning_session.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/channel_labels.dart';
import '../../provisioning/provisioning_controller.dart';
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
  const ScanPage({super.key, required this.controller, this.onOpenGuide});

  final ProvisioningController controller;
  final VoidCallback? onOpenGuide;

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  /// Channel detail cards expanded (v7d). Collapsed by default — the
  /// device table is the page's business, the environment is a footnote.
  bool _channelsExpanded = false;

  /// Candidate whose row is under the pointer (v7d row emphasis).
  String? _hoveredCandidateId;

  ProvisioningController get controller => widget.controller;

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
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
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
                      if (empty)
                        _emptyPanel(c, l)
                      else if (candidates.isEmpty && scanning)
                        _scanningPanel(c, l)
                      else
                        _deviceTable(c, l, candidates),
                    ],
                  ),
                ),
              ),
            ),
            // The QR entry is a permanent fixture at the bottom — the
            // user decides to add by code while the sweep is still
            // running, not only after the window burnt out on a table
            // full of rows. On empty it doubles as the way out; the
            // header keeps the rescan action.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 960),
                child: _noHitBar(c, l),
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

  Widget _deviceTable(
    NLColors c,
    AppLocalizations l,
    List<DiscoveryCandidate> candidates,
  ) {
    return NLCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          // Header row.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Expanded(flex: 3, child: _headText(c, l.tbDevice)),
                SizedBox(width: 92, child: _headText(c, l.tbChannel)),
                SizedBox(width: 120, child: _headText(c, l.tbSignalCol)),
                SizedBox(width: 110, child: _headText(c, l.tbStatus)),
                Expanded(flex: 2, child: _headText(c, l.tbLastSeen)),
                SizedBox(width: 84, child: _headText(c, l.tbAction)),
              ],
            ),
          ),
          Divider(height: 1, thickness: 1, color: c.border),
          for (final candidate in candidates)
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
    // M5: AP/CT-Disc-only rows are display candidates for now — the softAP
    // connect chain lands in its own round, so the row says so instead of
    // offering a connect that could only fail.
    final bleConnectable = device.channels.contains(DiscoveryChannel.ble);
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
                          child: bleConnectable
                              ? NLButton(
                                  label: l.scanSelect,
                                  size: NLButtonSize.sm,
                                  variant: hovered
                                      ? NLButtonVariant.primary
                                      : NLButtonVariant.secondary,
                                  onPressed: selectable
                                      ? () => controller.selectCandidate(device)
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

  /// "Can't find your device?" strip under a non-empty table — the doorway
  /// into the QR guide (mockup's no-hit bar).
  Widget _noHitBar(NLColors c, AppLocalizations l) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(NLRadii.radiusLg),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              l.noHit,
              style: NLType.body.copyWith(color: c.mutedForeground),
            ),
          ),
          NLButton(
            label: l.btnQrAddShort,
            variant: NLButtonVariant.ghost,
            size: NLButtonSize.sm,
            onPressed: widget.onOpenGuide,
          ),
        ],
      ),
    );
  }
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
