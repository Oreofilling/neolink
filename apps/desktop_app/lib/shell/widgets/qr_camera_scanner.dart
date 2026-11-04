/// Stage 3 QR spike: camera scanning for the device-guide QR code.
///
/// Windows has no frame-stream camera API in Flutter, so the pipeline is
/// serialized stills: `camera_windows` renders a live preview and takes a
/// picture every ~450 ms, `flutter_zxing` decodes the still via FFI
/// zxing-cpp, and [DeviceQrUri.tryParse] validates the text against the
/// ctdev:// grammar. Anything that fails to parse is simply another empty
/// frame — the manual suffix input below stays the always-available path.
///
/// The frame source and decoder are injectable so widget tests drive the
/// loop without a physical camera; the production wiring lives here too
/// ([CameraQrFrameSource], [zxingQrDecoder]).
library;

import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_zxing/flutter_zxing.dart';
import 'package:neolink_ui/neolink_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../provisioning/device_qr_uri.dart';

/// Produces image paths for the scanner loop to decode, one at a time.
abstract interface class QrFrameSource {
  /// Prepares the source (lists cameras, initializes the controller).
  ///
  /// Throws [QrNoCameraException] when the machine has no camera at all;
  /// any other failure is reported as an unavailable camera.
  Future<void> open();

  /// Captures one still and returns its file path, or `null` when the
  /// source has no frame ready. Called strictly sequentially by the loop.
  Future<String?> capture();

  /// Live-preview widget, or `null` when this source has nothing to show
  /// (fakes, cameras that failed to start).
  Widget? buildPreview(BuildContext context);

  /// Releases the source for good.
  Future<void> close();
}

/// Thrown by [QrFrameSource.open] when no camera device exists.
class QrNoCameraException implements Exception {
  @override
  String toString() => 'QrNoCameraException';
}

/// Decodes an image file to raw text (any barcode), or `null`.
typedef QrImageDecoder = Future<String?> Function(String imagePath);

/// Production decoder: zxing-cpp over the captured still, QR-only.
Future<String?> zxingQrDecoder(String imagePath) async {
  try {
    final result = await zx.readBarcodeImagePathString(
      imagePath,
      DecodeParams(format: Format.qrCode, tryHarder: true, maxSize: 1600),
    );
    return result.isValid ? result.text : null;
  } catch (_) {
    // Native-lib hiccup on one frame is not fatal — same as an empty frame.
    return null;
  }
}

/// Production frame source: first available camera, preview + stills.
class CameraQrFrameSource implements QrFrameSource {
  CameraController? _controller;

  @override
  Future<void> open() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) throw QrNoCameraException();
    final controller = CameraController(
      cameras.first,
      ResolutionPreset.medium,
      enableAudio: false,
    );
    _controller = controller;
    await controller.initialize();
  }

  @override
  Future<String?> capture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return null;
    final file = await controller.takePicture();
    return file.path;
  }

  @override
  Widget? buildPreview(BuildContext context) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return null;
    return CameraPreview(controller);
  }

  @override
  Future<void> close() async {
    final controller = _controller;
    _controller = null;
    await controller?.dispose();
  }
}

enum _QrScannerStatus { starting, scanning, noCamera, error }

/// Camera card with a corner-bracket viewfinder and a quiet status line.
///
/// Emits exactly one [onDecoded] for the first spec-conforming QR and then
/// goes quiet (the parent advances; this widget is disposed on step exit).
class QrCameraScanner extends StatefulWidget {
  const QrCameraScanner({
    super.key,
    required this.onDecoded,
    this.frameSource,
    this.decoder,
    this.attemptInterval = const Duration(milliseconds: 450),
    this.errorBackoff = const Duration(seconds: 1),
  });

  final void Function(DeviceQrUri uri) onDecoded;

  /// Injected by tests; defaults to the real camera pipeline.
  final QrFrameSource? frameSource;
  final QrImageDecoder? decoder;

  /// Pause between still captures; a Windows takePicture takes a few
  /// hundred ms on its own, so the effective rate is 1-2 scans/s.
  final Duration attemptInterval;

  /// Pause after a transient capture/decode error before retrying.
  final Duration errorBackoff;

  @override
  State<QrCameraScanner> createState() => _QrCameraScannerState();
}

class _QrCameraScannerState extends State<QrCameraScanner> {
  late final QrFrameSource _source;
  late final QrImageDecoder _decoder;
  _QrScannerStatus _status = _QrScannerStatus.starting;
  bool _running = true;

  @override
  void initState() {
    super.initState();
    _source = widget.frameSource ?? CameraQrFrameSource();
    _decoder = widget.decoder ?? zxingQrDecoder;
    unawaited(_run());
  }

  @override
  void dispose() {
    _running = false;
    unawaited(_source.close());
    super.dispose();
  }

  void _setStatus(_QrScannerStatus status) {
    if (!mounted) return;
    setState(() => _status = status);
  }

