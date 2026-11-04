import 'package:discovery_domain/discovery_domain.dart';
import 'package:flutter/material.dart';
import 'package:neolink_ui/neolink_ui.dart';
import 'package:provisioning_session/provisioning_session.dart';

import '../../l10n/app_localizations.dart';
import '../../provisioning/provisioning_controller.dart';

/// QR add-device guide (v6, T9 fallback shape): a UI-only three-step walk —
/// wake the device, enter the last 6 characters of its ID (camera scanning
/// plugs into step 2 later), then connect to the located row. The session
/// machine is untouched; step 3 highlights the matching candidate and hands
/// off to the normal connect chain.
class QrGuidePage extends StatefulWidget {
  const QrGuidePage({super.key, required this.controller, required this.onExit});

  final ProvisioningController controller;
  final VoidCallback onExit;

  @override
  State<QrGuidePage> createState() => _QrGuidePageState();
}

class _QrGuidePageState extends State<QrGuidePage> {
  final TextEditingController _idController = TextEditingController();
  int _step = 0;
  bool _showInvalid = false;
  String _entered = '';

  ProvisioningController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    // Entered from the empty page: the scan window has already burnt out and
    // the source is stopped — restart it so the waking device shows up in
    // step 3 without another tap.
    if (controller.phase == SessionPhase.scanEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => controller.rescan());
    }
  }

  @override
  void dispose() {
    _idController.dispose();
    super.dispose();
  }

  DiscoveryCandidate? get _match {
    if (_entered.isEmpty) return null;
    for (final candidate in controller.candidates) {
      if (candidate.macSuffix == _entered) return candidate;
    }
    return null;
  }

  void _goStep(int step) => setState(() {
    _step = step;
    if (step == 2) {
      controller.focusQrCandidate(_entered);
    }
  });

  void _submitId() {
    final value = _idController.text.trim().toUpperCase();
    final valid = RegExp(r'^[0-9A-F]{6}$').hasMatch(value);
    setState(() => _showInvalid = !valid);
    if (!valid) return;
    _entered = value;
    _goStep(2);
  }

  void _connectMatch(DiscoveryCandidate candidate) {
    // The shell snaps back to the flow workspace when the phase leaves the
    // scan family — no local navigation needed.
    controller.selectCandidate(candidate);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nl;
    final l = AppLocalizations.of(context)!;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.qr_code_2,
                      size: 18,
                      color: c.mutedForeground,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      l.qrTitle,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  l.qrSub,
                  style: TextStyle(fontSize: 12, color: c.mutedForeground),
                ),
                const SizedBox(height: 16),
                _stepHeader(c, l),
                const SizedBox(height: 16),
                if (_step == 0) ...[
                  _wakeCard(c, l),
                  const SizedBox(height: 16),
                  NLButton(label: l.qrNext, onPressed: () => _goStep(1)),
                ] else if (_step == 1) ...[
                  _idCard(c, l),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      NLButton(
                        label: l.qrPrev,
                        variant: NLButtonVariant.secondary,
                        onPressed: () => _goStep(0),
                      ),
                      const SizedBox(width: 8),
                      NLButton(label: l.qrNext, onPressed: _submitId),
                    ],
                  ),
                ] else ...[
                  _matchCard(c, l),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      NLButton(
                        label: l.qrPrev,
                        variant: NLButtonVariant.secondary,
                        onPressed: () => _goStep(1),
                      ),
                      const Spacer(),
                      NLButton(
                        label: l.qrSkip,
                        variant: NLButtonVariant.ghost,
                        size: NLButtonSize.sm,
                        onPressed: widget.onExit,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _stepHeader(NLColors c, AppLocalizations l) {
    final labels = [l.qrStep1, l.qrStep2, l.qrStep3];
    return Row(
      children: [
        for (var index = 0; index < labels.length; index++) ...[
          _stepDot(c, index + 1, labels[index], active: index <= _step),
          if (index < labels.length - 1)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Divider(
                  height: 1,
                  thickness: 1,
                  color: index < _step ? c.foreground : c.border,
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _stepDot(NLColors c, int number, String label, {bool active = false}) {
    return Row(
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? c.foreground : Colors.transparent,
            border: Border.all(color: active ? c.foreground : c.border),
            shape: BoxShape.circle,
          ),
          child: Text(
            '$number',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: active ? c.background : c.mutedForeground,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: active ? FontWeight.w600 : FontWeight.w500,
            color: active ? c.foreground : c.mutedForeground,
          ),
        ),
      ],
    );
  }

  Widget _wakeCard(NLColors c, AppLocalizations l) {
    final tips = [l.qrWake1, l.qrWake2, l.qrWake3];
    return NLCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Blinking-blue-LED stand-in: a soft glow dot, static on
                // purpose (no ambient animation loop on a walkthrough page).
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: c.info,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: c.info.withValues(alpha: 0.5),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  l.qrStep1,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final (index, tip) in tips.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${index + 1}. ',
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'JetBrains Mono',
                        color: c.mutedForeground,
                      ),
                    ),
                    Expanded(
                      child: Text(tip, style: const TextStyle(fontSize: 13)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _idCard(NLColors c, AppLocalizations l) {
    return NLCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.qrStep2,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              l.qrInputHint,
              style: TextStyle(fontSize: 12, color: c.mutedForeground),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _idController,
              maxLength: 6,
              textCapitalization: TextCapitalization.characters,
              style: const TextStyle(fontSize: 16, fontFamily: 'JetBrains Mono'),
              decoration: InputDecoration(
                isDense: true,
                counterText: '',
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(NLRadii.radiusMd),
                  borderSide: BorderSide(
                    color: _showInvalid ? c.destructive : c.border,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(NLRadii.radiusMd),
                  borderSide: BorderSide(
                    color: _showInvalid ? c.destructive : c.foreground,
                  ),
                ),
              ),
              onSubmitted: (_) => _submitId(),
            ),
            if (_showInvalid)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  l.qrInputInvalid,
                  style: TextStyle(fontSize: 11, color: c.destructive),
                ),
              ),
            const SizedBox(height: 10),
            Text(
              l.qrCameraNote,
              style: TextStyle(fontSize: 11, color: c.mutedForeground),
            ),
          ],
        ),
      ),
    );
  }

  Widget _matchCard(NLColors c, AppLocalizations l) {
    final match = _match;
    if (match == null) {
      return NLCard(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              NLBadge(
                label: l.tbStateScanning,
                variant: NLBadgeVariant.info,
                dot: true,
              ),
              const SizedBox(height: 10),
              Text(l.qrMatchNone, style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 6),
              Text(
                _entered,
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'JetBrains Mono',
                  color: c.mutedForeground,
                ),
              ),
            ],
          ),
        ),
      );
    }
    final selectable = match.provisionable && !match.busy;
    return NLCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            NLBadge(label: l.qrMatchFound, variant: NLBadgeVariant.success),
            const SizedBox(height: 12),
            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${match.modelHint ?? ''}-${match.macSuffix ?? ''}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (match.signal != null)
                      Text(
                        l.scanSignal(match.signal!),
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'JetBrains Mono',
                          color: c.mutedForeground,
                        ),
                      ),
                  ],
                ),
                const Spacer(),
                NLButton(
                  label: l.qrConnect,
                  onPressed:
                      selectable &&
                      controller.phase == SessionPhase.resultsAvailable
                      ? () => _connectMatch(match)
                      : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
