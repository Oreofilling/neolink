// 冒烟测试：界面可构建、标题可见（无射频环境不触发扫描）。
import 'package:ct_prov_poc/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('app builds with title', (tester) async {
    await tester.pumpWidget(const CtProvPocApp());
    expect(find.text('CT-Prov PoC'), findsOneWidget);
    expect(find.text('Start scan'), findsOneWidget);
  });
}
