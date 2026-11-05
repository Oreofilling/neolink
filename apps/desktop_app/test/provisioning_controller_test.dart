// M2-4 控制器链路测试：自检 → 扫描 → 候选 → 连接 → 读能力全链路；
// 连接失败回候选列表；能力失败走协议错误；扫描超时空态与停源；
// 候选生命周期随扫描任务。
library;

import 'dart:async';

import 'package:ble_universal/ble_universal.dart';
import 'package:communication_domain/communication_domain.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provisioning_session/provisioning_session.dart';

import 'package:desktop_app/provisioning/provisioning_controller.dart';
import 'package:desktop_app/services/environment_probe.dart';

import 'provisioning_fakes.dart';

ProvisioningController makeController(
  FakeSource source, {
  DesktopEnvironmentProbe? probe,
  Future<CtGattChannel> Function(String, void Function(String))? connect,
  Stream<bool> Function(String deviceId)? linkEvents,
  Duration scanTimeout = const Duration(seconds: 20),
  Duration sweepInterval = const Duration(seconds: 3),
}) => ProvisioningController(
  environmentProbe: probe ?? readyProbe(),
  discoverySource: source,
  establishPairing: (_) async {},
  connectChannel: connect ?? ((_, __) async => FakeCtDevice()),
  // Default empty stream: cases not exercising link loss never touch
  // the universal_ble static (no plugin in the test environment).
  linkEvents: linkEvents ?? ((_) => const Stream<bool>.empty()),
  scanTimeout: scanTimeout,
  sweepInterval: sweepInterval,
  // 旧用例语义是「自检过即进扫描」：零等待跳过倒计时。
  selfCheckHold: Duration.zero,
);

/// Drives selfcheck → candidate → connect up to choosingSections; registers
/// teardowns in the enclosing test scope.
Future<ProvisioningController> connectedToCaps(
  FakeSource source,
  FakeCtDevice device, {
  Future<CtGattChannel> Function(String, void Function(String))? connect,
  Stream<bool> Function(String deviceId)? linkEvents,
}) async {
  final controller = makeController(
    source,
    connect: connect ?? ((_, __) async => device),
    linkEvents: linkEvents,
  );
  addTearDown(controller.dispose);
  addTearDown(source.close);
  addTearDown(device.close);
  await controller.runSelfCheck();
  // Phase events are delivered async: wait for the scan subscription before
  // feeding a candidate, otherwise the broadcast stream drops it.
  await until(() => source.startCount == 1, 'selfcheck did not start scan');
  source.emit(sampleCandidate());
  await until(
    () => controller.phase == SessionPhase.resultsAvailable,
    'candidate did not move phase',
  );
  await controller.selectCandidate(controller.candidates.first);
  expect(controller.phase, SessionPhase.choosingSections);
  return controller;
}

