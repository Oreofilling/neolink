// M2-4 页面冒烟测试：壳随相位自动切页；候选行忙态禁选；连接失败错误卡
// 返回列表；扫描超时空态页；能力页节列表与勾选。
library;

import 'dart:async';
import 'dart:io';

import 'package:ble_universal/ble_universal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:communication_domain/communication_domain.dart';
import 'package:provisioning_session/provisioning_session.dart';

import 'package:desktop_app/app.dart';
import 'package:desktop_app/provisioning/provisioning_controller.dart';
import 'package:desktop_app/services/environment_probe.dart';
import 'package:desktop_app/services/settings_store.dart';
import 'package:desktop_app/shell/widgets/scan_radar.dart';

import 'provisioning_fakes.dart';

ProvisioningController wiredController(
  FakeSource source,
  FakeCtDevice device, {
  Duration scanTimeout = const Duration(seconds: 20),
  Duration selfCheckHold = Duration.zero,
  Stream<bool> Function(String deviceId)? linkEvents,
}) => ProvisioningController(
  environmentProbe: readyProbe(),
  discoverySource: source,
  establishPairing: (_) async {},
  connectChannel: (_, __) async => device,
  // Default empty stream: cases not exercising link loss never touch
  // the universal_ble static (no plugin in the test environment).
  linkEvents: linkEvents ?? ((_) => const Stream<bool>.empty()),
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
Future<void> pumpApp(
  WidgetTester tester,
  ProvisioningController controller, {
  SettingsStore? settings,
}) async {
  // v7c: the scan page pins the QR strip at the bottom, so the scroll
  // viewport loses ~68px. Exercise a realistic desktop window (1280x900)
  // instead of the 800x600 default, where the first table row's connect
  // button would otherwise sit below the fold.
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  tester.platformDispatcher.localesTestValue = const [Locale('zh')];
  await tester.pumpWidget(
    NeoLinkApp(
      controller: controller,
      settings: settings ?? SettingsStore.none(),
    ),
  );
}

void main() {
  testWidgets('全链路：自检过 → 候选行 → 连接 → 模块列表进入配置', (tester) async {
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
    // v6: healthy rows fill the status/last-seen cells (idle badge, just now).
    expect(find.text('空闲'), findsOneWidget);
    expect(find.text('刚刚'), findsOneWidget);

    await tester.tap(find.text('连接'));
    await settle(tester);
    expect(controller.phase, SessionPhase.choosingSections);
    expect(find.text('NE101-AABBCC'), findsOneWidget); // 会话上下文条
    expect(find.text('Wi-Fi 联网'), findsOneWidget); // 产品名节标签
    expect(find.text('蜂窝网络 4G'), findsOneWidget);
    expect(find.text('MQTT 数据推送'), findsOneWidget);
    expect(find.text('从未配置'), findsOneWidget); // 右栏当前网络
    expect(find.text('已连接'), findsOneWidget); // 上下文条徽章

    // v7：模块列表即入口，点 Wi-Fi 行直接进入该模块表单。
    await tester.tap(find.text('Wi-Fi 联网'));
    await settle(tester);
    expect(controller.phase, SessionPhase.editingConfig);
    expect(controller.editingSections, ['wifi']);
    expect(find.text('返回模块选择'), findsOneWidget); // 模块页返回链接
    expect(find.text('未填'), findsNothing); // 模块页没有列表行徽章
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
    // 扫描中（尚无候选）底部也常驻「扫码添加」入口，不必等窗口烧穿。
    expect(find.text('未发现您的设备？'), findsOneWidget);
    await tester.pump(const Duration(seconds: 21)); // 超时触发

    expect(controller.phase, SessionPhase.scanEmpty);
    expect(find.text('未发现您的设备'), findsOneWidget); // 空态页标题
    expect(find.textContaining('附近没有发现可配置设备'), findsOneWidget);

    await tester.tap(find.text('重新扫描'));
    await tester.pump(const Duration(milliseconds: 16)); // 微任务收敛即扫描中
    expect(controller.phase, SessionPhase.scanning);

    // 无候选则二次超时仍收敛回空态（也保证测试收尾无挂起定时器）。
    await tester.pump(const Duration(seconds: 21));
    expect(controller.phase, SessionPhase.scanEmpty);
  });

  testWidgets('空态提示进扫码指引：指引保持打开且后台持续重开扫描', (tester) async {
    final source = FakeSource();
    final device = FakeCtDevice();
    final controller = wiredController(source, device);
    addTearDown(source.close);
    addTearDown(device.close);

    await pumpApp(tester, controller);
    await settle(tester);
    await tester.pump(
      const Duration(seconds: 21),
    ); // window burns out -> empty hint
    expect(controller.phase, SessionPhase.scanEmpty);
    // v7c: empty result stays on this page — inline no-devices hint,
    // QR entry at the bottom.
    expect(find.text('未发现您的设备'), findsOneWidget);
    expect(find.textContaining('附近没有发现可配置设备'), findsOneWidget);

    await tester.tap(find.text('扫码添加'));
    await settle(tester); // post-frame 重扫：scanEmpty → cleaning → scanning
    expect(controller.phase, SessionPhase.scanning);
    // 回归：cleaning 相位不得把指引弹回（此前一帧闪退，点击看似无反应）。
    expect(find.text('唤醒设备'), findsNWidgets(2)); // 步骤头 + 卡片标题

    // 指引打开期间窗口再次烧穿 → 自动重开扫描（设备唤醒晚也不悬停）。
    await tester.pump(const Duration(seconds: 21));
    await settle(tester, 2);
    expect(controller.phase, SessionPhase.scanning);
    expect(find.text('唤醒设备'), findsNWidgets(2)); // 步骤头 + 卡片标题

    // 结束在 scanning：扫描/清扫定时器仍挂着，测试体内同步 dispose。
    controller.dispose();
  });

  testWidgets('M3 PoE: ethernet readonly row carries the PoE badge', (
    tester,
  ) async {
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
    expect(find.text('以太网'), findsOneWidget); // 产品名节标签
    expect(find.text('PoE 供电'), findsOneWidget);
  });

  testWidgets(
    'M3 full flow: pick sections -> prefilled form -> deliver -> result -> back to scan',
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

      // v7: open the wifi module directly from the list.
      await tester.tap(find.text('Wi-Fi 联网'));
      await settle(tester);
      expect(controller.phase, SessionPhase.editingConfig);

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
      expect(find.text('已保存 1 项配置'), findsOneWidget);
      expect(find.text('Wi-Fi 联网'), findsOneWidget);
      expect(find.text('配置将在网络重连后生效'), findsOneWidget);

      await tester.tap(find.text('完成并返回扫描'));
      await settle(tester);
      expect(controller.phase, SessionPhase.scanning);
      // Pump past the scan window to converge back to empty (also guarantees
      // no pending timers at teardown).
      await tester.pump(const Duration(seconds: 21));
      expect(controller.phase, SessionPhase.scanEmpty);
    },
  );

  testWidgets(
    'v7 round: back keeps drafts, second module joins in capability order',
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

      // Open wifi, type a password — the entry must survive every move.
      await tester.tap(find.text('Wi-Fi 联网'));
      await settle(tester);
      expect(controller.phase, SessionPhase.editingConfig);
      await tester.enterText(find.byType(TextField).at(1), 'keep-me');

      // Back to the module list: wifi row shows progress, others stay empty.
      await tester.tap(find.text('返回模块选择'));
      await settle(tester);
      // Prefilled ssid + typed password both count as content.
      expect(find.text('已填 2 项'), findsOneWidget);
      expect(find.text('未填'), findsNWidgets(2)); // cellular + mqtt
      // The side rail answers "what ships": one module opened so far.
      expect(find.text('1 项待下发'), findsOneWidget);

      // Open cellular: the round grows in capability order (wifi first).
      await tester.tap(find.text('蜂窝网络 4G'));
      await settle(tester);
      expect(controller.editingSections, ['wifi', 'cellular']);
      expect((controller.drafts['wifi'] as WifiSection).password, 'keep-me');
      expect(find.text('返回模块选择'), findsOneWidget);
      expect(find.text('2 项待下发'), findsOneWidget);
    },
  );

  testWidgets(
    'M3 rejection: banner shows the code, back-to-edit keeps values',
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

      // v7: open the wifi module directly from the list.
      await tester.tap(find.text('Wi-Fi 联网'));
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

      // The earlier ensureVisible(下发配置) scroll leaves the banner above the
      // fold — scroll back to it before tapping.
      await tester.ensureVisible(find.text('返回编辑'));
      await tester.pump();
      await tester.tap(find.text('返回编辑'));
      await settle(tester);
      expect(controller.phase, SessionPhase.editingConfig);
      // Entries preserved: prefilled ssid + typed password still in the draft.
      final wifi = controller.drafts['wifi'] as WifiSection;
      expect(wifi.ssid, 'Office-2.4G');
      expect(wifi.password, 'example-password');
    },
  );

  testWidgets('M3 network scan: list pick fills ssid, cursor loads page 2', (
    tester,
  ) async {
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

    // v7: open the wifi module directly from the list.
    await tester.tap(find.text('Wi-Fi 联网'));
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
    await tester.ensureVisible(find.text('CT-HaLow'));
    await tester.pump();
    await tester.tap(find.text('CT-HaLow'));
    await settle(tester);
    expect((controller.drafts['wifi'] as WifiSection).ssid, 'CT-HaLow');
  });

  testWidgets('M3b countdown: prominent digits, stay, then scan now', (
    tester,
  ) async {
    final source = FakeSource();
    final device = FakeCtDevice();
    final controller = wiredController(
      source,
      device,
      selfCheckHold: const Duration(seconds: 5),
    );
    addTearDown(source.close);
    addTearDown(device.close);
    addTearDown(controller.dispose);

    await pumpApp(tester, controller);
    await settle(tester); // Report landed; the v6 walk sits on the first row.
    expect(controller.phase, SessionPhase.selfChecking);
    // v6 walk: first row mid-check (spinner + checking), later rows queued.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('等待检测'), findsNWidgets(2));
    expect(find.text('点击页面任意位置可停止自动进入'), findsOneWidget);

    // Walk ticks (600ms/row) land for all three channels, then the countdown
    // arms — the digit is the proof the walk finished first.
    await tester.pump(const Duration(seconds: 2));
    // Round-2 A1: big countdown digits plus the suffix hint — unmissable.
    expect(find.text('5'), findsOneWidget);
    expect(find.text('秒后自动进入扫描'), findsOneWidget);
    // v6: the stay button is gone — any click on the page holds it instead.
    expect(find.text('停留本页'), findsNothing);

    await tester.tap(find.text('环境自检')); // tap-to-stay on the page body
    await settle(tester);
    expect(controller.selfCheckCountdown, isNull);
    expect(controller.selfCheckHeld, isTrue);
    expect(find.textContaining('已停留本页'), findsOneWidget);

    await tester.ensureVisible(find.text('立即进入扫描'));
    await tester.pump();
    await tester.tap(find.text('立即进入扫描'));
    await settle(tester);
    expect(controller.phase, SessionPhase.scanning);
    // 泵过扫描窗口收敛回空态，保证收尾无挂起定时器。
    await tester.pump(const Duration(seconds: 21));
    expect(controller.phase, SessionPhase.scanEmpty);
  });

  testWidgets('v6 icon pass: topbar toggles and page decorations carry icons', (
    tester,
  ) async {
    final source = FakeSource();
    final device = FakeCtDevice();
    final controller = wiredController(source, device);
    addTearDown(source.close);
    addTearDown(device.close);
    addTearDown(controller.dispose);

    await pumpApp(tester, controller);
    await settle(tester); // Self-check passed -> scanning page.

    // Topbar right corner: language and theme toggle icons beside badges.
    expect(find.byIcon(Icons.translate), findsOneWidget);
    // v7c: the chip states the CURRENT theme — light UI carries the sun.
    expect(find.byIcon(Icons.light_mode_outlined), findsOneWidget);
    // Scan page: leading title icon and the radar loading panel (no
    // skeleton rows left).
    expect(find.byIcon(Icons.radar_outlined), findsWidgets);
    expect(find.byType(ScanRadar), findsOneWidget);

    // Pump past the scan window so no timer dangles at teardown.
    await tester.pump(const Duration(seconds: 21));
    expect(controller.phase, SessionPhase.scanEmpty);
  });

  testWidgets('M3b A2: history page stays put mid-scan (refresh immunity)', (
    tester,
  ) async {
    final source = FakeSource();
    final device = FakeCtDevice();
    final controller = wiredController(source, device);
    addTearDown(source.close);
    addTearDown(device.close);
    addTearDown(controller.dispose);

    await pumpApp(tester, controller);
    await settle(tester); // Self-check passed -> scanning.

    // Hop to the history page from the sidebar.
    await tester.tap(find.text('历史会话'));
    await settle(tester);
    expect(find.textContaining('暂无记录'), findsOneWidget);

    // Pump past the whole scan window: the phase migrates scanning ->
    // scanEmpty, but the shell must keep the manual page selection.
    await tester.pump(const Duration(seconds: 21));
    expect(controller.phase, SessionPhase.scanEmpty);
    expect(find.textContaining('暂无记录'), findsOneWidget); // still history

    // Back to the scan destination: the empty page shows up.
    await tester.tap(find.text('扫描设备'));
    await settle(tester);
    expect(find.text('未发现您的设备'), findsOneWidget);
  });

  testWidgets('M3d recheck feedback: running label, then last-checked stamp', (
    tester,
  ) async {
    final source = FakeSource();
    final device = FakeCtDevice();
    // Gated probe: the BLE leg resolves only when the test completes it,
    // so the in-flight window is observable.
    var gate = Completer<CtEnvironmentReport>();
    CtEnvironmentReport readyReport() => const CtEnvironmentReport(
      readiness: CtBleReadiness.ready,
      detail: 'radio on',
    );
    final controller = ProvisioningController(
      environmentProbe: DesktopEnvironmentProbe(
        probeBle: () => gate.future,
        enumerateAdapters: () async => '[{"Name":"Wi-Fi","Status":"Up","PhysicalMediaType":"Native 802.11"}]',
      ),
      discoverySource: source,
      establishPairing: (_) async {},
      connectChannel: (_, __) async => device,
      selfCheckHold: const Duration(seconds: 5),
    );
    addTearDown(source.close);
    addTearDown(device.close);
    addTearDown(controller.dispose);

    await pumpApp(tester, controller);
    await tester.pump(); // post-frame runSelfCheck fired; gate still pending
    expect(find.text('正在检测环境…'), findsOneWidget); // in-flight label
    expect(controller.selfCheckAt, isNull);

    gate.complete(readyReport());
    await settle(tester); // report landed; v6 walk on the first row
    expect(find.text('等待检测'), findsNWidgets(2));
    await tester.pump(
      const Duration(seconds: 2),
    ); // walk plays out -> countdown
    expect(find.text('5'), findsOneWidget);
    expect(find.textContaining('上次检测'), findsOneWidget); // stamp proves it ran

    // Re-check: countdown cancelled, running label back, then a fresh stamp.
    final firstAt = controller.selfCheckAt;
    gate = Completer<CtEnvironmentReport>();
    // v6: re-check is the refresh icon pinned to the card's top-right.
    await tester.tap(find.byIcon(Icons.refresh));
    await settle(tester);
    expect(find.text('正在检测环境…'), findsOneWidget);
    expect(controller.selfCheckCountdown, isNull);
    gate.complete(readyReport());
    await settle(tester);
    await tester.pump(const Duration(seconds: 2)); // walk replays -> countdown
    expect(identical(controller.selfCheckAt, firstAt), isFalse);
    expect(find.text('5'), findsOneWidget); // countdown restarted

    // Converge: enter the scan, pump past the window (no pending timers).
    await tester.ensureVisible(find.text('立即进入扫描'));
    await tester.pump();
    await tester.tap(find.text('立即进入扫描'));
    await settle(tester);
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
    source.emit(
      sampleCandidate(
        seen: DateTime.now().subtract(const Duration(seconds: 30)),
      ),
    );
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
    expect(
      find.text('EN'),
      findsOneWidget,
    ); // v6: toggle states the CURRENT language

    // 顶栏切换 → 界面立即中文（写盘为 fire-and-forget，UI 断言不依赖文件）。
    await tester.tap(find.text('EN'));
    await tester.pump();
    expect(find.text('扫描设备'), findsWidgets);
    expect(find.text('中文'), findsOneWidget); // 有效语言已切到中文

    // 泵过扫描窗口收敛回空态（清理定时器），再验证重启恢复路径。
    await tester.pump(const Duration(seconds: 21));
    expect(controller.phase, SessionPhase.scanEmpty);

    // 重启 = 新 app 实例：预写中文设置（同步写避免竞态）+ 系统英文，
    // 起始语言应为存储的中文（E5 的回归点）。
    File('${dir.path}\\settings.json').writeAsStringSync('{"locale":"zh"}\n');
    await tester.pumpWidget(
      NeoLinkApp(
        controller: controller,
        settings: SettingsStore(directory: dir.path),
      ),
    );
    await settle(tester);
    expect(find.text('扫描设备'), findsWidgets);
    expect(find.text('中文'), findsOneWidget); // 存储语言覆盖系统英文
  });

  testWidgets('v7c 断连弹窗：草稿保留，重连原位恢复，返回列表回扫描', (tester) async {
    final source = FakeSource();
    final device = FakeCtDevice();
    final link = StreamController<bool>.broadcast();
    final controller = wiredController(
      source,
      device,
      linkEvents: (_) => link.stream,
    );
    addTearDown(source.close);
    addTearDown(device.close);
    addTearDown(link.close);
    addTearDown(controller.dispose);

    await pumpApp(tester, controller);
    await settle(tester);
    source.emit(sampleCandidate());
    await settle(tester);
    await tester.tap(find.text('连接'));
    await settle(tester);
    await tester.tap(find.text('Wi-Fi 联网'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).at(0), 'Home-2.4G');
    await settle(tester, 2);
    expect(controller.phase, SessionPhase.editingConfig);

    // Link drops -> the modal sits over the frozen form (drafts kept).
    link.add(false);
    await settle(tester, 2);
    expect(controller.phase, SessionPhase.linkLost);
    expect(find.text('连接已断开'), findsOneWidget);
    expect(find.textContaining('配置内容全部保留'), findsOneWidget);
    expect(find.text('重新连接'), findsOneWidget);
    expect(find.text('返回设备列表'), findsOneWidget);

    // Reconnect succeeds -> modal gone, form back in place, values kept.
    await tester.tap(find.text('重新连接'));
    await settle(tester);
    expect(controller.phase, SessionPhase.editingConfig);
    expect(find.text('连接已断开'), findsNothing);
    expect(find.text('Home-2.4G'), findsWidgets);

    // Drop again -> back to the device list -> scanning, round cleared.
    link.add(false);
    await settle(tester, 2);
    expect(controller.phase, SessionPhase.linkLost);
    await tester.tap(find.text('返回设备列表'));
    await settle(tester);
    expect(controller.phase, SessionPhase.scanning);
    expect(controller.editingSections, isEmpty);
    expect(controller.drafts, isEmpty);
    // Pump past the scan window to settle on empty; no dangling timers.
    await tester.pump(const Duration(seconds: 21));
    expect(controller.phase, SessionPhase.scanEmpty);
  });
}
