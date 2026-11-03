// M2-4 页面冒烟测试：壳随相位自动切页；候选行忙态禁选；连接失败错误卡
// 返回列表；扫描超时空态页；能力页节列表与勾选。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:communication_domain/communication_domain.dart';
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
    expect(
      find.textContaining('gatt link gone'),
      findsOneWidget,
    ); // 诊断串原样展示（含异常前缀）

    await tester.tap(find.text('返回设备列表'));
    await settle(tester);
    expect(controller.phase, SessionPhase.resultsAvailable);
    expect(find.text('NE101'), findsOneWidget); // 候选保留可直接重试
  });

  testWidgets('扫描超时进入空态页并可重扫', (tester) async {
    final source = FakeSource();
    final device = FakeCtDevice();
    // 用默认 20s 扫描窗：泵快进触发超时；重扫后小步泵进，避免窗口再烧穿。
    final controller = wiredController(source, device);
    addTearDown(source.close);
    addTearDown(device.close);
    addTearDown(controller.dispose);

    await tester.pumpWidget(NeoLinkApp(controller: controller));
    await settle(tester); // 进入扫描
    await tester.pump(const Duration(seconds: 21)); // 超时触发

    expect(controller.phase, SessionPhase.scanEmpty);
    expect(find.text('未发现设备'), findsWidgets); // 导航 + 页标题
    expect(find.textContaining('附近没有发现可配置设备'), findsOneWidget);

    await tester.tap(find.text('重新扫描'));
    await tester.pump(const Duration(milliseconds: 16)); // 微任务收敛即扫描中
    expect(controller.phase, SessionPhase.scanning);

    // 无候选则二次超时仍收敛回空态（也保证测试收尾无挂起定时器）。
    await tester.pump(const Duration(seconds: 21));
    expect(controller.phase, SessionPhase.scanEmpty);
  });

  testWidgets('M3 full flow: pick sections -> prefilled form -> deliver -> result -> back to scan',
      (tester) async {
    final source = FakeSource();
    final device = FakeCtDevice();
    final controller = wiredController(source, device);
    addTearDown(source.close);
    addTearDown(device.close);
    addTearDown(controller.dispose);

    await tester.pumpWidget(NeoLinkApp(controller: controller));
    await settle(tester);
    source.emit(sampleCandidate());
    await settle(tester);
    await tester.tap(find.text('连接'));
    await settle(tester);
    expect(controller.phase, SessionPhase.choosingSections);

    // Check wifi, enter the form.
    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();
    await tester.tap(find.text('开始配置'));
    await settle(tester);
    expect(controller.phase, SessionPhase.editingConfig);
    expect(find.text('下发确认'), findsWidgets); // page title + sidebar

    // config.get prefill: ssid filled, masked password left empty (an open
    // network is legal).
    expect((controller.drafts['wifi'] as WifiSection).ssid, 'Office-2.4G');

    // Type a password, submit.
    await tester.enterText(find.byType(TextField).at(1), 'example-password');
    await tester.pump();
    await tester.ensureVisible(find.text('下发配置'));
    await tester.pump();
    await tester.tap(find.text('下发配置'));
    await settle(tester);

    // Result page: stored list + apply hint + finish back to scan loop.
    expect(controller.phase, SessionPhase.completed);
    expect(find.text('已写入 1 个配置节'), findsOneWidget);
    expect(find.text('wifi'), findsOneWidget);
    expect(find.text('配置将在网络重连后生效'), findsOneWidget);

    await tester.tap(find.text('完成'));
    await settle(tester);
    expect(controller.phase, SessionPhase.scanning);
    // Pump past the scan window to converge back to empty (also guarantees
    // no pending timers at teardown).
    await tester.pump(const Duration(seconds: 21));
    expect(controller.phase, SessionPhase.scanEmpty);
  });

  testWidgets('M3 rejection: banner shows the code, back-to-edit keeps values',
      (tester) async {
    final source = FakeSource();
    final device = FakeCtDevice(rejectConfigSet: 'FIELD_NOT_SUPPORTED');
    final controller = wiredController(source, device);
    addTearDown(source.close);
    addTearDown(device.close);
    addTearDown(controller.dispose);

    await tester.pumpWidget(NeoLinkApp(controller: controller));
    await settle(tester);
    source.emit(sampleCandidate());
    await settle(tester);
    await tester.tap(find.text('连接'));
    await settle(tester);

    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();
    await tester.tap(find.text('开始配置'));
    await settle(tester);

    await tester.enterText(find.byType(TextField).at(1), 'example-password');
    await tester.pump();
    await tester.ensureVisible(find.text('下发配置'));
    await tester.pump();
    await tester.tap(find.text('下发配置'));
    await settle(tester);

    expect(controller.phase, SessionPhase.operationError);
    expect(find.text('下发被拒，已保留所填内容'), findsOneWidget);
    expect(find.textContaining('FIELD_NOT_SUPPORTED'), findsOneWidget);

    await tester.tap(find.text('返回编辑'));
    await settle(tester);
    expect(controller.phase, SessionPhase.editingConfig);
    // Entries preserved: prefilled ssid + typed password still in the draft.
    final wifi = controller.drafts['wifi'] as WifiSection;
    expect(wifi.ssid, 'Office-2.4G');
    expect(wifi.password, 'example-password');
  });

  testWidgets('M3 network scan: list pick fills ssid, cursor loads page 2',
      (tester) async {
    final source = FakeSource();
    final device = FakeCtDevice();
    final controller = wiredController(source, device);
    addTearDown(source.close);
    addTearDown(device.close);
    addTearDown(controller.dispose);

    await tester.pumpWidget(NeoLinkApp(controller: controller));
    await settle(tester);
    source.emit(sampleCandidate());
    await settle(tester);
    await tester.tap(find.text('连接'));
    await settle(tester);

    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();
    await tester.tap(find.text('开始配置'));
    await settle(tester);

    await tester.ensureVisible(find.text('扫描网络'));
    await tester.pump();
    await tester.tap(find.text('扫描网络'));
    await settle(tester);
    expect(controller.scanItems, hasLength(2)); // Office-2.4G + CT-HaLow

    // Cursor paging: page-2 entry appears.
    await tester.ensureVisible(find.text('加载更多'));
    await tester.pump();
    await tester.tap(find.text('加载更多'));
    await settle(tester);
    expect(controller.scanItems, hasLength(3));

    // Picking a tile writes the ssid draft.
    await tester.tap(find.text('CT-HaLow'));
    await settle(tester);
    expect((controller.drafts['wifi'] as WifiSection).ssid, 'CT-HaLow');
  });
}
