// M2-4 控制器链路测试：自检 → 扫描 → 候选 → 连接 → 读能力全链路；
// 连接失败回候选列表；能力失败走协议错误；扫描超时空态与停源；
// 候选生命周期随扫描任务。
library;

import 'package:ble_adapter/ble_adapter.dart';
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
  Duration scanTimeout = const Duration(seconds: 20),
}) => ProvisioningController(
  environmentProbe: probe ?? readyProbe(),
  discoverySource: source,
  establishPairing: (_) async {},
  connectChannel: connect ?? ((_, __) async => FakeCtDevice()),
  scanTimeout: scanTimeout,
);

/// Drives selfcheck → candidate → connect up to choosingSections; registers
/// teardowns in the enclosing test scope.
Future<ProvisioningController> connectedToCaps(
  FakeSource source,
  FakeCtDevice device,
) async {
  final controller = makeController(source, connect: (_, __) async => device);
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
      // 出候选即停源：底层扫描资源与相位同步收敛。
      await until(() => source.stopCount >= 1, 'scan source not stopped');
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
    },
  );

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

  group('M3 form / delivery / scan', () {
    test('beginEditing prefills from config.get (masked secrets skipped)',
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
    });

    test('submit stores both sections then finish returns to scanning',
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
      expect(controller.deliveryResult!.stored, containsAll(['wifi', 'mqtt']));
      expect(controller.deliveryResult!.apply, 'reconnect');
      expect(device.lastConfigSet, {
        'wifi': {'ssid': 'Office-2.4G', 'password': 'example-password'},
        'mqtt': {'enable': true, 'host': 'mqtt.example.com', 'port': 8883},
      });

      await controller.finishSession();
      expect(controller.phase, SessionPhase.scanning);
      expect(controller.drafts, isEmpty); // editing state cleared
      expect(controller.pageForPhase, 'scan');
    });

    test('client validation blocks submit with per-field problems', () async {
      final source = FakeSource();
      final device = FakeCtDevice();
      final controller = await connectedToCaps(source, device);

      await controller.beginEditing({'wifi'});
      await until(() => controller.prefillDone, 'prefill did not finish');
      controller.updateDraft(
        const WifiSection(ssid: 'Net', password: 'short'),
      );
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

    test('device rejection keeps drafts; editAgain returns to the form',
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
      expect(controller.lastProblem!.message, contains('FIELD_NOT_SUPPORTED'));

      controller.editAgain();
      expect(controller.phase, SessionPhase.editingConfig);
      final wifi = controller.drafts['wifi'] as WifiSection;
      expect(wifi.ssid, 'Office-2.4G'); // entries preserved
      expect(wifi.password, 'example-password');
    });

    test('network scan pages via cursor; picking fills the ssid draft',
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
      expect(device.lastScanRequest, {
        'section': 'wifi',
        'cursor': 'page-2',
      });

      controller.pickNetwork(controller.scanItems.first);
      expect((controller.drafts['wifi'] as WifiSection).ssid, 'Office-2.4G');
    });

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
      controller.updateDraft(const WifiSection(ssid: 'Cafe-Guest', password: ''));
      await controller.submit();

      expect(controller.phase, SessionPhase.completed);
      // Empty password = open network: the field never reaches the wire.
      expect(device.lastConfigSet!['wifi'], {'ssid': 'Cafe-Guest'});
    });

    test('§13.3 CAT1: manual apn/pin/auth submit; malformed pin blocked',
        () async {
      final source = FakeSource();
      final device = FakeCtDevice(); // ne101 cellular: apn/username/password/pin/auth
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
    });

    test('§13.3 CAT1: preconfigured SIM (fields=[]) submits an empty section',
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
    });

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

    test('§13.4 undeclared service section is excluded from the round',
        () async {
      final source = FakeSource();
      final device = FakeCtDevice(); // ne101 declares no webhook section
      final controller = await connectedToCaps(source, device);

      await controller.beginEditing({'wifi', 'webhook'});
      expect(controller.editingSections, ['wifi']);
    });
  });
}
