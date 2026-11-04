// Delivery result page (M3): shows the sections the device reported as
// persisted, the apply hint (display-only per §10) and the finish action
// that closes the session and returns to the scan loop.
library;

import 'package:flutter/material.dart';
import 'package:neolink_ui/neolink_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/labels.dart';
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
        final receipt = controller.sessionHistory.lastOrNull;
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
                                Text(
                                  l.sectionLabel(name),
                                  style: const TextStyle(fontSize: 13),
                                ),
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
                        // The receipt just appended by submit() — same stamp
                        // the history page lists.
                        if (receipt != null) ...[
                          const SizedBox(height: 8),
                          Divider(height: 1, thickness: 1, color: c.border),
                          const SizedBox(height: 8),
                          Text(
                            _stamp(receipt.appliedAt),
                            style: TextStyle(
                              fontSize: 11,
                              fontFamily: 'JetBrains Mono',
                              color: c.mutedForeground,
                            ),
                          ),
                        ],
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

  static String _stamp(DateTime at) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(at.month)}-${two(at.day)} ${two(at.hour)}:${two(at.minute)}';
  }
}
