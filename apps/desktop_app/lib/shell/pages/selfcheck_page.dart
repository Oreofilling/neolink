import 'package:discovery_domain/discovery_domain.dart';
import 'package:flutter/material.dart';
import 'package:neolink_ui/neolink_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/channel_labels.dart';
import '../../provisioning/provisioning_controller.dart';

/// 环境自检页（M2-4）：进入即自动执行，三路通道逐行给出可用性结论；
/// 「AP 枚举受限」呈现为能力限制说明而非空列表；全部不可用时可修复
/// 后重新检测（机器停留自检相位）。
class SelfcheckPage extends StatefulWidget {
  const SelfcheckPage({super.key, required this.controller});

  final ProvisioningController controller;

  @override
  State<SelfcheckPage> createState() => _SelfcheckPageState();
}

class _SelfcheckPageState extends State<SelfcheckPage> {
  @override
  void initState() {
    super.initState();
    // 首帧后自动执行自检（首帧内调用 setState 会撞构建周期）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.controller.runSelfCheck();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nl;
    final l = AppLocalizations.of(context)!;
    final controller = widget.controller;
    final report = controller.environmentReport;

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final running = controller.selfChecking && report == null;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.navSelfcheck,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  report == null || running
                      ? l.selfcheckRunning
                      : (report.canProceed
                            ? l.selfcheckReady
                            : l.selfcheckBlocked),
                  style: TextStyle(fontSize: 12, color: c.mutedForeground),
                ),
                const SizedBox(height: 16),
                NLCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (report == null)
                        ...List.generate(
                          3,
                          (index) => const Padding(
                            padding: EdgeInsets.only(bottom: 12),
                            child: NLSkeleton(width: 320, height: 14),
                          ),
                        )
                      else
                        for (final entry in report.channels)
                          _channelRow(c, l, entry),
                      const SizedBox(height: 16),
                      NLButton(
                        label: l.btnRecheck,
                        variant: NLButtonVariant.secondary,
                        size: NLButtonSize.sm,
                        onPressed: controller.runSelfCheck,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _channelRow(NLColors c, AppLocalizations l, ChannelReadiness entry) {
    final variant = switch (entry.capability) {
      ChannelCapability.available => NLBadgeVariant.success,
      ChannelCapability.limited => NLBadgeVariant.warning,
      ChannelCapability.unavailable => NLBadgeVariant.error,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                l.channelLabel(entry.channel),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              NLBadge(
                label: l.capabilityLabel(entry.capability),
                variant: variant,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            l.reasonLabel(entry.reason),
            style: TextStyle(fontSize: 12, color: c.mutedForeground),
          ),
          if (entry.detail != null && entry.reason != 'ready')
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                entry.detail!,
                style: TextStyle(
                  fontSize: 10,
                  fontFamily: 'JetBrains Mono',
                  color: c.mutedForeground,
                ),
              ),
            ),
          const SizedBox(height: 6),
          Divider(height: 1, thickness: 1, color: c.border),
        ],
      ),
    );
  }
}
