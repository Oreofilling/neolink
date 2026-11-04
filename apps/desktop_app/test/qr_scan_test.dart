// Stage 3: QR scanning on the guide page, driven through injected fakes
// (a camera cannot exist in `flutter test`). Real camera + zxing-cpp
// correctness is verified on the Windows box against the built app.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neolink_ui/neolink_ui.dart';

import 'package:desktop_app/l10n/app_localizations.dart';
import 'package:desktop_app/provisioning/provisioning_controller.dart';
import 'package:desktop_app/shell/pages/qr_guide_page.dart';
import 'package:desktop_app/shell/widgets/qr_camera_scanner.dart';

import 'provisioning_fakes.dart';

const _kValidUri =
    'ctdev://guide-v1/A1B2C3?m=NE101&c=01&g=ne101_config_button_v1';

/// Frame source standing in for the camera: hands out scripted capture
/// paths, remembers when it was closed so tests can prove the loop stops.
final class FakeQrSource implements QrFrameSource {
  FakeQrSource({Object? openError})
      : frames = const [],
        _openError = openError;

  FakeQrSource.withFrames(this.frames) : _openError = null;

  final List<String> frames;
  final Object? _openError;
  int captures = 0;
  int closeCalls = 0;

  @override
  Future<void> open() async {
    if (_openError != null) throw _openError;
  }

  @override
  Future<String?> capture() async {
    final index = captures;
    captures++;
    return index < frames.length ? frames[index] : null;
  }

  @override
  Widget? buildPreview(BuildContext context) => null;

  @override
  Future<void> close() async => closeCalls++;
}

ProvisioningController _wiredController(FakeSource source) =>
    ProvisioningController(
      environmentProbe: readyProbe(),
      discoverySource: source,
      establishPairing: (_) async {},
      connectChannel: (_, __) async => FakeCtDevice(),
      // Zero hold so the virtual clock reaches the scanning phase within a
      // few pumps (the default 5s hold is for the real self-check show).
      selfCheckHold: Duration.zero,
    );

/// Single-frame pumps only — looping skeleton animations forbid
/// pumpAndSettle (same discipline as pages_test).
Future<void> _settle(WidgetTester tester, [int frames = 12]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Future<void> _pumpGuide(
  WidgetTester tester,
  ProvisioningController controller, {
  QrFrameSource? source,
  QrImageDecoder? decoder,
}) async {
  tester.platformDispatcher.localesTestValue = const [Locale('zh')];
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh'),
      theme: nlTheme(Brightness.light),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: QrGuidePage(
          controller: controller,
          onExit: () {},
          qrFrameSource: source,
          qrDecoder: decoder,
        ),
      ),
    ),
  );
  // The real shell kicks the session off from SelfcheckPage.initState; this
  // harness never mounts it, so start the phase machine the same way.
  unawaited(controller.runSelfCheck());
}

void main() {
  testWidgets('scan decodes a spec QR, fills the ID and locates the row', (
    tester,
  ) async {
    // Arrange: one scripted frame that "decodes" to the spec example.
    final bleSource = FakeSource();
    final controller = _wiredController(bleSource);
    final qrSource = FakeQrSource.withFrames(['shot1.png']);
    Future<String?> decoder(String path) async =>
        path == 'shot1.png' ? _kValidUri : null;
    addTearDown(bleSource.close);

    await _pumpGuide(tester, controller, source: qrSource, decoder: decoder);
    await _settle(tester); // self-check passes, scanning starts

    // Act: step 1 mounts the scanner; the loop hits on the first frame.
    await tester.tap(find.text('下一步'));
    await _settle(tester);

    // Assert: auto-advanced to the match step with the suffix focused.
    expect(controller.qrFocusSuffix, 'A1B2C3');
    expect(find.text('A1B2C3'), findsWidgets);
    expect(qrSource.closeCalls, greaterThan(0)); // scanner disposed

    // The device shows up → match card states it found the row.
    bleSource.emit(sampleCandidate(macSuffix: 'A1B2C3'));
    await _settle(tester);
    expect(find.text('已定位设备'), findsOneWidget);
    expect(find.text('NE101-A1B2C3'), findsOneWidget);

    // This harness never leaves the scan family (no connect here), so the
    // scan/sweep timers would still be armed at test end — dispose in the
    // body (addTearDown runs after the binding's pending-timer check).
    controller.dispose();
  });

  testWidgets('no camera falls back to manual input end-to-end', (tester) async {
    // Arrange: the source reports a machine without any camera.
    final bleSource = FakeSource();
    final controller = _wiredController(bleSource);
    final qrSource = FakeQrSource(openError: QrNoCameraException());
    Future<String?> decoder(String path) async => null;
    addTearDown(bleSource.close);

    await _pumpGuide(tester, controller, source: qrSource, decoder: decoder);
    await _settle(tester);

    await tester.tap(find.text('下一步'));
    await _settle(tester);

    // Assert: the quiet no-camera hint appears, capture never runs.
    expect(find.text('未检测到摄像头，可直接手动输入下方编号'), findsOneWidget);
    expect(qrSource.captures, 0);

    // Act: type the suffix by hand (lowercase on purpose — submit
    // normalizes) and advance. The button row sits below the fold once the
    // scanner card mounts, so scroll it in first.
    await tester.enterText(find.byType(TextField), 'a1b2c3');
    final next = find.text('下一步');
    await tester.ensureVisible(next);
    await _settle(tester, 4);
    await tester.tap(next);
    await _settle(tester);

    expect(controller.qrFocusSuffix, 'A1B2C3');
    expect(find.text('A1B2C3'), findsWidgets);

    // Same timer discipline as above: dispose before the body returns.
    controller.dispose();
  });
}
