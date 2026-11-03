import 'package:discovery_domain/discovery_domain.dart';
import 'package:flutter/material.dart';
import 'package:neolink_ui/neolink_ui.dart';
import 'package:provisioning_session/provisioning_session.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/channel_labels.dart';
import '../../provisioning/provisioning_controller.dart';

/// 环境自检页（M2-4）：进入即自动执行，三路通道逐行给出可用性结论；
/// 「AP 枚举受限」呈现为能力限制说明而非空列表；全部不可用时可修复
/// 后重新检测（机器停留自检相位）。
///
/// M3b：通过后不再立刻跳扫描——倒计时 N 秒自动进入，期间可「停留本页」
/// 检查通道明细或「立即扫描」（A1）；重新检测在任意相位都可点（A2）。
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

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        // report 必须在 builder 内读取：壳只在切页时重建本页组件，
        // 自检相位内的通知只走 ListenableBuilder，外层捕获会停留在 null。
        final report = controller.environmentReport;
        final running = controller.selfChecking && report == null;
        final counting = controller.selfCheckCountdown;
        final held = controller.selfCheckHeld;
        // 自检相位之外回访本页：只读报告，不再声明「自动进入扫描」。
        final idle = controller.phase != SessionPhase.selfChecking;
        // While counting, the big strip below carries the countdown sentence;
        // the status line keeps the plain "ready" label (round-2 A1).
        final status = report == null || running
            ? l.selfcheckRunning
            : (idle || counting != null)
            ? (report.canProceed ? l.selfcheckReadyIdle : l.selfcheckBlocked)
            : held
            ? l.selfcheckHeld
            : (report.canProceed ? l.selfcheckReady : l.selfcheckBlocked);
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
                Text(status, style: TextStyle(fontSize: 12, color: c.mutedForeground)),
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
                      // Round-2 A1: a prominent countdown strip — big digits
                      // plus a bar that drains each second, sitting right
                      // above the action buttons.
                      if (counting != null) ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '$counting',
                              style: const TextStyle(
                                fontSize: 34,
                                fontWeight: FontWeight.w800,
                                height: 1,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 3),
                              child: Text(
                                l.selfcheckCountdownHint,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: c.mutedForeground,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Container(
                          height: 6,
                          decoration: BoxDecoration(
                            color: c.muted,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          clipBehavior: Clip.antiAlias,
                          alignment: Alignment.centerLeft,
                          child: AnimatedFractionallySizedBox(
                            duration: const Duration(milliseconds: 900),
                            curve: Curves.linear,
                            widthFactor:
                                (counting /
                                        controller.selfCheckHold.inSeconds)
                                    .clamp(0.0, 1.0),
                            child: ColoredBox(
                              color: c.foreground,
                              child: const SizedBox.expand(),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          NLButton(
                            label: l.btnRecheck,
                            variant: NLButtonVariant.secondary,
                            size: NLButtonSize.sm,
                            onPressed: controller.runSelfCheck,
                          ),
                          // A1: the pass state is readable before the jump —
                          // stay here, or enter the scan immediately.
                          if (counting != null) ...[
                            NLButton(
                              label: l.btnStay,
                              variant: NLButtonVariant.secondary,
                              size: NLButtonSize.sm,
                              onPressed: controller.stayOnSelfCheck,
                            ),
                            NLButton(
                              label: l.btnScanNow,
                              size: NLButtonSize.sm,
                              onPressed: controller.startScanNow,
                            ),
                          ] else if (held)
                            NLButton(
                              label: l.btnScanNow,
                              size: NLButtonSize.sm,
                              onPressed: controller.startScanNow,
                            ),
                        ],
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
