import 'package:flutter_test/flutter_test.dart';
import 'package:desktop_app/app.dart';

void main() {
  testWidgets('空壳启动：导航、占位页、主题与中英切换', (tester) async {
    await tester.pumpWidget(const NeoLinkApp());
    expect(find.text('NeoLink'), findsOneWidget);
    expect(find.text('环境自检'), findsWidgets);

    // 切页
    await tester.tap(find.text('扫描设备'));
    await tester.pumpAndSettle();

    // 语言 zh → en：导航与占位文案即时切换
    await tester.tap(find.text('EN'));
    await tester.pumpAndSettle();
    expect(find.text('Environment self-check'), findsWidgets);
    expect(find.text('Scan devices'), findsWidgets);
    expect(find.text('未发现设备'), findsNothing);

    // 主题（en 下按钮文案为 Dark/Light）
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(find.text('Light'), findsOneWidget);

    // 切回中文
    await tester.tap(find.text('中文'));
    await tester.pumpAndSettle();
    expect(find.text('环境自检'), findsWidgets);
  });
}
