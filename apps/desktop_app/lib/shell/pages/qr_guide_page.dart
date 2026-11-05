import 'dart:async';

import 'package:discovery_domain/discovery_domain.dart';
import 'package:flutter/material.dart';
import 'package:neolink_ui/neolink_ui.dart';
import 'package:provisioning_session/provisioning_session.dart';

import '../../l10n/app_localizations.dart';
import '../../provisioning/device_qr_uri.dart';
import '../../provisioning/provisioning_controller.dart';
import '../widgets/qr_camera_scanner.dart';

/// QR add-device guide (v6): a UI-only three-step walk — wake the device,
/// read its ID from the QR code, then connect to the located row. Step 2
/// offers two ways to obtain the code: live camera scanning and picking an
/// image, both feeding the same strict parser; machines without a camera
/// land on the upload path. The session machine is only touched to keep a
/// scan window armed behind the walkthrough; step 3 highlights the
/// matching candidate and hands off to the normal connect chain.
class QrGuidePage extends StatefulWidget {
  const QrGuidePage({
    super.key,
    required this.controller,
    required this.onExit,
    this.qrFrameSource,
    this.qrDecoder,
    this.qrImagePicker,
  });

  final ProvisioningController controller;
  final VoidCallback onExit;

  /// Test injection for the step-2 scanner; production uses the real
  /// camera + zxing wiring built into QrCameraScanner.
  final QrFrameSource? qrFrameSource;
  final QrImageDecoder? qrDecoder;

  /// Test injection for the upload mode's file picker.
  final QrImagePicker? qrImagePicker;

  @override
  State<QrGuidePage> createState() => _QrGuidePageState();
}

/// How step 2 obtains the QR image.
enum _QrInputMode { camera, image }

class _QrGuidePageState extends State<QrGuidePage> {
  int _step = 0;
  _QrInputMode _mode = _QrInputMode.camera;
  bool _uploadInvalid = false;
  String _entered = '';

  ProvisioningController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.addListener(_onControllerChanged);
    // Entered from the empty page: the scan window has already burnt out
    // and the source is stopped — restart it so the waking device shows up
    // in step 3 without another tap.
    if (controller.phase == SessionPhase.scanEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _rearmScan());
    }
  }

  @override
  void dispose() {
    controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  /// A walkthrough needs a live scan window behind it: the device wakes on
  /// the user's schedule (a ~60s config window), not the scan timeout's.
  /// Whenever the window burns out while the guide is open, restart it —
  /// the shell keeps this page mounted across the transient cleaning phase
  /// (cleaning belongs to the scan family).
  void _onControllerChanged() {
    if (controller.phase == SessionPhase.scanEmpty) _rearmScan();
  }

  void _rearmScan() {
    if (!mounted || controller.phase != SessionPhase.scanEmpty) return;
    unawaited(controller.rescan());
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

  void _onQrDecoded(DeviceQrUri uri) {
    // A spec-conforming QR is authoritative for the suffix — no typing, no
    // typos; model/channels stay hints for the table.
    _entered = uri.macSuffix;
    _goStep(2);
  }

  /// Upload mode: pick an image, run it through the same decoder + parser
  /// as the camera loop. A cancelled dialog is not an error; an unreadable
  /// or non-conforming image shows a quiet inline hint and stays on step.
  Future<void> _pickAndDecode() async {
    setState(() => _uploadInvalid = false);
    final path = await (widget.qrImagePicker ?? fileQrImagePicker)();
    if (!mounted || path == null) return;
    final text = await (widget.qrDecoder ?? zxingQrDecoder)(path);
    if (!mounted) return;
    final uri = text == null ? null : DeviceQrUri.tryParse(text);
    if (uri == null) {
      setState(() => _uploadInvalid = true);
      return;
    }
    _onQrDecoded(uri);
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
                  _modeToggle(l),
                  const SizedBox(height: 12),
                  if (_mode == _QrInputMode.camera)
                    QrCameraScanner(
                      frameSource: widget.qrFrameSource,
                      decoder: widget.qrDecoder,
                      onDecoded: _onQrDecoded,
                    )
                  else
                    _uploadCard(c, l),
                  const SizedBox(height: 16),
                  NLButton(
                    label: l.qrPrev,
                    variant: NLButtonVariant.secondary,
                    onPressed: () => _goStep(0),
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

  /// Two exclusive ways to obtain the code; the active one is filled.
  Widget _modeToggle(AppLocalizations l) {
    return Row(
      children: [
        Expanded(
          child: NLButton(
            label: l.qrModeCamera,
            icon: Icons.photo_camera_outlined,
            variant: _mode == _QrInputMode.camera
                ? NLButtonVariant.primary
                : NLButtonVariant.secondary,
            onPressed: () => setState(() {
              _mode = _QrInputMode.camera;
              _uploadInvalid = false;
            }),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: NLButton(
            label: l.qrModeImage,
            icon: Icons.image_outlined,
            variant: _mode == _QrInputMode.image
                ? NLButtonVariant.primary
                : NLButtonVariant.secondary,
            onPressed: () => setState(() {
              _mode = _QrInputMode.image;
              _uploadInvalid = false;
            }),
          ),
        ),
      ],
    );
  }

  Widget _uploadCard(NLColors c, AppLocalizations l) {
    return NLCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.qrModeImage,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              l.qrUploadHint,
              style: TextStyle(fontSize: 12, color: c.mutedForeground),
            ),
            const SizedBox(height: 12),
            NLButton(
              label: l.qrUploadButton,
              icon: Icons.upload_file_outlined,
              variant: NLButtonVariant.secondary,
              onPressed: _pickAndDecode,
            ),
            if (_uploadInvalid)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 14, color: c.destructive),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        l.qrUploadInvalid,
                        style: TextStyle(fontSize: 11, color: c.destructive),
                      ),
                    ),
                  ],
                ),
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
