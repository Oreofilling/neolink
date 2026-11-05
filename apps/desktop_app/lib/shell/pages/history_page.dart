// History page (v7d): receipts of delivered sessions THIS LAUNCH — the
// scope is stated up front (in-memory only, cleared when the app closes)
// and the whole list exports as one text file. Rows render as a plain
// divider list, not a stack of cards: nothing here is clickable, so the
// frame budget stays with things that act.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:neolink_ui/neolink_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/labels.dart';
import '../../provisioning/provisioning_controller.dart';
import '../../services/receipt_export.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key, required this.controller});

  final ProvisioningController controller;

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  bool _exported = false;
  Timer? _exportedTimer;

  @override
  void dispose() {
    _exportedTimer?.cancel();
    super.dispose();
  }

  ProvisioningController get controller => widget.controller;

  Future<void> _export(AppLocalizations l) async {
    final saved = await exportTextFile(
      'neolink-history.txt',
      formatHistoryText(controller.sessionHistory, l),
    );
    if (!saved || !mounted) return;
    _exportedTimer?.cancel();
    setState(() => _exported = true);
    _exportedTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _exported = false);
    });
  }

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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(l.navHistory, style: NLType.pageTitle),
                              const SizedBox(width: 10),
                              // v7d product ask #5: the scope is part of
                              // the data contract — say what "history"
                              // means before the list is trusted.
                              NLBadge(
                                label: l.histRunScope,
                                variant: NLBadgeVariant.info,
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            l.histSub,
                            style: NLType.pageTitleSub.copyWith(
                              color: c.mutedForeground,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    NLButton(
                      label: _exported ? l.btnExported : l.btnExportHistory,
                      icon: _exported ? Icons.check : Icons.save_outlined,
                      variant: _exported
                          ? NLButtonVariant.secondary
                          : NLButtonVariant.ghost,
                      size: NLButtonSize.sm,
                      onPressed: receipts.isEmpty ? null : () => _export(l),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (receipts.isEmpty)
                  _empty(c, l)
                else
                  for (var i = 0; i < receipts.length; i++)
                    _receiptRow(
                      c,
                      l,
                      receipts[i],
                      first: i == 0,
                      last: i == receipts.length - 1,
                    ),
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
          style: NLType.aux.copyWith(color: c.mutedForeground),
        ),
      ),
    );
  }

  /// One receipt row: outcome tick, identity, sections, stamp, verdict
  /// badge — separated from its neighbours by hairline dividers.
  Widget _receiptRow(
    NLColors c,
    AppLocalizations l,
    SessionReceipt receipt, {
    bool first = false,
    bool last = false,
  }) {
    return Column(
      children: [
        if (!first) Divider(height: 1, thickness: 1, color: c.border),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
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
                            style: NLType.body.copyWith(
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
                      style: NLType.aux.copyWith(color: c.mutedForeground),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                _stamp(receipt.appliedAt),
                style: NLType.mono.copyWith(color: c.mutedForeground),
              ),
              const SizedBox(width: 10),
              NLBadge(label: l.histSuccess, variant: NLBadgeVariant.success),
            ],
          ),
        ),
        if (last) Divider(height: 1, thickness: 1, color: c.border),
      ],
    );
  }

  static String _stamp(DateTime at) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(at.month)}-${two(at.day)} ${two(at.hour)}:${two(at.minute)}';
  }
}
