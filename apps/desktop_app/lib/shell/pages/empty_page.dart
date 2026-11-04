import 'package:flutter/material.dart';
import 'package:neolink_ui/neolink_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../provisioning/provisioning_controller.dart';

/// No-devices-found page (v6): nothing showed up in the scan window — the
/// primary action opens the QR add guide (wake device → ID → connect), the
/// secondary restarts the scan.
class EmptyPage extends StatelessWidget {
  const EmptyPage({super.key, required this.controller, this.onOpenGuide});

  final ProvisioningController controller;
  final VoidCallback? onOpenGuide;

  @override
  Widget build(BuildContext context) {
    final c = context.nl;
    final l = AppLocalizations.of(context)!;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 56, 24, 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.wifi_find_outlined, size: 30, color: c.mutedForeground),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                l.emptyTitle,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                l.emptyHint,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: c.mutedForeground),
              ),
              const SizedBox(height: 20),
              NLButton(label: l.btnQrAdd, onPressed: onOpenGuide),
              const SizedBox(height: 8),
              NLButton(
                label: l.scanRescan,
                variant: NLButtonVariant.secondary,
                onPressed: controller.rescan,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
