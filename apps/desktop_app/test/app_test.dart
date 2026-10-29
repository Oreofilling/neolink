import 'package:flutter_test/flutter_test.dart';
import 'package:desktop_app/app.dart';

void main() {
  // 占位页含无限循环的骨架屏动画，禁用 pumpAndSettle，一律单帧 pump。
  testWidgets('空壳启动：导航、占位页、主题与中英切换', (tester) async {
    await tester.pumpWidget(const NeoLinkApp());
    expect(find.text('NeoLink'), findsOneWidget);
    expect(find.text('环境自检'), findsWidgets);

    await tester.tap(find.text('扫描设备'));
    await tester.pump();

    await tester.tap(find.text('EN'));
    await tester.pump();
    expect(find.text('Environment self-check'), findsWidgets);
    expect(find.text('Scan devices'), findsWidgets);
    expect(find.text('未发现设备'), findsNothing);

    await tester.tap(find.text('Dark'));
    await tester.pump();
    expect(find.text('Light'), findsOneWidget);

    await tester.tap(find.text('中文'));
    await tester.pump();
    expect(find.text('环境自检'), findsWidgets);
  });
}
