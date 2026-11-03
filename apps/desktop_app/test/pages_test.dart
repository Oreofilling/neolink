// M2-4 页面冒烟测试：壳随相位自动切页；候选行忙态禁选；连接失败错误卡
// 返回列表；扫描超时空态页；能力页节列表与勾选。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:communication_domain/communication_domain.dart';
import 'package:provisioning_session/provisioning_session.dart';

import 'package:desktop_app/app.dart';
import 'package:desktop_app/provisioning/provisioning_controller.dart';
import 'package:desktop_app/services/settings_store.dart';

import 'provisioning_fakes.dart';

ProvisioningController wiredController(
  FakeSource source,
  FakeCtDevice device, {
  Duration scanTimeout = const Duration(seconds: 20),
  Duration selfCheckHold = Duration.zero,
}) => ProvisioningController(
  environmentProbe: readyProbe(),
  discoverySource: source,
  establishPairing: (_) async {},
  connectChannel: (_, __) async => device,
  scanTimeout: scanTimeout,
  selfCheckHold: selfCheckHold,
);

/// 连续单帧泵：链路环节都是微任务，逐帧推进即可收敛（骨架屏动画禁 settle）。
Future<void> settle(WidgetTester tester, [int frames = 12]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// 泵根组件：跟随系统语言默认为中文（testWidgets 默认 en-US，E5 后语言
/// 由平台列表解析），设置存储禁用避免写真实 APPDATA。
Future<void> pumpApp(WidgetTester tester, ProvisioningController controller,
    {SettingsStore? settings}) async {
  tester.platformDispatcher.localesTestValue = const [Locale('zh')];
  await tester.pumpWidget(
    NeoLinkApp(controller: controller, settings: settings ?? SettingsStore.none()),
  );
}

void main() {
  testWidgets('全链路：自检过 → 候选行 → 连接 → 能力页勾选', (tester) async {
    final source = FakeSource();
    final device = FakeCtDevice();
    final controller = wiredController(source, device);
    addTearDown(source.close);
    addTearDown(device.close);
    addTearDown(controller.dispose);

    await pumpApp(tester, controller);
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

    await pumpApp(tester, controller);
    await settle(tester);

    source.emit(sampleCandidate(busy: true));
    await settle(tester);
    expect(controller.phase, SessionPhase.resultsAvailable);
    expect(find.text('忙'), findsOneWidget);

    await tester.tap(find.text('连接'));
    await settle(tester);
    // 忙设备不得进入连接链（§4.2.2）。
    expect(controller.phase, SessionPhase.resultsAvailable);

    // 结果页有 3s 清扫定时器（时效标注重绘）：重扫并泵过窗口收敛回空态。
    await tester.tap(find.text('重新扫描'));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(seconds: 21));
    expect(controller.phase, SessionPhase.scanEmpty);
  });

  testWidgets('连接失败：错误卡展示原因并可返回设备列表', (tester) async {
    final source = FakeSource();
    final controller = ProvisioningController(
      environmentProbe: readyProbe(),
      discoverySource: source,
      establishPairing: (_) async {},
      connectChannel: (_, __) async => throw Exception('gatt link gone'),
      selfCheckHold: Duration.zero,
    );
    addTearDown(source.close);
    addTearDown(controller.dispose);

    await pumpApp(tester, controller);
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

    // 结果页有 3s 清扫定时器（时效标注重绘）：重扫并泵过窗口收敛回空态。
    await tester.tap(find.text('重新扫描'));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(seconds: 21));
    expect(controller.phase, SessionPhase.scanEmpty);
  });

  testWidgets('扫描超时进入空态页并可重扫', (tester) async {
    final source = FakeSource();
    final device = FakeCtDevice();
    // 用默认 20s 扫描窗：泵快进触发超时；重扫后小步泵进，避免窗口再烧穿。
    final controller = wiredController(source, device);
    addTearDown(source.close);
    addTearDown(device.close);
    addTearDown(controller.dispose);

    await pumpApp(tester, controller);
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

  testWidgets('M3 PoE: ethernet readonly row carries the PoE badge', (tester) async {
    final source = FakeSource();
    final device = FakeCtDevice(capsShape: 'ne301', power: const ['poe']);
    final controller = wiredController(source, device);
    addTearDown(source.close);
    addTearDown(device.close);
    addTearDown(controller.dispose);

    await pumpApp(tester, controller);
    await settle(tester);
    source.emit(sampleCandidate());
    await settle(tester);
    await tester.tap(find.text('连接'));
    await settle(tester);
    expect(controller.phase, SessionPhase.choosingSections);
    // §13.3 Ethernet: readonly row plus the PoE power attribute badge.
    expect(find.text('ethernet'), findsOneWidget);
    expect(find.text('PoE 供电'), findsOneWidget);
  });

  testWidgets('M3 full flow: pick sections -> prefilled form -> deliver -> result -> back to scan',
      (tester) async {
    final source = FakeSource();
    final device = FakeCtDevice();
    final controller = wiredController(source, device);
    addTearDown(source.close);
    addTearDown(device.close);
    addTearDown(controller.dispose);

    await pumpApp(tester, controller);
    await settle(tester);
    source.emit(sampleCandidate());
    await settle(tester);
    await tester.tap(find.text('连接'));
    await settle(tester);
    expect(controller.phase, SessionPhase.choosingSections);

    // Check wifi, enter the form.
    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();
    await tester.ensureVisible(find.text('开始配置'));
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

    await pumpApp(tester, controller);
    await settle(tester);
    source.emit(sampleCandidate());
    await settle(tester);
    await tester.tap(find.text('连接'));
    await settle(tester);

    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();
    await tester.ensureVisible(find.text('开始配置'));
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

    await pumpApp(tester, controller);
    await settle(tester);
    source.emit(sampleCandidate());
    await settle(tester);
    await tester.tap(find.text('连接'));
    await settle(tester);

    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();
    await tester.ensureVisible(find.text('开始配置'));
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

  testWidgets('M3b 自检通过倒计时：可停留，停留后立即扫描', (tester) async {
    final source = FakeSource();
    final device = FakeCtDevice();
    final controller = wiredController(source, device,
        selfCheckHold: const Duration(seconds: 5));
    addTearDown(source.close);
    addTearDown(device.close);
    addTearDown(controller.dispose);

    await pumpApp(tester, controller);
    await settle(tester); // 自检完成，倒计时 5（帧步进不触发 1s tick）
    expect(controller.phase, SessionPhase.selfChecking);
    expect(find.text('5 秒后自动进入扫描'), findsOneWidget);
    expect(find.text('停留本页'), findsOneWidget);

    await tester.tap(find.text('停留本页'));
    await settle(tester);
    expect(controller.selfCheckCountdown, isNull);
    expect(controller.selfCheckHeld, isTrue);
    expect(find.textContaining('已停留本页'), findsOneWidget);

    await tester.tap(find.text('立即扫描'));
    await settle(tester);
    expect(controller.phase, SessionPhase.scanning);
    // 泵过扫描窗口收敛回空态，保证收尾无挂起定时器。
    await tester.pump(const Duration(seconds: 21));
    expect(controller.phase, SessionPhase.scanEmpty);
  });

  testWidgets('M3b 断电候选标注「信号消失」而非消失', (tester) async {
    final source = FakeSource();
    final device = FakeCtDevice();
    final controller = wiredController(source, device);
    addTearDown(source.close);
    addTearDown(device.close);
    addTearDown(controller.dispose);

    await pumpApp(tester, controller);
    await settle(tester);
    // lastSeen 回溯 30s（> ttl 12s）：进结果页即为过期条目。
    source.emit(sampleCandidate(
      seen: DateTime.now().subtract(const Duration(seconds: 30)),
    ));
    await settle(tester);
    expect(controller.phase, SessionPhase.resultsAvailable);

    expect(find.text('NE101'), findsOneWidget); // 条目保留
    expect(find.text('信号消失'), findsOneWidget); // 过期徽章
    expect(find.textContaining('最后见到'), findsOneWidget); // 时龄标注
    expect(find.text('连接'), findsOneWidget); // 仍可点（连接由链路报错兜底）

    // 结果页有 3s 清扫定时器（时效标注重绘）：重扫并泵过窗口收敛回空态。
    await tester.tap(find.text('重新扫描'));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(seconds: 21));
    expect(controller.phase, SessionPhase.scanEmpty);
  });

  testWidgets('M3b 语言跟随系统、可切换、重启按存储恢复', (tester) async {
    final source = FakeSource();
    final device = FakeCtDevice();
    final controller = wiredController(source, device);
    addTearDown(source.close);
    addTearDown(device.close);
    addTearDown(controller.dispose);
    final dir = Directory.systemTemp.createTempSync('neolink_settings_test');
    addTearDown(() => dir.deleteSync(recursive: true));

    // 未存储任何设置：跟随系统英文（E5：不再硬编码中文）。
    tester.platformDispatcher.localesTestValue = const [Locale('en')];
    await tester.pumpWidget(
      NeoLinkApp(controller: controller, settings: SettingsStore.none()),
    );
    await settle(tester);
    expect(find.text('Scan devices'), findsWidgets);

    // 顶栏切换 → 界面立即中文（写盘为 fire-and-forget，UI 断言不依赖文件）。
    await tester.tap(find.text('中文'));
    await tester.pump();
    expect(find.text('扫描设备'), findsWidgets);
    expect(find.text('EN'), findsOneWidget); // 有效语言已切到中文

    // 泵过扫描窗口收敛回空态（清理定时器），再验证重启恢复路径。
    await tester.pump(const Duration(seconds: 21));
    expect(controller.phase, SessionPhase.scanEmpty);

    // 重启 = 新 app 实例：预写中文设置（同步写避免竞态）+ 系统英文，
    // 起始语言应为存储的中文（E5 的回归点）。
    File('${dir.path}\\settings.json').writeAsStringSync('{"locale":"zh"}\n');
    await tester.pumpWidget(
      NeoLinkApp(controller: controller, settings: SettingsStore(directory: dir.path)),
    );
    await settle(tester);
    expect(find.text('扫描设备'), findsWidgets);
    expect(find.text('EN'), findsOneWidget); // 存储语言覆盖系统英文
  });
}
