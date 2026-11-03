// Delivery result page (M3): shows the sections the device reported as
// persisted, the apply hint (display-only per §10) and the finish action
// that closes the session and returns to the scan loop.
library;

import 'package:flutter/material.dart';
import 'package:neolink_ui/neolink_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../provisioning/provisioning_controller.dart';

class ResultPage extends StatelessWidget {
  const ResultPage({super.key, required this.controller});

  final ProvisioningController controller;

  @override
  Widget build(BuildContext context) {
    final c = context.nl;
    final l = AppLocalizations.of(context)!;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final result = controller.deliveryResult;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.navResult,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  l.resultNote,
                  style: TextStyle(fontSize: 12, color: c.mutedForeground),
                ),
                const SizedBox(height: 16),
                NLCard(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.check_circle_outline,
                              size: 16,
                              color: c.success,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              l.resultStoredCount(result?.stored.length ?? 0),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        for (final name in result?.stored ?? const <String>[])
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 16,
                                  child: Icon(
                                    Icons.check,
                                    size: 14,
                                    color: c.success,
                                  ),
                                ),
                                Text(name, style: const TextStyle(fontSize: 13)),
                              ],
                            ),
                          ),
                        const SizedBox(height: 10),
                        Text(
                          _applyLabel(l, result?.apply),
                          style: TextStyle(
                            fontSize: 12,
                            color: c.mutedForeground,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                NLButton(
                  label: l.resultDone,
                  onPressed: controller.finishSession,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _applyLabel(AppLocalizations l, String? apply) => switch (apply) {
    'immediate' => l.resultApplyImmediate,
    'reconnect' => l.resultApplyReconnect,
    'reboot' => l.resultApplyReboot,
    _ => l.resultApplyUnknown,
  };
}
