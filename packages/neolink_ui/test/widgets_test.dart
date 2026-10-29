import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neolink_ui/neolink_ui.dart';

void main() {
  testWidgets('NLBadge/NLCard/NLButton 在亮暗主题下渲染', (tester) async {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      await tester.pumpWidget(MaterialApp(
        theme: nlTheme(brightness),
        home: const Scaffold(
          body: Column(children: [
            NLCard(child: NLBadge(label: '通过', variant: NLBadgeVariant.success, dot: true)),
            NLButton(label: '重新检测'),
          ]),
        ),
      ));
      expect(find.text('通过'), findsOneWidget);
      expect(find.text('重新检测'), findsOneWidget);
    }
  });

  testWidgets('NLSkeleton 持续动画不抛异常', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: nlTheme(Brightness.light),
      home: const Scaffold(body: NLSkeleton(width: 120, height: 10)),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(NLSkeleton), findsOneWidget);
  });
}