  Future<void> _run() async {
    try {
      await _source.open();
    } on QrNoCameraException {
      _setStatus(_QrScannerStatus.noCamera);
      return;
    } catch (error) {
      debugPrint('qr scanner: camera failed to open: $error');
      _setStatus(_QrScannerStatus.error);
      return;
    }
    if (!mounted) return;
    _setStatus(_QrScannerStatus.scanning);

    while (mounted && _running) {
      try {
        final path = await _source.capture();
        if (path != null && mounted && _running) {
          final text = await _decoder(path);
          final uri = text == null ? null : DeviceQrUri.tryParse(text);
          if (uri != null) {
            if (mounted) widget.onDecoded(uri);
            return;
          }
        }
        await Future<void>.delayed(widget.attemptInterval);
      } catch (_) {
        // Transient hiccup (capture raced with the preview, file lock…):
        // back off and try again instead of dropping the scanner.
        await Future<void>.delayed(widget.errorBackoff);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nl;
    final l = AppLocalizations.of(context)!;
    final preview =
        _status == _QrScannerStatus.scanning ? _source.buildPreview(context) : null;

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(NLRadii.radiusLg),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: 4 / 3,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (preview != null)
                  FittedBox(
                    fit: BoxFit.cover,
                    clipBehavior: Clip.antiAlias,
                    child: preview,
                  )
                else
                  ColoredBox(
                    color: c.muted.withValues(alpha: 0.12),
                    child: Center(
                      child: Icon(
                        _status == _QrScannerStatus.noCamera ||
                                _status == _QrScannerStatus.error
                            ? Icons.videocam_off_outlined
                            : Icons.videocam_outlined,
                        size: 34,
                        color: c.mutedForeground,
                      ),
                    ),
                  ),
                // Viewfinder brackets sit above whatever the source shows so
                // users aim the QR at a fixed spot.
                if (preview != null)
                  const Positioned.fill(child: _ViewfinderBrackets()),
              ],
            ),
          ),
          Divider(height: 1, thickness: 1, color: c.border),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: _statusLine(c, l),
          ),
        ],
      ),
    );
  }

  /// Quiet status line — inline dot/icon + muted text, no loud chips
  /// (matches the scan table's restrained idle state).
  Widget _statusLine(NLColors c, AppLocalizations l) {
    switch (_status) {
      case _QrScannerStatus.starting:
      case _QrScannerStatus.scanning:
        return Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: _status == _QrScannerStatus.scanning
                    ? c.ring
                    : c.mutedForeground,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _status == _QrScannerStatus.scanning
                    ? l.qrScanHint
                    : l.qrCameraStarting,
                style: TextStyle(fontSize: 11, color: c.mutedForeground),
              ),
            ),
          ],
        );
      case _QrScannerStatus.noCamera:
        return _hint(c, l.qrCameraNone);
      case _QrScannerStatus.error:
        return _hint(c, l.qrCameraError);
    }
  }

  Widget _hint(NLColors c, String text) => Row(
        children: [
          Icon(Icons.info_outline, size: 14, color: c.mutedForeground),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 11, color: c.mutedForeground),
            ),
          ),
        ],
      );
}

/// Four corner brackets marking the aim area, painted over the preview.
class _ViewfinderBrackets extends StatelessWidget {
  const _ViewfinderBrackets();

  @override
  Widget build(BuildContext context) {
    final c = context.nl;
    return CustomPaint(
      painter: _BracketPainter(color: c.ring),
      size: Size.infinite,
    );
  }
}

class _BracketPainter extends CustomPainter {
  _BracketPainter({required this.color});

  final Color color;

  static const double _armLength = 26;
  static const double _strokeWidth = 2.5;
  static const double _frameScale = 0.62;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide * _frameScale;
    if (side <= _armLength * 2) return;
    final rect = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: side,
      height: side,
    );
    final paint = Paint()
      ..color = color.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth
      ..strokeCap = StrokeCap.round;

    // Each corner is an L: one horizontal + one vertical segment.
    const arm = _armLength;
    void corner(Offset point, Offset horizontalEnd, Offset verticalEnd) {
      canvas.drawLine(point, horizontalEnd, paint);
      canvas.drawLine(point, verticalEnd, paint);
    }

    corner(rect.topLeft, Offset(rect.left + arm, rect.top),
        Offset(rect.left, rect.top + arm));
    corner(rect.topRight, Offset(rect.right - arm, rect.top),
        Offset(rect.right, rect.top + arm));
    corner(rect.bottomLeft, Offset(rect.left + arm, rect.bottom),
        Offset(rect.left, rect.bottom - arm));
    corner(rect.bottomRight, Offset(rect.right - arm, rect.bottom),
        Offset(rect.right, rect.bottom - arm));
  }

  @override
  bool shouldRepaint(covariant _BracketPainter oldDelegate) =>
      oldDelegate.color != color;
}
