// M5 softAP 连接链控制器测试：AP-only 候选经 join → HTTP 传输 → 能力读取
// 全链；join 失败映射 connectionError 并恢复原 Wi-Fi；配置中掉线
// （ap_unreachable）走 linkLost，重连重新 join 并恢复原网。
library;

import 'package:ap_discovery_adapter/ap_discovery_adapter.dart';
import 'package:discovery_domain/discovery_domain.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provisioning_session/provisioning_session.dart';

import 'package:desktop_app/provisioning/provisioning_controller.dart';

import 'provisioning_fakes.dart';

Future<ProvisioningController> wiredAp(
  FakeSource source,
  FakeApJoiner joiner,
  FakeApTransport transport,
) async {
  final controller = ProvisioningController(
    environmentProbe: readyProbe(),
    discoverySource: source,
    establishPairing: (_) async {},
    connectChannel: (_, __) async => FakeCtDevice(),
    linkEvents: (_) => const Stream<bool>.empty(),
    apJoiner: joiner,
    apTransportFactory: (_) => transport,
    selfCheckHold: Duration.zero,
  );
  addTearDown(controller.dispose);
  addTearDown(source.close);
  await controller.runSelfCheck();
  await until(() => source.startCount == 1, 'selfcheck did not start scan');
  source.emit(apCandidate());
  await until(
    () => controller.phase == SessionPhase.resultsAvailable,
    'AP candidate did not surface in results',
  );
  return controller;
}

void main() {
  test('AP-only 候选：join 用 SSID（非 candidateId），读到能力，收尾恢复原网', () async {
    final source = FakeSource();
    final joiner = FakeApJoiner();
    final transport = FakeApTransport();
    final controller = await wiredAp(source, joiner, transport);

    await controller.selectCandidate(controller.candidates.first);
    await until(
      () => controller.phase == SessionPhase.choosingSections,
      'softAP chain did not reach capabilities',
    );

    // join 收到的是原始 SSID：legacy 型号段（NE101-P）不能从 modelHint 重建。
    expect(joiner.joins, ['NE101-P_BBC6DC']);
    expect(controller.deviceInfo?.deviceName, 'NE101-P_BBC6DC');
    expect(controller.capabilities?.sections.first.name, 'wifi');
    expect(joiner.restores, isEmpty);

    // 会话收尾（清理钩子）把 radio 还给原网快照。
    await controller.rescan();
    expect(joiner.restores, [
      const WlanRestorePoint(ssid: 'TP-LINK-5G', profileName: 'TP-LINK-5G'),
    ]);
  });

  test('join 失败：connectionError 带稳定原因，且已捕获的快照仍被恢复', () async {
    final source = FakeSource();
    final joiner = FakeApJoiner();
    joiner.joinError = const ApJoinException(kJoinTimeout, 'not associated');
    final transport = FakeApTransport();
    final controller = await wiredAp(source, joiner, transport);

    await controller.selectCandidate(controller.candidates.first);
    await until(
      () => controller.phase == SessionPhase.connectionError,
      'join failure did not surface as connectionError',
    );
    expect(controller.lastProblem?.reason, kJoinTimeout);
    // join 可能已把 radio 挪走：失败释放时同样恢复。
    expect(joiner.restores.length, 1);
    expect(transport.requests, 0);
  });

  test('CT-Disc-only 候选仍是 channel_unsupported（无连接链）', () async {
    final source = FakeSource();
    final joiner = FakeApJoiner();
    final transport = FakeApTransport();
    final controller = await wiredAp(source, joiner, transport);

    // 独立 MAC 后缀：与 AP 候选同后缀会被注册表合并成一行，
    // 合并行（AP+CT-Disc）走的是 softAP 链而非 channel_unsupported。
    final ctdisc = DiscoveryCandidate(
      candidateId: 'ctdisc:CCDDEE@Ethernet',
      macSuffix: 'CCDDEE',
      channels: const {DiscoveryChannel.ctDisc},
      provisionable: true,
      busy: false,
      lastSeen: DateTime.now(),
    );
    source.emit(ctdisc);
    await until(
      () => controller.candidates.any((c) => c.candidateId == ctdisc.candidateId),
      'ctdisc candidate did not merge in',
    );
    await controller.selectCandidate(
      controller.candidates.firstWhere(
        (c) => c.candidateId == ctdisc.candidateId,
      ),
    );
    await until(
      () => controller.phase == SessionPhase.connectionError,
      'ctdisc-only row did not fail',
    );
    expect(controller.lastProblem?.reason, 'channel_unsupported');
    expect(joiner.joins, isEmpty);
  });

  test('配置中设备不可达 → linkLost；重连重新 join 并再恢复原网', () async {
    final source = FakeSource();
    final joiner = FakeApJoiner();
    final transport = FakeApTransport();
    final controller = await wiredAp(source, joiner, transport);

    await controller.selectCandidate(controller.candidates.first);
    await until(
      () => controller.phase == SessionPhase.choosingSections,
      'softAP chain did not reach capabilities',
    );

    // 打开 wifi 模块触发 config.get 预填；传输翻成不可达 → 掉线相位。
    transport.dropped = true;
    await controller.openSection('wifi');
    await until(
      () => controller.phase == SessionPhase.linkLost,
      'ap_unreachable did not map to linkLost',
    );
    // 掉线即释放：radio 已还给原网一次。
    expect(joiner.restores.length, 1);

    // 重连：join 第二次 + 能力重读 + 恢复点再挂枪（会话再收尾仍恢复）。
    // 掉线时 wifi 模块已打开（editingSections 非空），按 v7c 约定
    // 原位恢复回 editingConfig，而非回到模块选择。
    transport.dropped = false;
    await controller.reconnectLink();
    await until(
      () => controller.phase == SessionPhase.editingConfig,
      'reconnect did not restore the session in place',
    );
    expect(joiner.joins, hasLength(2));
    await controller.rescan();
    expect(joiner.restores.length, 2);
  });
}
