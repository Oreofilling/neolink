import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:desktop_app/app.dart';
import 'package:desktop_app/provisioning/provisioning_controller.dart';
import 'package:desktop_app/services/settings_store.dart';

import 'provisioning_fakes.dart';

void main() {
  // 页面含无限循环的骨架屏动画，禁用 pumpAndSettle，一律单帧 pump。
  // 注入阻塞自检的控制器：任何机器上启动页都停在自检，导航行为确定
  // （不依赖真机蓝牙/网卡探测结果）。语言跟随系统：测试显式置中文。
  testWidgets('空壳启动：导航、自检页、主题与中英切换', (tester) async {
    final source = FakeSource();
    final controller = ProvisioningController(
      environmentProbe: blockedProbe(),
      discoverySource: source,
      establishPairing: (_) async {},
      connectChannel: (_, __) async => FakeCtDevice(),
    );
    addTearDown(source.close);
    addTearDown(controller.dispose);

    tester.platformDispatcher.localesTestValue = const [Locale('zh')];
    await tester.pumpWidget(
      NeoLinkApp(controller: controller, settings: SettingsStore.none()),
    );
    // v6 品牌行出现两处：侧栏 + 自检页卡片。
    expect(find.text('NeoLink'), findsNWidgets(2));
    expect(find.text('环境自检'), findsWidgets);
    await tester.pump(); // 自检完成（阻塞态停留）

    await tester.tap(find.text('扫描设备'));
    await tester.pump();

    // v6: the toggle states the CURRENT language — zh UI shows 中文; tapping
    // swaps to English (label flips to EN).
    await tester.tap(find.text('中文'));
    await tester.pump();
    expect(find.text('Environment self-check'), findsWidgets);
    expect(find.text('Scan devices'), findsWidgets);
    expect(find.text('未发现设备'), findsNothing);
    expect(find.text('EN'), findsOneWidget);

    await tester.tap(find.text('Dark'));
    await tester.pump();
    expect(find.text('Light'), findsOneWidget);

    await tester.tap(find.text('EN'));
    await tester.pump();
    expect(find.text('环境自检'), findsWidgets);
  });
}
