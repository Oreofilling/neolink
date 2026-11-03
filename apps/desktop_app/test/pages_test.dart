// M2-4 页面冒烟测试：壳随相位自动切页；候选行忙态禁选；连接失败错误卡
// 返回列表；扫描超时空态页；能力页节列表与勾选。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provisioning_session/provisioning_session.dart';

import 'package:desktop_app/app.dart';
import 'package:desktop_app/provisioning/provisioning_controller.dart';

import 'provisioning_fakes.dart';

ProvisioningController wiredController(
  FakeSource source,
  FakeCtDevice device, {
  Duration scanTimeout = const Duration(seconds: 20),
}) => ProvisioningController(
  environmentProbe: readyProbe(),
  discoverySource: source,
  establishPairing: (_) async {},
  connectChannel: (_, __) async => device,
  scanTimeout: scanTimeout,
);

/// 连续单帧泵：链路环节都是微任务，逐帧推进即可收敛（骨架屏动画禁 settle）。
Future<void> settle(WidgetTester tester, [int frames = 12]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  testWidgets('全链路：自检过 → 候选行 → 连接 → 能力页勾选', (tester) async {
    final source = FakeSource();
    final device = FakeCtDevice();
    final controller = wiredController(source, device);
    addTearDown(source.close);
    addTearDown(device.close);
    addTearDown(controller.dispose);

    await tester.pumpWidget(NeoLinkApp(controller: controller));
    await settle(tester); // 自检放行 → 自动进扫描页

    source.emit(sampleCandidate());
    await settle(tester);
    expect(controller.phase, SessionPhase.resultsAvailable);
    expect(find.text('NE101'), findsOneWidget);
    expect(find.text('连接'), findsOneWidget);

    await tester.tap(find.text('连接'));
    await settle(tester);
    expect(controller.phase, SessionPhase.choosingSections);
    expect(find.text('NE101-AABBCC'), findsOneWidget); // 设备信息卡
    expect(find.text('wifi'), findsOneWidget);
    expect(find.text('cellular'), findsOneWidget);
    expect(find.text('mqtt'), findsOneWidget);
    expect(find.text('从未配置'), findsOneWidget); // 当前网络
    expect(find.text('已连接'), findsOneWidget); // 顶栏徽章

    // 勾选 wifi 节（节顺序与能力响应一致）。
    final boxes = find.byType(Checkbox);
    expect(boxes, findsNWidgets(3));
    await tester.tap(boxes.first);
    await tester.pump();
    expect(tester.widget<Checkbox>(boxes.first).value, isTrue);
  });

  testWidgets('忙候选显示忙徽章且不可选择', (tester) async {
    final source = FakeSource();
    final device = FakeCtDevice();
    final controller = wiredController(source, device);
    addTearDown(source.close);
    addTearDown(device.close);
    addTearDown(controller.dispose);

    await tester.pumpWidget(NeoLinkApp(controller: controller));
    await settle(tester);

    source.emit(sampleCandidate(busy: true));
    await settle(tester);
    expect(controller.phase, SessionPhase.resultsAvailable);
    expect(find.text('忙'), findsOneWidget);

    await tester.tap(find.text('连接'));
    await settle(tester);
    // 忙设备不得进入连接链（§4.2.2）。
    expect(controller.phase, SessionPhase.resultsAvailable);
  });

  testWidgets('连接失败：错误卡展示原因并可返回设备列表', (tester) async {
    final source = FakeSource();
    final controller = ProvisioningController(
      environmentProbe: readyProbe(),
      discoverySource: source,
      establishPairing: (_) async {},
      connectChannel: (_, __) async => throw Exception('gatt link gone'),
    );
    addTearDown(source.close);
    addTearDown(controller.dispose);

    await tester.pumpWidget(NeoLinkApp(controller: controller));
    await settle(tester);

    source.emit(sampleCandidate());
    await settle(tester);
    await tester.tap(find.text('连接'));
    await settle(tester);
    expect(controller.phase, SessionPhase.connectionError);
    expect(find.text('连接未完成'), findsOneWidget);
    expect(find.text('gatt link gone'), findsOneWidget); // 诊断串原样展示

    await tester.tap(find.text('返回设备列表'));
    await settle(tester);
    expect(controller.phase, SessionPhase.resultsAvailable);
    expect(find.text('NE101'), findsOneWidget); // 候选保留可直接重试
  });

  testWidgets('扫描超时进入空态页并可重扫', (tester) async {
    final source = FakeSource();
    final device = FakeCtDevice();
    final controller = wiredController(
      source,
      device,
      scanTimeout: const Duration(milliseconds: 60),
    );
    addTearDown(source.close);
    addTearDown(device.close);
    addTearDown(controller.dispose);

    await tester.pumpWidget(NeoLinkApp(controller: controller));
    await settle(tester); // 进入扫描
    await tester.pump(const Duration(milliseconds: 100)); // 超时触发

    expect(controller.phase, SessionPhase.scanEmpty);
    expect(find.text('未发现设备'), findsWidgets); // 导航 + 页标题
    expect(find.textContaining('附近没有发现可配置设备'), findsOneWidget);

    await tester.tap(find.text('重新扫描'));
    await settle(tester);
    expect(controller.phase, SessionPhase.scanning);
  });
}
