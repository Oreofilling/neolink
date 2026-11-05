import 'package:discovery_domain/discovery_domain.dart';
import 'package:flutter/material.dart';
import 'package:neolink_ui/neolink_ui.dart';
import 'package:provisioning_session/provisioning_session.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/channel_labels.dart';
import '../../provisioning/provisioning_controller.dart';
import '../widgets/scan_radar.dart';

/// Device scan page (v6): three channel cards up top, then a live device
/// table. Continuous scan semantics — rows appear as devices are found and
/// age out by TTL; the QR guide highlight marks the row the user is looking
/// for. Busy devices stay visible but cannot be selected (§4.2.2).
class ScanPage extends StatelessWidget {
  const ScanPage({super.key, required this.controller, this.onOpenGuide});

  final ProvisioningController controller;
  final VoidCallback? onOpenGuide;

  @override
  Widget build(BuildContext context) {
    final c = context.nl;
    final l = AppLocalizations.of(context)!;

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final scanning = controller.phase == SessionPhase.scanning;
        final candidates = controller.candidates;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.radar_outlined,
                      size: 18,
                      color: c.mutedForeground,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      l.scanTitle,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 10),
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
                  style: TextStyle(fontSize: 12, color: c.mutedForeground),
                ),
                const SizedBox(height: 16),
                _channelCards(c, l, candidates),
                const SizedBox(height: 16),
                if (candidates.isEmpty && scanning)
                  _scanningPanel(c, l)
                else
                  _deviceTable(c, l, candidates),
                // The QR entry is a permanent fixture at the bottom — the
                // user decides to add by code while the sweep is still
                // running, not only after the window burnt out on a table
                // full of rows.
                const SizedBox(height: 10),
                _noHitBar(c, l),
              ],
            ),
          ),
        );
      },
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
            style: TextStyle(fontSize: 12, color: c.mutedForeground),
          ),
        ],
      ),
    );
  }

  /// One card per discovery channel: readiness + live candidate count +
  /// the remark line from the mockup copy.
  Widget _channelCards(
    NLColors c,
    AppLocalizations l,
    List<DiscoveryCandidate> candidates,
  ) {
    final report = controller.environmentReport;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columnWidth = (constraints.maxWidth - 24) / 3;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final entry in report?.channels ?? const <ChannelReadiness>[])
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
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
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
            Text(
              remark,
              style: TextStyle(fontSize: 11, color: c.mutedForeground),
            ),
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
      child: Column(
        children: [
          // Header row.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: _headText(c, l.tbDevice),
                ),
                SizedBox(
                  width: 92,
                  child: _headText(c, l.tbChannel),
                ),
                SizedBox(
                  width: 120,
                  child: _headText(c, l.tbSignalCol),
                ),
                SizedBox(
                  width: 110,
                  child: _headText(c, l.tbStatus),
                ),
                Expanded(
                  flex: 2,
                  child: _headText(c, l.tbLastSeen),
                ),
                SizedBox(
                  width: 84,
                  child: _headText(c, l.tbAction),
                ),
              ],
            ),
          ),
          Divider(height: 1, thickness: 1, color: c.border),
          for (final candidate in candidates)
            _deviceRow(c, l, candidate),
        ],
      ),
    );
  }

  Widget _headText(NLColors c, String text) => Text(
    text,
    style: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: c.mutedForeground,
    ),
  );

  Widget _deviceRow(
    NLColors c,
    AppLocalizations l,
    DiscoveryCandidate device,
  ) {
    final selectable = device.provisionable && !device.busy;
    final age = DateTime.now().difference(device.lastSeen);
    final stale = age > controller.ttl;
    final focused =
        device.macSuffix != null && device.macSuffix == controller.qrFocusSuffix;
    final signal = device.signal;
    return Opacity(
      opacity: stale ? 0.62 : 1,
      child: Column(
        children: [
          Container(
            decoration: focused
                ? BoxDecoration(
                    border: Border.all(color: c.ring),
                    borderRadius: BorderRadius.circular(NLRadii.radiusMd),
                  )
                : null,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                          style: TextStyle(
                            fontSize: 10,
                            fontFamily: 'JetBrains Mono',
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
                          style: TextStyle(
                            fontSize: 10,
                            fontFamily: 'JetBrains Mono',
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
                          style: TextStyle(
                            fontSize: 11,
                            color: c.mutedForeground,
                          ),
                        )
                      : Row(
                          children: [
                            SignalBars(signal: signal),
                            const SizedBox(width: 8),
                            Text(
                              l.scanSignal(signal),
                              style: TextStyle(
                                fontSize: 11,
                                fontFamily: 'JetBrains Mono',
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
                      // v6: a healthy connectable row gets a positive mark
                      // too — but quiet: bare dot + muted text, no chip
                      // background (exception states keep the loud badges).
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
                              style: TextStyle(
                                fontSize: 11,
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
                          style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'JetBrains Mono',
                            color: c.mutedForeground,
                          ),
                        )
                      // v6: sub-3s rows say "just now" instead of sitting
                      // blank while the age counter warms up.
                      : Text(
                          l.scanJustNow,
                          style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'JetBrains Mono',
                            color: c.mutedForeground,
                          ),
                        ),
                ),
                SizedBox(
                  width: 84,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: NLButton(
                      label: l.scanSelect,
                      size: NLButtonSize.sm,
                      onPressed: selectable
                          ? () => controller.selectCandidate(device)
                          : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, thickness: 1, color: c.border),
        ],
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
              style: TextStyle(fontSize: 12, color: c.mutedForeground),
            ),
          ),
          NLButton(
            label: l.btnQrAddShort,
            variant: NLButtonVariant.ghost,
            size: NLButtonSize.sm,
            onPressed: onOpenGuide,
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
