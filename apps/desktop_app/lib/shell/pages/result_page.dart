// Delivery result page (v7d): the confirmed sections with an explicit
// device identity block (name / serial / model / full completion stamp),
// and a next-step row whose primary action starts the next device — a
// provisioning bench works in loops, so "配置下一台设备" outranks "done".
// Copy and export put the receipt where a ticket or a log can keep it.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:neolink_ui/neolink_ui.dart';
import 'package:provisioning_session/provisioning_session.dart'
    hide ConfigSection;

import '../../l10n/app_localizations.dart';
import '../../l10n/labels.dart';
import '../../provisioning/provisioning_controller.dart';
import '../../services/receipt_export.dart';

class ResultPage extends StatefulWidget {
  const ResultPage({super.key, required this.controller});

  final ProvisioningController controller;

  @override
  State<ResultPage> createState() => _ResultPageState();
}

class _ResultPageState extends State<ResultPage> {
  /// Transient copy/export feedback — the label swaps to 已复制/已导出 for
  /// two seconds ("no reaction" bugs are this app's oldest class). A failed
  /// or cancelled export flashes nothing: the save dialog already explained
  /// itself, and a false "已导出" would be worse than silence.
  _ResultFeedback _feedback = _ResultFeedback.none;
  Timer? _feedbackTimer;

  @override
  void dispose() {
    _feedbackTimer?.cancel();
    super.dispose();
  }

  ProvisioningController get controller => widget.controller;

  void _flash(_ResultFeedback feedback) {
    _feedbackTimer?.cancel();
    setState(() => _feedback = feedback);
    _feedbackTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _feedback = _ResultFeedback.none);
    });
  }

  Future<void> _copyReceipt(AppLocalizations l) async {
    final receipt = controller.sessionHistory.lastOrNull;
    if (receipt == null) return;
    await Clipboard.setData(ClipboardData(text: formatReceiptText(receipt, l)));
    _flash(_ResultFeedback.copied);
  }

  Future<void> _exportReceipt(AppLocalizations l) async {
    final receipt = controller.sessionHistory.lastOrNull;
    if (receipt == null) return;
    final saved = await exportTextFile(
      'neolink-receipt-${receipt.serialNumber}.txt',
      formatReceiptText(receipt, l),
    );
    if (saved && mounted) _flash(_ResultFeedback.exported);
  }

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
                Row(
                  children: [
                    Icon(Icons.check_circle, size: 24, color: c.success),
                    const SizedBox(width: 10),
                    Text(l.navResult, style: NLType.pageTitle),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  l.resultNote,
                  style: NLType.pageTitleSub.copyWith(color: c.mutedForeground),
                ),
                const SizedBox(height: 16),
                _identityBlock(c, l, receipt),
                const SizedBox(height: 14),
                _storedCard(c, l, result, receipt),
                const SizedBox(height: 16),
                _actions(c, l),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Device identity block (v7d product ask #6): the fields an operator
  /// needs to pair this receipt with the physical unit on the bench.
  Widget _identityBlock(
    NLColors c,
    AppLocalizations l,
    SessionReceipt? receipt,
  ) {
    return NLCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              receipt == null
                  ? (controller.deviceInfo?.deviceName ?? '')
                  : (receipt.deviceName.isEmpty
                        ? receipt.serialNumber
                        : receipt.deviceName),
              style: NLType.cardTitle.copyWith(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            _fieldRow(c, l.resultSerialLabel, receipt?.serialNumber),
            _fieldRow(c, l.resultModelLabel, receipt?.model),
            _fieldRow(
              c,
              l.resultAppliedAtLabel,
              receipt == null ? null : exportStamp(receipt.appliedAt),
            ),
          ],
        ),
      ),
    );
  }

  /// Label + mono value line — protocol fields wear JetBrains Mono.
  Widget _fieldRow(NLColors c, String label, String? value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: NLType.aux.copyWith(color: c.mutedForeground),
            ),
          ),
          Expanded(
            child: Text(
              value == null || value.isEmpty ? '—' : value,
              style: NLType.mono,
            ),
          ),
        ],
      ),
    );
  }

  Widget _storedCard(
    NLColors c,
    AppLocalizations l,
    SetConfigResult? result,
    SessionReceipt? receipt,
  ) {
    return NLCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.resultStoredCount(result?.stored.length ?? 0),
              style: NLType.cardTitle,
            ),
            const SizedBox(height: 10),
            for (final name in result?.stored ?? const <String>[])
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 16,
                      child: Icon(Icons.check, size: 14, color: c.success),
                    ),
                    Text(l.sectionLabel(name), style: NLType.body),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            Text(
              _applyLabel(l, result?.apply),
              style: NLType.aux.copyWith(color: c.mutedForeground),
            ),
            if (receipt != null) ...[
              const SizedBox(height: 8),
              Divider(height: 1, thickness: 1, color: c.border),
              const SizedBox(height: 8),
              Text(
                receipt.sections.isEmpty ? '—' : receipt.sections.join(', '),
                style: NLType.mono.copyWith(color: c.mutedForeground),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Next-step row (v7d): the primary is "provision the next device" — the
  /// bench loop's actual next move; copy/export ride beside it.
  Widget _actions(NLColors c, AppLocalizations l) {
    return Row(
      children: [
        NLButton(
          label: l.resultNextDevice,
          icon: Icons.skip_next,
          onPressed: controller.finishSession,
        ),
        const SizedBox(width: 8),
        NLButton(
          label: _feedback == _ResultFeedback.copied
              ? l.btnCopied
              : l.btnCopyResult,
          icon: _feedback == _ResultFeedback.copied
              ? Icons.check
              : Icons.content_copy,
          variant: NLButtonVariant.secondary,
          onPressed: () => _copyReceipt(l),
        ),
        const SizedBox(width: 8),
        NLButton(
          label: _feedback == _ResultFeedback.exported
              ? l.btnExported
              : l.btnExportReceipt,
          icon: _feedback == _ResultFeedback.exported
              ? Icons.check
              : Icons.save_outlined,
          variant: _feedback == _ResultFeedback.exported
              ? NLButtonVariant.secondary
              : NLButtonVariant.ghost,
          onPressed: () => _exportReceipt(l),
        ),
      ],
    );
  }

  String _applyLabel(AppLocalizations l, String? apply) => switch (apply) {
    'immediate' => l.resultApplyImmediate,
    'reconnect' => l.resultApplyReconnect,
    'reboot' => l.resultApplyReboot,
    _ => l.resultApplyUnknown,
  };
}

enum _ResultFeedback { none, copied, exported }
