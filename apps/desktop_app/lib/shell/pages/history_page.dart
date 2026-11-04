import 'package:flutter/material.dart';
import 'package:neolink_ui/neolink_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/labels.dart';
import '../../provisioning/provisioning_controller.dart';

/// History page (v6): receipts of delivered sessions this launch — device,
/// sections applied, time. In-memory by design (nothing persists to disk
/// until a store exists); the list survives in-place page switches.
class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key, required this.controller});

  final ProvisioningController controller;

  @override
  Widget build(BuildContext context) {
    final c = context.nl;
    final l = AppLocalizations.of(context)!;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final receipts = controller.sessionHistory.reversed.toList();
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
                      Icons.history,
                      size: 18,
                      color: c.mutedForeground,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      l.navHistory,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  l.histSub,
                  style: TextStyle(fontSize: 12, color: c.mutedForeground),
                ),
                const SizedBox(height: 16),
                if (receipts.isEmpty)
                  _empty(c, l)
                else
                  for (final receipt in receipts)
                    _receiptRow(c, l, receipt),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _empty(NLColors c, AppLocalizations l) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(NLRadii.radiusLg),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 28),
      child: Center(
        child: Text(
          l.histEmpty,
          style: TextStyle(fontSize: 12, color: c.mutedForeground),
        ),
      ),
    );
  }

  Widget _receiptRow(NLColors c, AppLocalizations l, SessionReceipt receipt) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: NLCard(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // Delivered receipt: a success tick leads the row so the eye
              // lands on the outcome first.
              Icon(Icons.task_alt, size: 18, color: c.success),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            receipt.deviceName.isEmpty
                                ? receipt.serialNumber
                                : receipt.deviceName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (receipt.model.isNotEmpty)
                          NLBadge(
                            label: l.capsDeviceModel(receipt.model),
                            variant: NLBadgeVariant.muted,
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      receipt.sections.isEmpty
                          ? '—'
                          : [
                              for (final section in receipt.sections)
                                l.sectionLabel(section),
                            ].join(' · '),
                      style: TextStyle(
                        fontSize: 11,
                        color: c.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                _stamp(receipt.appliedAt),
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'JetBrains Mono',
                  color: c.mutedForeground,
                ),
              ),
              const SizedBox(width: 10),
              NLBadge(label: l.histSuccess, variant: NLBadgeVariant.success),
            ],
          ),
        ),
      ),
    );
  }

  static String _stamp(DateTime at) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(at.month)}-${two(at.day)} ${two(at.hour)}:${two(at.minute)}';
  }
}
