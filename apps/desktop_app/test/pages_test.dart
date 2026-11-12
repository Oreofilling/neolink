// M2-4 页面冒烟测试：壳随相位自动切页；候选行忙态禁选；连接失败错误卡
// 返回列表；扫描超时空态页；能力页节列表与勾选。
library;

import 'dart:async';
import 'dart:io';

import 'package:ap_discovery_adapter/ap_discovery_adapter.dart';
import 'package:ble_universal/ble_universal.dart';
import 'package:ct_disc_adapter/ct_disc_adapter.dart';
import 'package:ct_prov_core/ct_prov_core.dart' show ProvTransport;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:communication_domain/communication_domain.dart';
import 'package:neolink_ui/neolink_ui.dart';
import 'package:provisioning_session/provisioning_session.dart';

import 'package:desktop_app/app.dart';
import 'package:desktop_app/provisioning/provisioning_controller.dart';
import 'package:desktop_app/services/device_web_opener.dart';
import 'package:desktop_app/services/environment_probe.dart';
import 'package:desktop_app/services/settings_store.dart';
import 'package:desktop_app/services/wifi_settings_opener.dart';
import 'package:desktop_app/shell/widgets/scan_radar.dart';

import 'provisioning_fakes.dart';

ProvisioningController wiredController(
  FakeSource source,
  FakeCtDevice device, {
  Duration scanTimeout = const Duration(seconds: 20),
  Duration selfCheckHold = Duration.zero,
  Stream<bool> Function(String deviceId)? linkEvents,
  ApJoiner? apJoiner,
  ProvTransport Function(Uri endpoint)? apTransportFactory,
  DeviceWebOpener? webPageOpener,
}) => ProvisioningController(
  environmentProbe: readyProbe(),
  discoverySource: source,
  establishPairing: (_) async {},
  connectChannel: (_, __) async => device,
  // Default empty stream: cases not exercising link loss never touch
  // the universal_ble static (no plugin in the test environment).
  linkEvents: linkEvents ?? ((_) => const Stream<bool>.empty()),
  apJoiner: apJoiner,
  apTransportFactory: apTransportFactory,
  webPageOpener: webPageOpener,
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
  WifiSettingsOpener? wifiSettingsOpener,
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
      wifiSettingsOpener: wifiSettingsOpener,
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

  testWidgets('AP 行 web 模式：弹窗选「打开网页配置」→ 浏览器打开 → 保持面板 → 断开恢复', (tester) async {
    final source = FakeSource();
    final device = FakeCtDevice();
    final joiner = FakeApJoiner();
    final transport = FakeApTransport();
    final openedUrls = <Uri>[];
    final controller = wiredController(
      source,
      device,
      apJoiner: joiner,
      apTransportFactory: (_) => transport,
      webPageOpener: (url) async {
        openedUrls.add(url);
        return true;
      },
    );
    addTearDown(source.close);
    addTearDown(device.close);
    addTearDown(controller.dispose);

    await pumpApp(tester, controller);
    await settle(tester);

    source.emit(
      sampleCandidate(candidateId: 'ap:NE101-P_BBC6DC')
          .copyWith(channels: const {DiscoveryChannel.accessPoint}),
    );
    await settle(tester);
    expect(controller.phase, SessionPhase.resultsAvailable);

    // AP 行连接先弹断网提示：三个选择，默认主按钮是打开网页配置。
    await tester.tap(find.text('连接'));
    await settle(tester);
    expect(find.text('应用内配置'), findsOneWidget);
    expect(find.text('打开网页配置'), findsOneWidget);

    await tester.tap(find.text('打开网页配置'));
    await settle(tester);
    expect(controller.phase, SessionPhase.webBrowsing);
    expect(openedUrls, [Uri.parse('http://192.168.1.1/')]);

    // 连接页换成 web 保持面板：URL 可见 + 断开按钮。
    expect(find.text('设备网页已打开'), findsOneWidget);
    expect(find.text('http://192.168.1.1/'), findsOneWidget);
    expect(find.text('断开并恢复 Wi-Fi'), findsOneWidget);

    // 断开：恢复原网并回扫描循环，泵过扫描窗口收敛回空态（清扫定时器）。
    await tester.tap(find.text('断开并恢复 Wi-Fi'));
    await settle(tester);
    expect(controller.phase, SessionPhase.scanning);
    expect(joiner.restores, hasLength(1));
    await tester.pump(const Duration(seconds: 21));
    expect(controller.phase, SessionPhase.scanEmpty);
  });

  testWidgets('AP 行弹窗选「应用内配置」仍走 CT-Prov 链（回归）', (tester) async {
    final source = FakeSource();
    final device = FakeCtDevice();
    final joiner = FakeApJoiner();
    final transport = FakeApTransport();
    final controller = wiredController(
      source,
      device,
      apJoiner: joiner,
      apTransportFactory: (_) => transport,
      webPageOpener: (_) async => true,
    );
    addTearDown(source.close);
    addTearDown(device.close);
    addTearDown(controller.dispose);

    await pumpApp(tester, controller);
    await settle(tester);

    source.emit(
      sampleCandidate(candidateId: 'ap:NE101-P_BBC6DC')
          .copyWith(channels: const {DiscoveryChannel.accessPoint}),
    );
    await settle(tester);

    await tester.tap(find.text('连接'));
    await settle(tester);
    await tester.tap(find.text('应用内配置'));
    await settle(tester);

    // 不开网页，正常读到能力进入模块列表。
    expect(controller.phase, SessionPhase.choosingSections);
    expect(controller.webPageUrl, isNull);
    // 模块页打开结束（无悬挂扫描窗口）。
    await tester.tap(find.text('Wi-Fi 联网'));
    await settle(tester);
    expect(controller.phase, SessionPhase.editingConfig);
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

  testWidgets('CT-Disc-only 候选显示通道与暂不支持连接（M5）', (tester) async {
    final source = FakeSource();
    final device = FakeCtDevice();
    final controller = wiredController(source, device);
    addTearDown(source.close);
    addTearDown(device.close);
    addTearDown(controller.dispose);

    await pumpApp(tester, controller);
    await settle(tester);

    // AP-only 行已可连接（softAP 连接链，见断网提示用例）；暂不支持
    // 归属于 CT-Disc-only 行——NE301 Web API 传输面尚未落地。
    source.emit(
      sampleCandidate(
        candidateId: 'ctdisc:BBC6DC@Ethernet',
        modelHint: 'NE301',
      ).copyWith(channels: const {DiscoveryChannel.ctDisc}),
    );
    await settle(tester);
    expect(controller.phase, SessionPhase.resultsAvailable);
    // Row present with the CT-Disc channel chip, but no connect offer.
    expect(find.text('NE301'), findsOneWidget);
    expect(find.text('CT-Disc'), findsWidgets);
    expect(find.text('暂不支持连接'), findsOneWidget);
    expect(find.text('连接'), findsNothing);

    // 结果页保持 3s 清扫定时器（同忙候选用例）：重扫清空注册表后
    // 泵过扫描窗口收敛回空态，无悬挂定时器。
    await tester.tap(find.text('重新扫描'));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(seconds: 21));
    expect(controller.phase, SessionPhase.scanEmpty);
  });

  testWidgets('M5 结果表表头过滤：设备栏选型号、通道栏选通道、全部恢复', (tester) async {
    final source = FakeSource();
    final device = FakeCtDevice();
    final controller = wiredController(source, device);
    addTearDown(source.close);
    addTearDown(device.close);
    addTearDown(controller.dispose);

    await pumpApp(tester, controller);
    await settle(tester);

    source.emit(sampleCandidate(candidateId: 'ble:1', macSuffix: 'AAA001'));
    source.emit(
      sampleCandidate(
        candidateId: 'ble:2',
        macSuffix: 'AAA002',
        modelHint: 'NE301',
      ),
    );
    source.emit(
      sampleCandidate(
        candidateId: 'ble:3',
        macSuffix: 'BBB003',
        modelHint: 'NE301',
      ).copyWith(channels: const {DiscoveryChannel.accessPoint}),
    );
    await settle(tester);
    // 无过滤：三行齐全，无匹配徽章。
    expect(find.text('AAA001'), findsOneWidget);
    expect(find.text('AAA002'), findsOneWidget);
    expect(find.text('BBB003'), findsOneWidget);
    expect(find.text('匹配 1/3'), findsNothing);

    // 设备栏（列头下拉）选 NE301：菜单浮层在页面内容之后，同名行文本
    // 取 .last 命中菜单项。
    await tester.tap(find.byKey(const Key('scan-model-filter')));
    await settle(tester);
    await tester.tap(find.text('NE301').last);
    await settle(tester);
    expect(find.text('AAA001'), findsNothing);
    expect(find.text('AAA002'), findsOneWidget);
    expect(find.text('BBB003'), findsOneWidget);
    expect(find.text('匹配 2/3'), findsOneWidget);

    // 通道栏选 AP：两道过滤叠加，只剩走 AP 通道的那行。
    await tester.tap(find.byKey(const Key('scan-channel-filter')));
    await settle(tester);
    await tester.tap(find.text('AP').last);
    await settle(tester);
    expect(find.text('BBB003'), findsOneWidget);
    expect(find.text('AAA002'), findsNothing);
    expect(find.text('匹配 1/3'), findsOneWidget);

    // 设备栏回到「全部型号」：型号过滤解除，通道过滤仍限定 AP。
    await tester.tap(find.byKey(const Key('scan-model-filter')));
    await settle(tester);
    await tester.tap(find.text('全部型号'));
    await settle(tester);
    expect(find.text('AAA001'), findsNothing);
    expect(find.text('AAA002'), findsNothing);
    expect(find.text('BBB003'), findsOneWidget);
    expect(find.text('匹配 1/3'), findsOneWidget);

    // 叠加无命中组合（NE101 × AP）：空匹配行 + 0 匹配徽章。
    await tester.tap(find.byKey(const Key('scan-model-filter')));
    await settle(tester);
    await tester.tap(find.text('NE101').last);
    await settle(tester);
    expect(find.text('没有匹配的设备'), findsOneWidget);
    expect(find.text('匹配 0/3'), findsOneWidget);

    // 通道栏回到「全部通道」：通道过滤解除，型号过滤仍在。
    await tester.tap(find.byKey(const Key('scan-channel-filter')));
    await settle(tester);
    await tester.tap(find.text('全部通道'));
    await settle(tester);
    expect(find.text('AAA001'), findsOneWidget);
    expect(find.text('BBB003'), findsNothing);
    expect(find.text('匹配 1/3'), findsOneWidget);

    // 设备栏回到「全部型号」：全量恢复，徽章消失。
    await tester.tap(find.byKey(const Key('scan-model-filter')));
    await settle(tester);
    await tester.tap(find.text('全部型号'));
    await settle(tester);
    expect(find.text('AAA001'), findsOneWidget);
    expect(find.text('AAA002'), findsOneWidget);
    expect(find.text('BBB003'), findsOneWidget);
    expect(find.text('匹配 1/3'), findsNothing);

    // 收尾：清扫定时器停表（同忙候选用例配方）。
    await tester.tap(find.text('重新扫描'));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(seconds: 21));
    expect(controller.phase, SessionPhase.scanEmpty);
  });

  testWidgets('M5 结果表分页：每页 8 行，翻页浏览，扫码聚焦自动跳页', (tester) async {
    final source = FakeSource();
    final device = FakeCtDevice();
    final controller = wiredController(source, device);
    addTearDown(source.close);
    addTearDown(device.close);
    addTearDown(controller.dispose);

    await pumpApp(tester, controller);
    await settle(tester);

    for (var i = 1; i <= 9; i++) {
      source.emit(
        sampleCandidate(
          candidateId: 'ble:$i',
          macSuffix: 'AAA00$i', // AAA001..AAA009（注册表按到达序）
        ),
      );
    }
    await settle(tester);
    // 第 1 页：前 8 行 + 分页器；第 9 行不在页内。
    expect(find.text('AAA008'), findsOneWidget);
    expect(find.text('AAA009'), findsNothing);
    expect(find.text('第 1/2 页'), findsOneWidget);

    await tester.tap(find.text('下一页'));
    await settle(tester);
    expect(find.text('AAA001'), findsNothing);
    expect(find.text('AAA009'), findsOneWidget);
    expect(find.text('第 2/2 页'), findsOneWidget);

    // 扫码聚焦第 1 页的行：页码自动跳回所在页（聚焦行不得藏在页后）。
    controller.focusQrCandidate('AAA001');
    await settle(tester);
    expect(find.text('AAA001'), findsOneWidget);
    expect(find.text('第 1/2 页'), findsOneWidget);

    // 收尾：清扫定时器停表。
    await tester.tap(find.text('重新扫描'));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(seconds: 21));
    expect(controller.phase, SessionPhase.scanEmpty);
  });

  testWidgets('M5 扫码入口收敛：空态面板按钮与结果表脚注，无钉底长条', (tester) async {
    final source = FakeSource();
    final device = FakeCtDevice();
    final controller = wiredController(source, device);
    addTearDown(source.close);
    addTearDown(device.close);
    // 结束在 scanning（指引打开、扫描定时器常驻）：测试体内同步 dispose，
    // 不再挂 addTearDown 的二次 dispose。

    await pumpApp(tester, controller);
    await settle(tester);
    // 有结果：入口是表格下方的轻量脚注（问题文案 + ghost 按钮）。
    source.emit(sampleCandidate());
    await settle(tester);
    expect(find.text('未发现您的设备？'), findsOneWidget); // 脚注问句
    expect(find.text('扫码添加'), findsOneWidget); // 脚注按钮

    // 空态：入口收进空态面板（按钮在面板内），无重复脚注。
    await tester.tap(find.text('重新扫描'));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(seconds: 21));
    expect(controller.phase, SessionPhase.scanEmpty);
    expect(find.text('扫码添加'), findsOneWidget);
    expect(find.text('未发现您的设备？'), findsNothing); // 无第二个问句

    // 空态按钮同样能打开扫码指引（后台持续重开扫描）。
    await tester.tap(find.text('扫码添加'));
    await settle(tester);
    expect(controller.phase, SessionPhase.scanning);
    controller.dispose();
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
    // M5：雷达态不再常驻扫码条（原钉底长条太突兀）——扫码入口收敛到
    // 空态面板按钮与结果表脚注。
    expect(find.text('未发现您的设备？'), findsNothing);
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

      // Result page: stored list + apply hint + next-device primary.
      expect(controller.phase, SessionPhase.completed);
      expect(find.text('已保存 1 项配置'), findsOneWidget);
      expect(find.text('Wi-Fi 联网'), findsOneWidget);
      expect(find.text('配置将在网络重连后生效'), findsOneWidget);
      // v7d: explicit identity block + copy/export beside the primary.
      expect(find.text('序列号'), findsOneWidget);
      expect(find.text('NL24Q4001234'), findsOneWidget);
      expect(find.text('完成时间'), findsOneWidget);
      expect(find.text('配置下一台设备'), findsOneWidget);
      expect(find.text('复制配置结果'), findsOneWidget);
      expect(find.text('导出记录'), findsOneWidget);

      await tester.tap(find.text('配置下一台设备'));
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
    // v7d: the pause control appears only with the countdown — during the
    // walk there is nothing to pause yet.
    expect(find.byIcon(Icons.pause_circle_outline), findsNothing);

    // Walk ticks (600ms/row) land for all three channels, then the countdown
    // arms — the digit is the proof the walk finished first.
    await tester.pump(const Duration(seconds: 2));
    // Round-2 A1: big countdown digits plus the suffix hint — unmissable.
    expect(find.text('5'), findsOneWidget);
    expect(find.text('秒后自动进入扫描'), findsOneWidget);
    // v6: the stay button is gone — v7d replaces click-anywhere with the
    // explicit pause button beside the digits.
    expect(find.text('停留本页'), findsNothing);
    expect(find.byIcon(Icons.pause_circle_outline), findsOneWidget);

    await tester.tap(find.byIcon(Icons.pause_circle_outline));
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
    // v7d: the scope is part of the contract — run-scope badge, lifecycle
    // hint, and export disabled while there is nothing to export.
    expect(find.text('本次运行记录'), findsOneWidget);
    expect(find.textContaining('关闭应用后清空'), findsOneWidget);
    expect(
      tester.widget<NLButton>(find.widgetWithText(NLButton, '导出记录')).onPressed,
      isNull,
    );

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
        nicEnumerator: ({bool includeVirtual = false}) async => [
          NicEndpoint(
            interfaceName: 'Ethernet',
            address: InternetAddress('192.168.93.20'),
            nicClass: NicClass.physical,
          ),
        ],
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

  testWidgets('v7d 通道条：默认紧凑一行，查看详情展开三卡后可收起', (tester) async {
    final source = FakeSource();
    final device = FakeCtDevice();
    final controller = wiredController(source, device);
    addTearDown(source.close);
    addTearDown(device.close);
    addTearDown(controller.dispose);

    await pumpApp(tester, controller);
    await settle(tester); // Self-check passed -> scanning page.

    // Collapsed by default: short segment text, full channel names hidden.
    expect(find.text('查看详情'), findsOneWidget);
    expect(find.text('BLE 可用'), findsOneWidget);
    expect(find.text('蓝牙 BLE'), findsNothing);

    await tester.tap(find.text('查看详情'));
    await settle(tester, 2);
    expect(find.text('收起'), findsOneWidget);
    expect(find.text('蓝牙 BLE'), findsOneWidget);
    expect(find.text('无线网卡（AP）'), findsOneWidget);
    expect(find.text('CT-Disc（预留）'), findsOneWidget);
    // 通道可用时没有「打开系统 Wi-Fi 设置」入口（M5：仅受限卡展示）。
    expect(find.text('打开系统 Wi-Fi 设置'), findsNothing);

    await tester.tap(find.text('收起'));
    await settle(tester, 2);
    expect(find.text('蓝牙 BLE'), findsNothing);
    expect(find.text('查看详情'), findsOneWidget);

    // Pump past the scan window so no timer dangles at teardown.
    await tester.pump(const Duration(seconds: 21));
    expect(controller.phase, SessionPhase.scanEmpty);
  });

  testWidgets('M5 AP 通道受限（网卡禁用）：详情卡提供打开系统 Wi-Fi 设置', (tester) async {
    final source = FakeSource();
    final device = FakeCtDevice();
    // 无线网卡全部 Disabled → AP 通道 limited / wlan_disabled。
    final controller = ProvisioningController(
      environmentProbe: DesktopEnvironmentProbe(
        probeBle: () async => const CtEnvironmentReport(
          readiness: CtBleReadiness.ready,
          detail: 'fake ready',
        ),
        enumerateAdapters: () async =>
            '[{"Name":"Wi-Fi","Status":"Disabled","PhysicalMediaType":"Native 802.11"}]',
        nicEnumerator: ({bool includeVirtual = false}) async => [],
      ),
      discoverySource: source,
      establishPairing: (_) async {},
      connectChannel: (_, __) async => device,
      linkEvents: (_) => const Stream<bool>.empty(),
      // 零等待跳过通道走查与倒计时，直达扫描页（同 wiredController 语义）。
      selfCheckHold: Duration.zero,
    );
    addTearDown(source.close);
    addTearDown(device.close);
    addTearDown(controller.dispose);

    var opened = 0;
    await pumpApp(tester, controller, wifiSettingsOpener: () async {
      opened++;
      return true;
    });
    await settle(tester); // 自检放行 → 扫描页

    // 紧凑条先呈现受限；入口只在展开的详情卡上。
    expect(find.text('AP 受限'), findsOneWidget);
    expect(find.text('打开系统 Wi-Fi 设置'), findsNothing);
    await tester.tap(find.text('查看详情'));
    await settle(tester, 2);
    expect(find.text('打开系统 Wi-Fi 设置'), findsOneWidget);

    await tester.tap(find.text('打开系统 Wi-Fi 设置'));
    await settle(tester, 2);
    expect(opened, 1);

    await tester.pump(const Duration(seconds: 21));
    expect(controller.phase, SessionPhase.scanEmpty);
  });

  testWidgets('M5 AP-only 行：连接前弹断网提示，取消留在列表，「应用内配置」进 softAP 链', (tester) async {
    final source = FakeSource();
    final device = FakeCtDevice();
    final joiner = FakeApJoiner();
    final transport = FakeApTransport();
    final controller = wiredController(
      source,
      device,
      apJoiner: joiner,
      apTransportFactory: (_) => transport,
    );
    addTearDown(source.close);
    addTearDown(device.close);
    addTearDown(controller.dispose);

    await pumpApp(tester, controller);
    await settle(tester); // 自检放行 → 扫描页
    source.emit(apCandidate());
    await settle(tester);
    expect(controller.phase, SessionPhase.resultsAvailable);

    await tester.tap(find.text('连接'));
    await settle(tester, 12); // dialog open animation
    // 提示同时点名设备热点与将被暂时断开的当前网络。
    expect(find.text('连接设备 Wi-Fi'), findsOneWidget);
    expect(find.text('应用将连接设备热点 NE101-P_BBC6DC 进行配置。'), findsOneWidget);
    expect(
      find.text('连接期间将暂时断开当前 Wi-Fi（TP-LINK-5G），配置结束后自动恢复。'),
      findsOneWidget,
    );

    // 取消：留在候选列表，未动 radio。
    await tester.tap(find.text('取消'));
    await settle(tester, 12); // route exit animation
    expect(find.text('连接设备 Wi-Fi'), findsNothing);
    expect(controller.phase, SessionPhase.resultsAvailable);
    expect(joiner.joins, isEmpty);

    // 「应用内配置」：进入 softAP 连接链，直达模块列表（web 选择由
    // web 模式用例覆盖）。
    await tester.tap(find.text('连接'));
    await settle(tester, 12);
    await tester.tap(find.text('应用内配置'));
    await settle(tester);
    expect(joiner.joins, ['NE101-P_BBC6DC']);
    expect(controller.phase, SessionPhase.choosingSections);
    expect(find.text('NE101-P_BBC6DC'), findsOneWidget); // 会话上下文条

    // 会话收尾：radio 还给原网，重扫收敛回空态（无悬挂定时器）。
    expect(joiner.restores, isEmpty);
    await controller.rescan();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(seconds: 21));
    expect(controller.phase, SessionPhase.scanEmpty);
    expect(joiner.restores, [
      const WlanRestorePoint(ssid: 'TP-LINK-5G', profileName: 'TP-LINK-5G'),
    ]);
  });

  testWidgets('v7d 取消会话：已有输入先确认，继续编辑保留 / 放弃并退出清空', (tester) async {
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
    await tester.tap(find.text('Wi-Fi 联网'));
    await settle(tester);
    expect(controller.phase, SessionPhase.editingConfig);

    // Prefilled ssid counts as content — cancel must ask first.
    await tester.ensureVisible(find.text('取消会话'));
    await tester.pump();
    await tester.tap(find.text('取消会话'));
    await settle(tester, 12); // dialog open animation is 150ms
    expect(find.text('取消本次会话？'), findsOneWidget);
    expect(find.text('继续编辑'), findsOneWidget);
    expect(find.text('放弃并退出'), findsOneWidget);

    // Keep editing: dialog closes, the round and drafts stay.
    await tester.tap(find.text('继续编辑'));
    await settle(tester, 12); // let the route exit animation finish
    expect(controller.phase, SessionPhase.editingConfig);
    expect(find.text('取消本次会话？'), findsNothing);
    expect((controller.drafts['wifi'] as WifiSection).ssid, 'Office-2.4G');

    // Discard: back to scanning with the round cleared.
    await tester.ensureVisible(find.text('取消会话'));
    await tester.pump();
    await tester.tap(find.text('取消会话'));
    await settle(tester, 12);
    await tester.tap(find.text('放弃并退出'));
    await settle(tester);
    expect(controller.phase, SessionPhase.scanning);
    expect(controller.editingSections, isEmpty);
    expect(controller.drafts, isEmpty);

    await tester.pump(const Duration(seconds: 21));
    expect(controller.phase, SessionPhase.scanEmpty);
  });

  testWidgets('v7d 取消会话：无输入直接退出，不弹确认', (tester) async {
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
    await tester.tap(find.text('Wi-Fi 联网'));
    await settle(tester);

    // Clear the prefilled ssid: nothing left worth confirming about.
    await tester.enterText(find.byType(TextField).at(0), '');
    await tester.pump();
    await tester.ensureVisible(find.text('取消会话'));
    await tester.pump();
    await tester.tap(find.text('取消会话'));
    await settle(tester, 2);
    expect(find.text('取消本次会话？'), findsNothing); // straight out
    expect(controller.phase, SessionPhase.scanning);

    await tester.pump(const Duration(seconds: 21));
    expect(controller.phase, SessionPhase.scanEmpty);
  });
}
