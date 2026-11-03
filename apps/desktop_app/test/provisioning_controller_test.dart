// M2-4 控制器链路测试：自检 → 扫描 → 候选 → 连接 → 读能力全链路；
// 连接失败回候选列表；能力失败走协议错误；扫描超时空态与停源；
// 候选生命周期随扫描任务。
library;

import 'package:ble_adapter/ble_adapter.dart';
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
}
