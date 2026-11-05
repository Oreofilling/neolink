// Tier-2 E2E: the real Windows exe (integration_test runs the actual app
// binary with real plugins, fonts and l10n) driven through the production
// loop twice — self-check, scan, connect, module form, deliver, receipt,
// "provision next device", run history — plus link-loss recovery and the
// discard-confirmation gate. The device side is the shared fake GATT
// channel from test/provisioning_fakes.dart; what this file proves that
// the widget suite cannot is the app assembling and running end to end.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provisioning_session/provisioning_session.dart';

import 'package:desktop_app/app.dart';
import 'package:desktop_app/provisioning/provisioning_controller.dart';
import 'package:desktop_app/services/settings_store.dart';

import '../test/provisioning_fakes.dart';

void main() {
  // 3.47 integration_test follows AutomatedTestWidgetsFlutterBinding
  // semantics (no framePolicy knob anymore): pump() drives fake time and
  // fires timers virtually, so settle() counts mirror the widget suite.
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// 16ms frames, N of them — the app chain converges on microtasks, and
  /// dialog/route animations need 150ms (10+ frames) to finish.
  Future<void> settle(WidgetTester tester, [int frames = 14]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Future<void> pumpApp(WidgetTester tester, ProvisioningController controller) {
    // v7c lesson: the pinned QR strip eats viewport height, 800x600 leaves
    // the first connect button below the fold.
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    return tester.pumpWidget(
      NeoLinkApp(controller: controller, settings: SettingsStore.none()),
    );
  }

  ProvisioningController e2eController(
    FakeSource source,
    FakeCtDevice device,
  ) => ProvisioningController(
    environmentProbe: readyProbe(),
    discoverySource: source,
    establishPairing: (_) async {},
    connectChannel: (_, __) async => device,
    // No link injection here: this suite never leaves the happy path's
    // link assumptions to the real universal_ble static.
    linkEvents: (_) => const Stream<bool>.empty(),
    selfCheckHold: const Duration(seconds: 2),
  );

  testWidgets('production loop twice, then run history', (tester) async {
    final source = FakeSource();
    final device = FakeCtDevice();
    final controller = e2eController(source, device);
    addTearDown(source.close);
    addTearDown(device.close);

    await pumpApp(tester, controller);
    await settle(tester); // self-check walks its channels
    await tester.pump(const Duration(seconds: 3)); // through the 2s hold
    await settle(tester);
    expect(controller.phase, SessionPhase.scanning);

    for (var round = 1; round <= 2; round++) {
      source.emit(sampleCandidate(candidateId: 'dev-$round'));
      await settle(tester);
      await tester.tap(find.text('连接'));
      await settle(tester, 20); // timeline -> capabilities -> module list
      expect(controller.phase, SessionPhase.choosingSections);

      await tester.tap(find.text('Wi-Fi 联网'));
      await settle(tester);
      expect(controller.phase, SessionPhase.editingConfig);

      // ssid alone validates (empty password = open network, §13.4).
      await tester.enterText(find.byType(TextField).at(0), 'probe-$round');
      await settle(tester);

      await tester.tap(find.text('下发配置'));
      await settle(tester, 20);
      expect(controller.phase, SessionPhase.completed);
      expect(device.lastConfigSet?['wifi'], isNotNull);
      expect(find.text('NL24Q4001234'), findsOneWidget); // identity block
      expect(find.text('完成时间'), findsOneWidget);

      if (round == 1) {
        await tester.tap(find.text('配置下一台设备'));
        await settle(tester, 20); // cleaning -> scanning for round two
        expect(controller.phase, SessionPhase.scanning);
      }
    }

    // Both receipts landed in this launch's history.
    await tester.tap(find.text('历史会话'));
    await settle(tester);
    expect(find.text('本次运行记录'), findsOneWidget);
    expect(find.text('NL24Q4001234'), findsNWidgets(2));

    controller.dispose();
  });

  testWidgets('link loss mid-session recovers in place with drafts kept', (
    tester,
  ) async {
    final source = FakeSource();
    final device = FakeCtDevice();
    final link = StreamController<bool>.broadcast();
    final controller = ProvisioningController(
      environmentProbe: readyProbe(),
      discoverySource: source,
      establishPairing: (_) async {},
      connectChannel: (_, __) async => device,
      linkEvents: (_) => link.stream,
      selfCheckHold: Duration.zero,
    );
    addTearDown(source.close);
    addTearDown(device.close);
    addTearDown(link.close);

    await pumpApp(tester, controller);
    await settle(tester); // zero hold: straight into scanning
    source.emit(sampleCandidate());
    await settle(tester);
    await tester.tap(find.text('连接'));
    await settle(tester, 20);
    await tester.tap(find.text('Wi-Fi 联网'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).at(0), 'keep-me');
    await settle(tester);

    // Radio loss while editing: dialog offers reconnect, drafts survive.
    link.add(false);
    await settle(tester, 12);
    expect(controller.phase, SessionPhase.linkLost);
    expect(find.text('连接已断开'), findsOneWidget);

    await tester.tap(find.text('重新连接'));
    await settle(tester, 20); // pair -> connect -> session again
    expect(controller.phase, SessionPhase.editingConfig);
    expect(find.text('keep-me'), findsOneWidget);

    controller.dispose();
  });

  testWidgets('cancel session with input asks before discarding', (
    tester,
  ) async {
    final source = FakeSource();
    final device = FakeCtDevice();
    final controller = e2eController(source, device);
    addTearDown(source.close);
    addTearDown(device.close);

    await pumpApp(tester, controller);
    await settle(tester);
    source.emit(sampleCandidate());
    await settle(tester);
    await tester.tap(find.text('连接'));
    await settle(tester, 20);
    await tester.tap(find.text('Wi-Fi 联网'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).at(0), 'unsent');
    await settle(tester);

    await tester.ensureVisible(find.text('取消会话'));
    await tester.pump();
    await tester.tap(find.text('取消会话'));
    await settle(tester, 12);
    expect(find.text('取消本次会话？'), findsOneWidget);

    await tester.tap(find.text('放弃并退出'));
    await settle(tester, 12);
    expect(controller.phase, SessionPhase.scanning);
    expect(controller.drafts, isEmpty);

    await tester.pump(const Duration(seconds: 21));
    expect(controller.phase, SessionPhase.scanEmpty);
    controller.dispose();
  });
}
