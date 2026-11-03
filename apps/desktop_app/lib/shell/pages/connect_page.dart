import 'package:flutter/material.dart';
import 'package:neolink_ui/neolink_ui.dart';
import 'package:provisioning_session/provisioning_session.dart';

import '../../l10n/app_localizations.dart';
import '../../provisioning/provisioning_controller.dart';

/// 建立连接页（M2-4）：配对 → GATT 链路 → 读设备信息 → 读能力，全程
/// 骨架屏加分步进度；连接/能力失败给出原因并可返回候选列表重试
/// （NE101 断开后仍在配置模式，可立即重试）。
class ConnectPage extends StatelessWidget {
  const ConnectPage({super.key, required this.controller});

  final ProvisioningController controller;

  @override
  Widget build(BuildContext context) {
    final c = context.nl;
    final l = AppLocalizations.of(context)!;

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final phase = controller.phase;
        final failed =
            phase == SessionPhase.connectionError ||
            phase == SessionPhase.capabilityError;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.navConnect,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                if (failed) _errorCard(c, l, phase) else _progressCard(c, l),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _progressCard(NLColors c, AppLocalizations l) {
    final phase = controller.phase;
    final steps = [
      l.connectPairing,
      l.connectOpening,
      l.connectReadingInfo,
      l.connectReadingCaps,
    ];
    // 相位 → 当前步序：connecting 覆盖前两步，readingCapabilities 后两步。
    final currentIndex = switch (phase) {
      SessionPhase.connecting => controller.connectSteps.isEmpty ? 0 : 1,
      SessionPhase.readingCapabilities => controller.deviceInfo == null ? 2 : 3,
      _ => steps.length - 1,
    };
    return NLCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NLBadge(
            label: l.badgeChecking,
            variant: NLBadgeVariant.info,
            dot: true,
          ),
          const SizedBox(height: 16),
          for (var index = 0; index < steps.length; index++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: index < currentIndex
                        ? Icon(Icons.check, size: 16, color: c.foreground)
                        : (index == currentIndex
                              ? const SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(
                                  Icons.circle_outlined,
                                  size: 12,
                                  color: c.mutedForeground,
                                )),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    steps[index],
                    style: TextStyle(
                      fontSize: 13,
                      color: index <= currentIndex
                          ? c.foreground
                          : c.mutedForeground,
                      fontWeight: index == currentIndex
                          ? FontWeight.w600
                          : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          if (controller.connectSteps.isNotEmpty) ...[
            const SizedBox(height: 8),
            Divider(height: 1, thickness: 1, color: c.border),
            const SizedBox(height: 10),
            Text(
              controller.connectSteps.last,
              style: TextStyle(
                fontSize: 10,
                fontFamily: 'JetBrains Mono',
                color: c.mutedForeground,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _errorCard(NLColors c, AppLocalizations l, SessionPhase phase) {
    final problem = controller.lastProblem;
    final detail = problem == null ? '' : (problem.message ?? problem.reason);
    return NLCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NLBadge(
            label: phase == SessionPhase.capabilityError
                ? l.connectCapsErrorTitle
                : l.connectErrorTitle,
            variant: NLBadgeVariant.error,
          ),
          const SizedBox(height: 10),
          Text(
            l.connectRetryHint,
            style: TextStyle(fontSize: 12, color: c.mutedForeground),
          ),
          if (detail.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              detail,
              style: TextStyle(
                fontSize: 10,
                fontFamily: 'JetBrains Mono',
                color: c.mutedForeground,
              ),
            ),
          ],
          const SizedBox(height: 16),
          NLButton(
            label: l.connectBackToList,
            variant: NLButtonVariant.secondary,
            size: NLButtonSize.sm,
            onPressed: controller.switchCandidate,
          ),
        ],
      ),
    );
  }
}
