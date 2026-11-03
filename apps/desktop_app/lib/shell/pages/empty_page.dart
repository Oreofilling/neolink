import 'package:flutter/material.dart';
import 'package:neolink_ui/neolink_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../provisioning/provisioning_controller.dart';

/// 未发现设备页（M2-4）：扫描超时无候选。重扫走机器清理路径回扫描
/// 循环；操作指引（二维码）为后续里程碑，明确降级标注。
class EmptyPage extends StatelessWidget {
  const EmptyPage({super.key, required this.controller});

  final ProvisioningController controller;

  @override
  Widget build(BuildContext context) {
    final c = context.nl;
    final l = AppLocalizations.of(context)!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.navEmpty,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              l.emptyHint,
              style: TextStyle(fontSize: 12, color: c.mutedForeground),
            ),
            const SizedBox(height: 16),
            NLCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  NLBadge(
                    label: l.emptyGuideLocked,
                    variant: NLBadgeVariant.muted,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      NLButton(
                        label: l.scanRescan,
                        variant: NLButtonVariant.secondary,
                        size: NLButtonSize.sm,
                        onPressed: controller.rescan,
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
  }
}
