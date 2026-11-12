// M5 softAP 连接链控制器测试：AP-only 候选经 join → HTTP 传输 → 能力读取
// 全链；join 失败映射 connectionError 并恢复原 Wi-Fi；配置中掉线
// （ap_unreachable）走 linkLost，重连重新 join 并恢复原网。
// web 模式：join 成功即开默认浏览器并持有链路，不发 CT-Prov 会话。
library;

import 'package:ap_discovery_adapter/ap_discovery_adapter.dart';
import 'package:discovery_domain/discovery_domain.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provisioning_session/provisioning_session.dart';

import 'package:desktop_app/provisioning/provisioning_controller.dart';
import 'package:desktop_app/services/device_web_opener.dart';

import 'provisioning_fakes.dart';

Future<ProvisioningController> wiredAp(
  FakeSource source,
  FakeApJoiner joiner,
  FakeApTransport transport, {
  DeviceWebOpener? webPageOpener,
}) async {
  final controller = ProvisioningController(
    environmentProbe: readyProbe(),
    discoverySource: source,
    establishPairing: (_) async {},
    connectChannel: (_, __) async => FakeCtDevice(),
    linkEvents: (_) => const Stream<bool>.empty(),
    apJoiner: joiner,
    apTransportFactory: (_) => transport,
    webPageOpener: webPageOpener,
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

  group('web 模式：join 后直接打开设备网页并持有链路', () {
    test('join 成功 → 开浏览器 → webBrowsing；无 CT-Prov 请求；断开才恢复原网', () async {
      final source = FakeSource();
      final joiner = FakeApJoiner();
      final transport = FakeApTransport();
      final openedUrls = <Uri>[];
      final controller = await wiredAp(
        source,
        joiner,
        transport,
        webPageOpener: (url) async {
          openedUrls.add(url);
          return true;
        },
      );

      await controller.selectCandidate(controller.candidates.first,
          viaWeb: true);
      await until(
        () => controller.phase == SessionPhase.webBrowsing,
        'web mode did not reach webBrowsing',
      );

      // NE101 默认网关根路径；未建立 CT-Prov 会话，链路仍被持有。
      expect(openedUrls, [Uri.parse('http://192.168.1.1/')]);
      expect(controller.webPageOpened, isTrue);
      expect(transport.requests, 0);
      expect(joiner.restores, isEmpty);

      // 用户结束浏览：释放链路（恢复原网）并回到扫描循环。
      await controller.finishWebBrowsing();
      await until(
        () => controller.phase == SessionPhase.scanning,
        'finishWebBrowsing did not return to scanning',
      );
      expect(joiner.restores, hasLength(1));
      expect(transport.requests, 0);
    });

    test('NE301 行：网页地址按型号解析为 192.168.10.10', () async {
      final source = FakeSource();
      final joiner = FakeApJoiner();
      final transport = FakeApTransport();
      final openedUrls = <Uri>[];
      final controller = await wiredAp(
        source,
        joiner,
        transport,
        webPageOpener: (url) async {
          openedUrls.add(url);
          return true;
        },
      );

      final ne301 = DiscoveryCandidate(
        candidateId: 'ap:NE301_20007F',
        macSuffix: '20007F',
        modelHint: 'NE301',
        channels: const {DiscoveryChannel.accessPoint},
        provisionable: true,
        busy: false,
        lastSeen: DateTime.now(),
      );
      source.emit(ne301);
      await until(
        () => controller.candidates.any((c) => c.candidateId == ne301.candidateId),
        'NE301 candidate did not surface',
      );
      await controller.selectCandidate(
        controller.candidates
            .firstWhere((c) => c.candidateId == ne301.candidateId),
        viaWeb: true,
      );
      await until(
        () => controller.phase == SessionPhase.webBrowsing,
        'web mode did not reach webBrowsing',
      );
      expect(openedUrls, [Uri.parse('http://192.168.10.10/')]);
      expect(joiner.gatewayHosts, ['192.168.10.10']);
    });

    test('浏览器启动失败 → webBrowsing 保持，重新打开翻正', () async {
      final source = FakeSource();
      final joiner = FakeApJoiner();
      final transport = FakeApTransport();
      var openResult = false;
      final openedUrls = <Uri>[];
      final controller = await wiredAp(
        source,
        joiner,
        transport,
        webPageOpener: (url) async {
          openedUrls.add(url);
          return openResult;
        },
      );

      await controller.selectCandidate(controller.candidates.first,
          viaWeb: true);
      await until(
        () => controller.phase == SessionPhase.webBrowsing,
        'web mode did not reach webBrowsing',
      );
      expect(controller.webPageOpened, isFalse); // 面板显示失败注记 + 重开
      expect(joiner.restores, isEmpty); // 启动失败不释放链路

      openResult = true;
      await controller.reopenWebPage();
      expect(controller.webPageOpened, isTrue);
      expect(openedUrls, hasLength(2));
    });

    test('join 失败后重试保持 web 模式', () async {
      final source = FakeSource();
      final joiner = FakeApJoiner();
      joiner.joinError = const ApJoinException(kJoinTimeout, 'not associated');
      final transport = FakeApTransport();
      final openedUrls = <Uri>[];
      final controller = await wiredAp(
        source,
        joiner,
        transport,
        webPageOpener: (url) async {
          openedUrls.add(url);
          return true;
        },
      );

      await controller.selectCandidate(controller.candidates.first,
          viaWeb: true);
      await until(
        () => controller.phase == SessionPhase.connectionError,
        'join failure did not surface',
      );
      expect(openedUrls, isEmpty);

      joiner.joinError = null;
      await controller.retryConnect();
      await until(
        () => controller.phase == SessionPhase.webBrowsing,
        'retry did not keep web mode',
      );
      expect(openedUrls, [Uri.parse('http://192.168.1.1/')]);
    });
  });
}
