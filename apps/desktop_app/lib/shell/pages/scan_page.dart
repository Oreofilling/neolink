import 'package:discovery_domain/discovery_domain.dart';
import 'package:flutter/material.dart';
import 'package:neolink_ui/neolink_ui.dart';
import 'package:provisioning_session/provisioning_session.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/channel_labels.dart';
import '../../l10n/labels.dart';
import '../../provisioning/provisioning_controller.dart';

/// 扫描页（M2-4）：通道状态条 + 候选列表。扫描中显示骨架行；出候选后
/// 列表冻结为快照（离开扫描相位即停源）。忙设备显示 BUSY 徽章且不可
/// 选择（§4.2.2：不得自动连接 BUSY=1 的候选）。
class ScanPage extends StatelessWidget {
  const ScanPage({super.key, required this.controller});

  final ProvisioningController controller;

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
            constraints: const BoxConstraints(maxWidth: 860),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      l.navScan,
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
                if (scanning)
                  Text(
                    l.scanScanning,
                    style: TextStyle(fontSize: 12, color: c.mutedForeground),
                  ),
                const SizedBox(height: 14),
                _channelStrip(c, l),
                const SizedBox(height: 14),
                if (scanning)
                  ...List.generate(
                    3,
                    (index) => const Padding(
                      padding: EdgeInsets.only(bottom: 10),
                      child: NLSkeleton(width: 640, height: 52),
                    ),
                  )
                else
                  for (final candidate in candidates)
                    _candidateRow(c, l, candidate),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _channelStrip(NLColors c, AppLocalizations l) {
    final report = controller.environmentReport;
    if (report == null) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          l.scanChannelStatus,
          style: TextStyle(fontSize: 11, color: c.mutedForeground),
        ),
        for (final entry in report.channels)
          NLBadge(
            label:
                '${l.channelLabel(entry.channel)} · '
                '${l.capabilityLabel(entry.capability)}',
            variant: switch (entry.capability) {
              ChannelCapability.available => NLBadgeVariant.success,
              ChannelCapability.limited => NLBadgeVariant.warning,
              ChannelCapability.unavailable => NLBadgeVariant.error,
            },
          ),
      ],
    );
  }

  Widget _candidateRow(
    NLColors c,
    AppLocalizations l,
    DiscoveryCandidate device,
  ) {
    final selectable = device.provisionable && !device.busy;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: NLCard(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        device.modelHint ?? l.scanUnknownModel,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (device.macSuffix != null)
                        NLBadge(
                          label: l.scanMacSuffix(device.macSuffix!),
                          variant: NLBadgeVariant.muted,
                        ),
                      const SizedBox(width: 8),
                      if (device.busy)
                        NLBadge(
                          label: l.scanBusy,
                          variant: NLBadgeVariant.error,
                        )
                      else if (!device.provisionable)
                        NLBadge(
                          label: l.scanNotProvisionable,
                          variant: NLBadgeVariant.warning,
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (device.signal != null)
                    Text(
                      l.scanSignal(device.signal!),
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'JetBrains Mono',
                        color: c.mutedForeground,
                      ),
                    ),
                ],
              ),
              const Spacer(),
              NLButton(
                label: l.scanSelect,
                size: NLButtonSize.sm,
                onPressed: selectable
                    ? () => controller.selectCandidate(device)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
