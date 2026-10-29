import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:neolink_ui/neolink_ui.dart';

import '../l10n/labels.dart';

/// M0 页面占位：用真实组件拼出每页的信息结构，M2 起逐页接领域层。
class PlaceholderPage extends StatelessWidget {
  const PlaceholderPage({super.key, required this.pageId});

  final String pageId;

  @override
  Widget build(BuildContext context) {
    final c = context.nl;
    final l = AppLocalizations.of(context)!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l.navLabel(pageId), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(l.m0PlaceholderNote, style: TextStyle(fontSize: 12, color: c.mutedForeground)),
          const SizedBox(height: 16),
          NLCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 8, runSpacing: 8, children: [
                NLBadge(label: l.badgePassCount(5), variant: NLBadgeVariant.success),
                NLBadge(label: l.badgeWarnCount(1), variant: NLBadgeVariant.warning),
                NLBadge(label: l.badgeChecking, variant: NLBadgeVariant.info, dot: true),
              ]),
              const SizedBox(height: 16),
              const NLSkeleton(width: 320, height: 12),
              const SizedBox(height: 10),
              const NLSkeleton(width: 240, height: 12),
              const SizedBox(height: 10),
              const NLSkeleton(width: 280, height: 12),
              const SizedBox(height: 18),
              Row(children: [
                NLButton(label: l.btnRecheck, size: NLButtonSize.sm, onPressed: () {}),
                const SizedBox(width: 8),
                NLButton(label: l.btnContinueToScan, variant: NLButtonVariant.secondary, size: NLButtonSize.sm, onPressed: () {}),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}