void main() {
  test(
    'full chain: selfcheck → scan → candidate → connect → capabilities',
    () async {
      final source = FakeSource();
      final device = FakeCtDevice();
      final controller = makeController(
        source,
        connect: (_, __) async => device,
      );
      addTearDown(controller.dispose);
      addTearDown(source.close);
      addTearDown(device.close);

      await controller.runSelfCheck();
      expect(controller.phase, SessionPhase.scanning);
      expect(controller.environmentReport!.canProceed, isTrue);
      await until(() => source.startCount == 1, 'selfcheck did not start scan');

      source.emit(sampleCandidate());
      await until(
        () => controller.phase == SessionPhase.resultsAvailable,
        'candidate did not move phase',
      );
      // 连续扫描（v6）：出候选不停源，行随 TTL 老去；源仅在超时/选择/清理时停。
      expect(source.stopCount, 0);
      expect(controller.candidates, hasLength(1));

      await controller.selectCandidate(controller.candidates.first);
      expect(controller.phase, SessionPhase.choosingSections);
      expect(controller.deviceInfo!.model, 'NE101');
      expect(controller.deviceInfo!.deviceName, 'NE101-AABBCC');
      expect(controller.capabilities!.sections.map((section) => section.name), [
        'wifi',
        'cellular',
        'mqtt',
      ]);
      expect(controller.capabilities!.currentNetwork, isNull);
      expect(controller.connectSteps, isNotEmpty);
      // v7d timeline: every recorded step carries a wall-clock stamp, one
      // per entry, all landed before "now".
      expect(
        controller.connectStepTimes.length,
        controller.connectSteps.length,
      );
      final now = DateTime.now();
      for (final stamp in controller.connectStepTimes) {
        expect(stamp.isBefore(now), isTrue);
      }
    },
  );

  test('v7d connectStepTimes: cleared and refilled on connect retry', () async {
    final source = FakeSource();
    final controller = makeController(
      source,
      connect: (_, __) async => throw Exception('gatt link gone'),
    );
    addTearDown(controller.dispose);
    addTearDown(source.close);

    await controller.runSelfCheck();
    // 相位事件异步投递：订阅挂上（源已启动）再喂候选，否则广播流丢弃。
    await until(() => source.startCount == 1, 'selfcheck did not start scan');
    source.emit(sampleCandidate());
    await until(
      () => controller.phase == SessionPhase.resultsAvailable,
      'candidate did not move phase',
    );

    await controller.selectCandidate(controller.candidates.first);
    expect(controller.phase, SessionPhase.connectionError);
    expect(controller.connectStepTimes, isNotEmpty);
    final failedStampCount = controller.connectStepTimes.length;

    // choosingSections has no edge back to resultsAvailable, so the
    // reachable clear-and-refill path is retry after a failed connect.
    final retryStart = DateTime.now();
    await controller.retryConnect();
    expect(controller.phase, SessionPhase.connectionError);
    // The retry's stamps replace the failed run's: parity with the step
    // list (an append would double it) and every stamp lands at or after
    // the moment the retry began (direct wall-clock comparison ties on
    // Windows clock resolution, so compare against the retry boundary).
    expect(controller.connectStepTimes.length, controller.connectSteps.length);
    expect(controller.connectStepTimes.length, failedStampCount);
    for (final stamp in controller.connectStepTimes) {
      expect(stamp.isBefore(retryStart), isFalse);
    }
  });

  test('connect failure → connectionError → switch back to results', () async {
    final source = FakeSource();
    final controller = makeController(
      source,
      connect: (_, __) async => throw Exception('gatt link gone'),
    );
    addTearDown(controller.dispose);
    addTearDown(source.close);

    await controller.runSelfCheck();
    // 相位事件异步投递：订阅挂上（源已启动）再喂候选，否则广播流丢弃。
    await until(() => source.startCount == 1, 'selfcheck did not start scan');
    source.emit(sampleCandidate());
    await until(
      () => controller.phase == SessionPhase.resultsAvailable,
      'candidate did not move phase',
    );

    await controller.selectCandidate(controller.candidates.first);
    expect(controller.phase, SessionPhase.connectionError);
    expect(controller.lastProblem!.reason, 'connect_failed');

    controller.switchCandidate();
    expect(controller.phase, SessionPhase.resultsAvailable);
    expect(controller.candidates, hasLength(1));
  });

  test('capabilities failure → capabilityError with protocol reason', () async {
    final source = FakeSource();
    final device = FakeCtDevice(rejectDeviceInfo: true);
    final controller = makeController(source, connect: (_, __) async => device);
    addTearDown(controller.dispose);
    addTearDown(source.close);
    addTearDown(device.close);

    await controller.runSelfCheck();
    // 相位事件异步投递：订阅挂上（源已启动）再喂候选，否则广播流丢弃。
    await until(() => source.startCount == 1, 'selfcheck did not start scan');
    source.emit(sampleCandidate());
    await until(
      () => controller.phase == SessionPhase.resultsAvailable,
      'candidate did not move phase',
    );

    await controller.selectCandidate(controller.candidates.first);
    expect(controller.phase, SessionPhase.capabilityError);
    expect(controller.lastProblem!.reason, 'device_info_error');
    expect(controller.lastProblem!.message, contains('ERR_DEVICE_BUSY'));
  });

  test('scan timeout with no candidate → scanEmpty, source stopped', () async {
    final source = FakeSource();
    final controller = makeController(
      source,
      scanTimeout: const Duration(milliseconds: 60),
    );
    addTearDown(controller.dispose);
    addTearDown(source.close);

    await controller.runSelfCheck();
    expect(controller.phase, SessionPhase.scanning);
    await until(
      () => controller.phase == SessionPhase.scanEmpty,
      'scan timeout did not fire',
    );
    await until(() => source.stopCount >= 1, 'scan source not stopped');

    // 空态重扫：清理 → 新扫描循环。
    await controller.rescan();
    expect(controller.phase, SessionPhase.scanning);
    await until(() => source.startCount == 2, 'rescan did not restart scan');
  });

  test('rescan drops previous candidates (list scoped to scan task)', () async {
    final source = FakeSource();
    final controller = makeController(source);
    addTearDown(controller.dispose);
    addTearDown(source.close);

    await controller.runSelfCheck();
    // 相位事件异步投递：订阅挂上（源已启动）再喂候选，否则广播流丢弃。
    await until(() => source.startCount == 1, 'selfcheck did not start scan');
    source.emit(sampleCandidate());
    await until(
      () => controller.phase == SessionPhase.resultsAvailable,
      'candidate did not move phase',
    );
    expect(controller.candidates, hasLength(1));

    await controller.rescan();
    await until(() => source.startCount == 2, 'rescan did not restart scan');
    expect(controller.candidates, isEmpty);
  });

  // v6 连续扫描：候选 TTL 过期扫空后自动重开扫描窗口。
  test('swept-empty results auto-restart the scan window (v6)', () async {
    final source = FakeSource();
    final controller = makeController(
      source,
      sweepInterval: const Duration(milliseconds: 20),
    );
    addTearDown(controller.dispose);
    addTearDown(source.close);

    await controller.runSelfCheck();
    await until(() => source.startCount == 1, 'selfcheck did not start scan');
    // 出生即超过 TTL 的候选：首个 sweep tick 即被淘汰。
    source.emit(
      sampleCandidate(
        seen: DateTime.now().subtract(const Duration(seconds: 30)),
      ),
    );
    await until(
      () => controller.phase == SessionPhase.resultsAvailable,
      'candidate did not move phase',
    );
    expect(source.stopCount, 0); // 连续扫描：候选期源保持运行

    await until(
      () => controller.phase == SessionPhase.scanning && source.startCount == 2,
      'sweep expiry did not auto-rescan',
    );
    expect(controller.candidates, isEmpty);
  });

  // v6 连接页「重试连接」：同一候选原链路重放。
  test(
    'retryConnect replays the connect chain on the same candidate',
    () async {
      final source = FakeSource();
      final device = FakeCtDevice();
      var attempts = 0;
      final controller = makeController(
        source,
        connect: (_, __) async {
          attempts++;
          if (attempts == 1) throw Exception('gatt link gone');
          return device;
        },
      );
      addTearDown(controller.dispose);
      addTearDown(source.close);
      addTearDown(device.close);

      await controller.runSelfCheck();
      await until(() => source.startCount == 1, 'selfcheck did not start scan');
      source.emit(sampleCandidate());
      await until(
        () => controller.phase == SessionPhase.resultsAvailable,
        'candidate did not move phase',
      );

      await controller.selectCandidate(controller.candidates.first);
      expect(controller.phase, SessionPhase.connectionError);

      await controller.retryConnect();
      expect(attempts, 2);
      expect(controller.phase, SessionPhase.choosingSections);
      expect(controller.selectedCandidate, isNotNull);
    },
  );

  test(
    'blocked selfcheck stays in selfChecking without starting scan',
    () async {
      final source = FakeSource();
      final controller = makeController(source, probe: blockedProbe());
      addTearDown(controller.dispose);
      addTearDown(source.close);

      await controller.runSelfCheck();
      expect(controller.environmentReport!.canProceed, isFalse);
      expect(controller.phase, SessionPhase.selfChecking);
      expect(source.startCount, 0);
    },
  );

  group('M3b selfcheck hold / recheck (A1/A2/A3)', () {
    test(
      'countdown holds after pass; stay cancels; scan-now enters scanning',
      () async {
        final source = FakeSource();
        final controller = ProvisioningController(
          environmentProbe: readyProbe(),
          discoverySource: source,
          establishPairing: (_) async {},
          connectChannel: (_, __) async => FakeCtDevice(),
          selfCheckHold: const Duration(seconds: 1),
        );
        addTearDown(controller.dispose);
        addTearDown(source.close);

        await controller.runSelfCheck();
        expect(controller.phase, SessionPhase.selfChecking);
        expect(controller.selfCheckCountdown, 1);

        controller.stayOnSelfCheck();
        expect(controller.selfCheckCountdown, isNull);
        expect(controller.selfCheckHeld, isTrue);
        // 停留后倒计时不点火：真实时钟等过 1s 窗口仍留在自检。
        await Future<void>.delayed(const Duration(milliseconds: 1300));
        expect(controller.phase, SessionPhase.selfChecking);

        controller.startScanNow();
        expect(controller.phase, SessionPhase.scanning);
      },
    );

    test('countdown expiry auto-enters scanning', () async {
      final source = FakeSource();
      final controller = ProvisioningController(
        environmentProbe: readyProbe(),
        discoverySource: source,
        establishPairing: (_) async {},
        connectChannel: (_, __) async => FakeCtDevice(),
        // 亚秒 hold：inSeconds=0，首个 1s tick 即进入扫描。
        selfCheckHold: const Duration(milliseconds: 300),
      );
      addTearDown(controller.dispose);
      addTearDown(source.close);

      await controller.runSelfCheck();
      expect(controller.selfCheckCountdown, 0);
      await until(
        () => controller.phase == SessionPhase.scanning,
        'countdown expiry did not enter scanning',
      );
    });

    test(
      'walk reveals channels one-by-one, then arms the countdown (v6)',
      () async {
        final source = FakeSource();
        final controller = ProvisioningController(
          environmentProbe: readyProbe(),
          discoverySource: source,
          establishPairing: (_) async {},
          connectChannel: (_, __) async => FakeCtDevice(),
          selfCheckHold: const Duration(seconds: 5),
        );
        addTearDown(controller.dispose);
        addTearDown(source.close);

        final running = controller.runSelfCheck();
        // The walk starts at row 0 the moment the report lands.
        await until(
          () => controller.selfCheckWalkIndex == 0,
          'walk did not start at row 0',
        );
        // The countdown must wait until every channel has been revealed.
        expect(controller.selfCheckCountdown, isNull);
        await running;
        expect(controller.selfCheckWalkIndex, -1);
        expect(controller.selfCheckCountdown, 5);
        controller.stayOnSelfCheck();
      },
    );

    test('stay during the walk holds with all rows revealed (v6)', () async {
      final source = FakeSource();
      final controller = ProvisioningController(
        environmentProbe: readyProbe(),
        discoverySource: source,
        establishPairing: (_) async {},
        connectChannel: (_, __) async => FakeCtDevice(),
        selfCheckHold: const Duration(seconds: 5),
      );
      addTearDown(controller.dispose);
      addTearDown(source.close);

      final running = controller.runSelfCheck();
      await until(
        () => controller.selfCheckWalkIndex == 0,
        'walk did not start at row 0',
      );
      controller.stayOnSelfCheck();
      expect(controller.selfCheckWalkIndex, -1);
      expect(controller.selfCheckHeld, isTrue);
      expect(controller.selfCheckCountdown, isNull);
      // runSelfCheck resolves early via the cancelled walk — no countdown arm.
      await running;
      expect(controller.selfCheckHeld, isTrue);
      expect(controller.selfCheckCountdown, isNull);
      expect(controller.phase, SessionPhase.selfChecking);
      await Future<void>.delayed(const Duration(milliseconds: 700));
      expect(controller.selfCheckCountdown, isNull); // no late arm either
    });

    test('recheck from a later phase refreshes the report only (A2)', () async {
      final source = FakeSource();
      final controller = makeController(source);
      addTearDown(controller.dispose);
      addTearDown(source.close);

      await controller.runSelfCheck();
      await until(() => source.startCount == 1, 'selfcheck did not start scan');
      source.emit(sampleCandidate());
      await until(
        () => controller.phase == SessionPhase.resultsAvailable,
        'candidate did not move phase',
      );

      // 中途回访自检页点「重新检测」：报告刷新，相位与扫描状态不动。
      final before = controller.environmentReport;
      await controller.runSelfCheck();
      expect(controller.phase, SessionPhase.resultsAvailable);
      expect(identical(controller.environmentReport, before), isFalse);
      expect(source.startCount, 1);
      expect(source.stopCount, 0); // 连续扫描：出候选不停源
    });

    // Round-3 A2: a completed check must stamp selfCheckAt and always clear
    // the in-flight flag — a stuck flag silences the re-check button forever.
    test(
      'every check stamps selfCheckAt and clears the in-flight flag',
      () async {
        final source = FakeSource();
        final controller = makeController(source);
        addTearDown(controller.dispose);
        addTearDown(source.close);

        await controller.runSelfCheck();
        final first = controller.selfCheckAt;
        expect(first, isNotNull);
        expect(controller.selfChecking, isFalse);

        // Re-check (mid-scan revisit): fresh stamp object, flag not left on.
        await controller.runSelfCheck();
        expect(identical(controller.selfCheckAt, first), isFalse);
        expect(controller.selfChecking, isFalse);
        expect(controller.phase, SessionPhase.scanning);
      },
    );

    test(
      'blocked selfcheck can be re-run after the environment is fixed (A3)',
      () async {
        final source = FakeSource();
        // 双通道都关：只关蓝牙时 Wi-Fi 网卡仍会放行（canProceed 单通道即可）。
        var ready = false;
        final probe = DesktopEnvironmentProbe(
          probeBle: () async => CtEnvironmentReport(
            readiness: ready ? CtBleReadiness.ready : CtBleReadiness.poweredOff,
            detail: 'fake switchable',
          ),
          enumerateAdapters: () async => ready
              ? '[{"Name":"Wi-Fi","Status":"Up","PhysicalMediaType":"Native 802.11"}]'
              : null,
        );
        final controller = makeController(source, probe: probe);
        addTearDown(controller.dispose);
        addTearDown(source.close);

        await controller.runSelfCheck();
        expect(controller.environmentReport!.canProceed, isFalse);
        expect(controller.phase, SessionPhase.selfChecking);
        expect(source.startCount, 0);

        // 修复环境后重新检测：同一次运行内即可放行（不再需要重启应用）。
        ready = true;
        await controller.runSelfCheck();
        expect(controller.phase, SessionPhase.scanning);
        await until(() => source.startCount == 1, 'recheck did not start scan');
      },
    );
  });

  group('M3 form / delivery / scan', () {
    test(
      'beginEditing prefills from config.get (masked secrets skipped)',
      () async {
        final source = FakeSource();
        final device = FakeCtDevice();
        final controller = await connectedToCaps(source, device);

        await controller.beginEditing({'wifi', 'mqtt'});
        expect(controller.phase, SessionPhase.editingConfig);
        expect(controller.editingSections, ['wifi', 'mqtt']);
        await until(() => controller.prefillDone, 'prefill did not finish');

        final wifi = controller.drafts['wifi'] as WifiSection;
        expect(wifi.ssid, 'Office-2.4G'); // read-back applied
        expect(wifi.password, isEmpty); // masked value never enters the draft
        final mqtt = controller.drafts['mqtt'] as MqttSection;
        expect(mqtt.enable, isTrue);
        expect(mqtt.port, 8883);
      },
    );

    test(
      'openSection grows the round in capability order and keeps drafts',
      () async {
        final source = FakeSource();
        final device = FakeCtDevice();
        final controller = await connectedToCaps(source, device);

        // First open starts the round with just that module.
        await controller.openSection('cellular');
        expect(controller.phase, SessionPhase.editingConfig);
        expect(controller.editingSections, ['cellular']);
        await until(() => controller.prefillDone, 'prefill did not finish');

        // A second module joins the round in capability order (wifi first).
        await controller.openSection('wifi');
        expect(controller.editingSections, ['wifi', 'cellular']);
        // Later-opened module prefills from the cached config.get snapshot —
        // no second request for the same read-back.
        final wifi = controller.drafts['wifi'] as WifiSection;
        expect(wifi.ssid, 'Office-2.4G');

        // Reopening an open module is a pure view switch: no reorder, and the
        // edited draft is untouched.
        controller.updateDraft(const CellularSection(apn: 'cmnet'));
        await controller.openSection('cellular');
        expect(controller.editingSections, ['wifi', 'cellular']);
        expect((controller.drafts['cellular'] as CellularSection).apn, 'cmnet');

        // Unknown names are no-ops.
        await controller.openSection('nope');
        expect(controller.editingSections, ['wifi', 'cellular']);
      },
    );

    test(
      'submit stores both sections then finish returns to scanning',
      () async {
        final source = FakeSource();
        final device = FakeCtDevice();
        final controller = await connectedToCaps(source, device);

        await controller.beginEditing({'wifi', 'mqtt'});
        await until(() => controller.prefillDone, 'prefill did not finish');
        controller.updateDraft(
          const WifiSection(ssid: 'Office-2.4G', password: 'example-password'),
        );
        controller.updateDraft(
          const MqttSection(enable: true, host: 'mqtt.example.com', port: 8883),
        );
        await controller.submit();

        expect(controller.phase, SessionPhase.completed);
        expect(
          controller.deliveryResult!.stored,
          containsAll(['wifi', 'mqtt']),
        );
        expect(controller.deliveryResult!.apply, 'reconnect');
        // v6: 成功下发即记回执（历史页数据源）。
        expect(controller.sessionHistory, hasLength(1));
        expect(controller.sessionHistory.single.deviceName, 'NE101-AABBCC');
        expect(controller.sessionHistory.single.model, 'NE101');
        expect(
          controller.sessionHistory.single.sections,
          containsAll(['wifi', 'mqtt']),
        );
        expect(controller.sessionHistory.single.appliedAt, isNotNull);
        expect(device.lastConfigSet, {
          'wifi': {'ssid': 'Office-2.4G', 'password': 'example-password'},
          'mqtt': {'enable': true, 'host': 'mqtt.example.com', 'port': 8883},
        });

        await controller.finishSession();
        expect(controller.phase, SessionPhase.scanning);
        expect(controller.drafts, isEmpty); // editing state cleared
        expect(controller.pageForPhase, 'scan');
      },
    );

    test('client validation blocks submit with per-field problems', () async {
      final source = FakeSource();
      final device = FakeCtDevice();
      final controller = await connectedToCaps(source, device);

      await controller.beginEditing({'wifi'});
      await until(() => controller.prefillDone, 'prefill did not finish');
      controller.updateDraft(const WifiSection(ssid: 'Net', password: 'short'));
      await controller.submit();

      // Stays on the form with the field marked; nothing reached the device.
      expect(controller.phase, SessionPhase.editingConfig);
      expect(
        controller.sectionProblems['wifi'],
        contains(
          predicate<FieldProblem>(
            (problem) =>
                problem.field == 'password' &&
                problem.code == FieldProblemCode.tooShort,
          ),
        ),
      );
      expect(device.lastConfigSet, isNull);

      controller.updateDraft(
        const WifiSection(ssid: 'Net', password: 'example-password'),
      );
      await controller.submit();
      expect(controller.phase, SessionPhase.completed);
    });

    test('undeclared field is gated client-side before config.set', () async {
      final source = FakeSource();
      final device = FakeCtDevice(); // ne101 wifi fields: ssid, password only
      final controller = await connectedToCaps(source, device);

      await controller.beginEditing({'wifi'});
      await until(() => controller.prefillDone, 'prefill did not finish');
      controller.updateDraft(
        const WifiSection(
          ssid: 'Net',
          password: 'example-password',
          bssid: 'aa:bb:cc:dd:ee:ff',
        ),
      );
      await controller.submit();

      expect(controller.phase, SessionPhase.editingConfig);
      expect(
        controller.sectionProblems['wifi'],
        contains(
          predicate<FieldProblem>(
            (problem) =>
                problem.field == 'bssid' &&
                problem.code == FieldProblemCode.notDeclared,
          ),
        ),
      );
      expect(device.lastConfigSet, isNull);
    });

    test(
      'device rejection keeps drafts; editAgain returns to the form',
      () async {
        final source = FakeSource();
        final device = FakeCtDevice(rejectConfigSet: 'FIELD_NOT_SUPPORTED');
        final controller = await connectedToCaps(source, device);

        await controller.beginEditing({'wifi'});
        await until(() => controller.prefillDone, 'prefill did not finish');
        controller.updateDraft(
          const WifiSection(ssid: 'Office-2.4G', password: 'example-password'),
        );
        await controller.submit();

        expect(controller.phase, SessionPhase.operationError);
        // Problems are delivered through an async stream: wait for the event.
        await until(
          () => controller.lastProblem?.reason == 'field_not_supported',
          'rejection problem not delivered',
        );
        expect(
          controller.lastProblem!.message,
          contains('FIELD_NOT_SUPPORTED'),
        );

        controller.editAgain();
        expect(controller.phase, SessionPhase.editingConfig);
        final wifi = controller.drafts['wifi'] as WifiSection;
        expect(wifi.ssid, 'Office-2.4G'); // entries preserved
        expect(wifi.password, 'example-password');
      },
    );

    test(
      'network scan pages via cursor; picking fills the ssid draft',
      () async {
        final source = FakeSource();
        final device = FakeCtDevice();
        final controller = await connectedToCaps(source, device);

        await controller.beginEditing({'wifi'});
        await until(() => controller.prefillDone, 'prefill did not finish');

        await controller.scanNetworks('wifi');
        expect(
          controller.scanItems.map((network) => network.networkId).toList(),
          ['Office-2.4G', 'CT-HaLow'],
        );
        expect(controller.scanMore, isTrue);

        await controller.loadMoreNetworks();
        expect(controller.scanItems.last.networkId, 'Neighbor-5G');
        expect(controller.scanMore, isFalse);
        expect(device.lastScanRequest, {'section': 'wifi', 'cursor': 'page-2'});

        controller.pickNetwork(controller.scanItems.first);
        expect((controller.drafts['wifi'] as WifiSection).ssid, 'Office-2.4G');
      },
    );

    test('unsupported config.get degrades to empty prefill', () async {
      final source = FakeSource();
      final device = FakeCtDevice(supportsConfigGet: false);
      final controller = await connectedToCaps(source, device);

      await controller.beginEditing({'wifi'});
      await until(() => controller.prefillDone, 'prefill did not finish');
      expect(controller.drafts['wifi'], isA<WifiSection>());
      expect((controller.drafts['wifi'] as WifiSection).ssid, isEmpty);
    });

    test('ne301 shape: comm selector gated by declared networks', () async {
      final source = FakeSource();
      final device = FakeCtDevice(capsShape: 'ne301');
      final controller = await connectedToCaps(source, device);

      expect(controller.declaredNetworks, {'wifi', 'cellular', 'ethernet'});
      await controller.beginEditing({'comm', 'ethernet', 'webhook'});
      // Readonly ethernet is excluded from the editing round.
      expect(controller.editingSections, ['comm', 'webhook']);

      // halow is not a declared network section: client blocks the submit.
      controller.updateDraft(
        const CommSection(type: CommunicationMode.wifiHalow),
      );
      controller.updateDraft(
        const WebhookSection(
          enable: true,
          url: 'https://ops.example.com/hooks/camera',
        ),
      );
      await controller.submit();
      expect(controller.phase, SessionPhase.editingConfig);
      expect(
        controller.sectionProblems['comm'],
        contains(
          predicate<FieldProblem>(
            (problem) =>
                problem.field == 'type' &&
                problem.code == FieldProblemCode.invalidValue,
          ),
        ),
      );
      expect(device.lastConfigSet, isNull);

      // Back to a declared mode: both sections go through in one request.
      controller.updateDraft(const CommSection(type: CommunicationMode.cat1));
      await controller.submit();
      expect(controller.phase, SessionPhase.completed);
      expect(device.lastConfigSet!.keys.toSet(), {'comm', 'webhook'});
    });

    // ---- §13.3 / §13.4 acceptance cases ----

    test('§13.3 Wi-Fi: open network omits the password field', () async {
      final source = FakeSource();
      final device = FakeCtDevice();
      final controller = await connectedToCaps(source, device);

      await controller.beginEditing({'wifi'});
      await until(() => controller.prefillDone, 'prefill did not finish');
      // A hidden SSID is typed manually through the same field.
      controller.updateDraft(
        const WifiSection(ssid: 'Cafe-Guest', password: ''),
      );
      await controller.submit();

      expect(controller.phase, SessionPhase.completed);
      // Empty password = open network: the field never reaches the wire.
      expect(device.lastConfigSet!['wifi'], {'ssid': 'Cafe-Guest'});
    });

    test(
      '§13.3 CAT1: manual apn/pin/auth submit; malformed pin blocked',
      () async {
        final source = FakeSource();
        final device =
            FakeCtDevice(); // ne101 cellular: apn/username/password/pin/auth
        final controller = await connectedToCaps(source, device);

        await controller.beginEditing({'cellular'});
        await until(() => controller.prefillDone, 'prefill did not finish');
        controller.updateDraft(
          const CellularSection(apn: 'cmiot.iot', pin: '12', auth: 'pap'),
        );
        await controller.submit();
        expect(controller.phase, SessionPhase.editingConfig);
        expect(
          controller.sectionProblems['cellular'],
          contains(
            predicate<FieldProblem>(
              (problem) =>
                  problem.field == 'pin' &&
                  problem.code == FieldProblemCode.invalidFormat,
            ),
          ),
        );
        expect(device.lastConfigSet, isNull);

        controller.updateDraft(
          const CellularSection(apn: 'cmiot.iot', pin: '1234', auth: 'pap'),
        );
        await controller.submit();
        expect(controller.phase, SessionPhase.completed);
        expect(device.lastConfigSet!['cellular'], {
          'apn': 'cmiot.iot',
          'pin': '1234',
          'auth': 'pap',
        });
      },
    );

    test(
      '§13.3 CAT1: preconfigured SIM (fields=[]) submits an empty section',
      () async {
        final source = FakeSource();
        final device = FakeCtDevice(capsShape: 'halow');
        final controller = await connectedToCaps(source, device);

        await controller.beginEditing({'cellular'});
        await until(() => controller.prefillDone, 'prefill did not finish');
        await controller.submit();

        expect(controller.phase, SessionPhase.completed);
        // {} confirms "use SIM defaults" without any field on the wire.
        expect(device.lastConfigSet!['cellular'], isEmpty);
      },
    );

    test('§13.3 HaLow: scan pick fills ssid and country', () async {
      final source = FakeSource();
      final device = FakeCtDevice(capsShape: 'halow');
      final controller = await connectedToCaps(source, device);

      await controller.beginEditing({'halow'});
      await until(() => controller.prefillDone, 'prefill did not finish');
      await controller.scanNetworks('halow');
      controller.pickNetwork(
        controller.scanItems.firstWhere(
          (network) => network.networkId == 'CT-HaLow',
        ),
      );
      final draft = controller.drafts['halow'] as HalowSection;
      expect(draft.ssid, 'CT-HaLow');
      expect(draft.country, 'CN'); // extension field applied (declared)

      await controller.submit();
      expect(controller.phase, SessionPhase.completed);
      expect(device.lastConfigSet!['halow'], {
        'ssid': 'CT-HaLow',
        'country': 'CN',
      });
    });

    test('§13.4 service-only submit works without an active network', () async {
      final source = FakeSource();
      final device = FakeCtDevice();
      final controller = await connectedToCaps(source, device);

      expect(controller.capabilities!.currentNetwork, isNull);
      await controller.beginEditing({'mqtt'});
      await until(() => controller.prefillDone, 'prefill did not finish');
      controller.updateDraft(
        const MqttSection(enable: true, host: 'mqtt.example.com', port: 1883),
      );
      await controller.submit();

      expect(controller.phase, SessionPhase.completed);
      expect(device.lastConfigSet!.keys, ['mqtt']);
    });

    test(
      '§13.4 undeclared service section is excluded from the round',
      () async {
        final source = FakeSource();
        final device = FakeCtDevice(); // ne101 declares no webhook section
        final controller = await connectedToCaps(source, device);

        await controller.beginEditing({'wifi', 'webhook'});
        expect(controller.editingSections, ['wifi']);
      },
    );
  });

  group('link loss (v7c)', () {
    test(
      'drop during editing keeps the round; reconnect resumes in place',
      () async {
        final source = FakeSource();
        final device = FakeCtDevice();
        final link = StreamController<bool>.broadcast();
        addTearDown(link.close);
        final controller = await connectedToCaps(
          source,
          device,
          linkEvents: (_) => link.stream,
        );

        await controller.openSection('wifi');
        controller.updateDraft(
          const WifiSection(ssid: 'Home-2.4G', password: 'example-password'),
        );

        link.add(false);
        await until(
          () => controller.phase == SessionPhase.linkLost,
          'drop did not fire',
        );
        expect(controller.linkLostDuringDelivery, isFalse);
        expect(controller.editingSections, ['wifi']);
        expect((controller.drafts['wifi'] as WifiSection).ssid, 'Home-2.4G');

        await controller.reconnectLink();
        expect(controller.phase, SessionPhase.editingConfig);
        expect(controller.linkReconnectFailed, isFalse);
        expect((controller.drafts['wifi'] as WifiSection).ssid, 'Home-2.4G');

        // Idempotent redelivery: submit succeeds on the restored session.
        await controller.submit();
        expect(controller.phase, SessionPhase.completed);
        expect(device.lastConfigSet!.keys, ['wifi']);
      },
    );

    test('reconnect failure stays on linkLost with the retry note', () async {
      final source = FakeSource();
      final device = FakeCtDevice();
      final link = StreamController<bool>.broadcast();
      addTearDown(link.close);
      var connects = 0;
      final controller = await connectedToCaps(
        source,
        device,
        connect: (_, __) async {
          connects++;
          // Only the FIRST reconnect attempt fails; the retry connects.
          if (connects == 2) throw Exception('device asleep');
          return device;
        },
        linkEvents: (_) => link.stream,
      );

      await controller.openSection('wifi');
      link.add(false);
      await until(
        () => controller.phase == SessionPhase.linkLost,
        'drop did not fire',
      );

      await controller.reconnectLink();
      expect(controller.phase, SessionPhase.linkLost); // not restored
      expect(controller.linkReconnectFailed, isTrue);

      // Third connect succeeds -> editing restored (retry note cleared).
      await controller.reconnectLink();
      expect(controller.phase, SessionPhase.editingConfig);
      expect(controller.linkReconnectFailed, isFalse);
    });

    test(
      'drop during delivering discards the late result (idempotent redo)',
      () async {
        final source = FakeSource();
        final device = GatedFakeCtDevice();
        final link = StreamController<bool>.broadcast();
        addTearDown(link.close);
        final controller = await connectedToCaps(
          source,
          device,
          linkEvents: (_) => link.stream,
        );

        await controller.openSection('wifi');
        controller.updateDraft(
          const WifiSection(ssid: 'Home-2.4G', password: 'example-password'),
        );
        device.armGate(); // hold config.set in flight
        unawaited(controller.submit());
        await until(
          () => controller.phase == SessionPhase.delivering,
          'submit did not reach delivering',
        );

        link.add(false);
        await until(
          () => controller.phase == SessionPhase.linkLost,
          'drop did not fire',
        );
        expect(controller.linkLostDuringDelivery, isTrue);

        // Release the held first frame: close already aborted the remaining
        // fragments, so the device never sees a complete packet — exactly the
        // idempotent-redo scenario; the late result is discarded by the phase
        // guard and the UI stays on the modal.
        device.openGate();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(controller.phase, SessionPhase.linkLost);
        expect(controller.deliveryResult, isNull);
        expect(device.lastConfigSet, isNull);
      },
    );

    test(
      'rescan from linkLost clears the round and returns to scanning',
      () async {
        final source = FakeSource();
        final device = FakeCtDevice();
        final link = StreamController<bool>.broadcast();
        addTearDown(link.close);
        final controller = await connectedToCaps(
          source,
          device,
          linkEvents: (_) => link.stream,
        );

        await controller.openSection('wifi');
        link.add(false);
        await until(
          () => controller.phase == SessionPhase.linkLost,
          'drop did not fire',
        );

        await controller.rescan();
        expect(controller.phase, SessionPhase.scanning);
        expect(controller.editingSections, isEmpty);
        expect(controller.drafts, isEmpty);
      },
    );
  });

  group('M5 three-channel scan', () {
    test(
      'AP/CT-Disc-only candidates stay visible but do not enter GATT',
      () async {
        final source = FakeSource();
        var connectCalls = 0;
        final controller = ProvisioningController(
          environmentProbe: readyProbe(),
          discoverySource: source,
          establishPairing: (_) async {},
          connectChannel: (_, __) async {
            connectCalls++;
            return FakeCtDevice();
          },
          linkEvents: (_) => const Stream<bool>.empty(),
          selfCheckHold: Duration.zero,
        );
        addTearDown(controller.dispose);
        addTearDown(source.close);

        await controller.runSelfCheck();
        await until(
          () => source.startCount == 1,
          'selfcheck did not start scan',
        );
        // Same device seen through the AP channel only: display candidate.
        source.emit(
          sampleCandidate(
            candidateId: 'ap:CT-AP-BBC6DC',
            modelHint: 'NE101-P',
          ).copyWith(channels: const {DiscoveryChannel.accessPoint}),
        );
        await until(
          () => controller.candidates.isNotEmpty,
          'AP candidate never arrived',
        );
        expect(controller.phase, SessionPhase.resultsAvailable);

        await controller.selectCandidate(controller.candidates.single);
        await until(
          () => controller.phase == SessionPhase.connectionError,
          'guard did not fail the connect chain',
        );
        expect(controller.lastProblem?.reason, 'channel_unsupported');
        expect(connectCalls, 0);

        // The row is still there after the failure (back to the list).
        controller.switchCandidate();
        expect(controller.phase, SessionPhase.resultsAvailable);
        expect(controller.candidates.single.macSuffix, isNotNull);
      },
    );

    test('merged BLE+AP candidate connects over the BLE chain', () async {
      final source = FakeSource();
      final device = FakeCtDevice();
      final connectIds = <String>[];
      final controller = ProvisioningController(
        environmentProbe: readyProbe(),
        discoverySource: source,
        establishPairing: (_) async {},
        connectChannel: (deviceId, _) async {
          connectIds.add(deviceId);
          return device;
        },
        linkEvents: (_) => const Stream<bool>.empty(),
        selfCheckHold: Duration.zero,
      );
      addTearDown(controller.dispose);
      addTearDown(source.close);
      addTearDown(device.close);

      await controller.runSelfCheck();
      await until(() => source.startCount == 1, 'selfcheck did not start scan');
      // Cross-channel merge: the AP sighting arrives first, then BLE — the
      // registry keeps one row carrying both channels; the merged row's id
      // is the AP one, but the GATT chain must receive the BLE platform id.
      source.emit(
        sampleCandidate(
          candidateId: 'ap:CT-AP-A1B2C3',
          modelHint: 'NE101-P',
        ).copyWith(channels: const {DiscoveryChannel.accessPoint}),
      );
      source.emit(
        sampleCandidate(candidateId: 'ble-1').copyWith(
          channels: const {DiscoveryChannel.ble, DiscoveryChannel.accessPoint},
        ),
      );
      await until(
        () => controller.candidates.isNotEmpty,
        'candidates never arrived',
      );
      expect(controller.candidates.single.candidateId, 'ap:CT-AP-A1B2C3');
      expect(
        controller.candidates.single.channels,
        containsAll(<DiscoveryChannel>{
          DiscoveryChannel.ble,
          DiscoveryChannel.accessPoint,
        }),
      );

      await controller.selectCandidate(controller.candidates.single);
      await until(
        () => controller.phase == SessionPhase.choosingSections,
        'merged candidate did not connect',
      );
      expect(connectIds, ['ble-1']);
    });
  });
}
