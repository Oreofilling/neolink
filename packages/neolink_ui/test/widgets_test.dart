import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neolink_ui/neolink_ui.dart';

void main() {
  testWidgets('NLBadge/NLCard/NLButton 在亮暗主题下渲染', (tester) async {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: nlTheme(brightness),
          home: const Scaffold(
            body: Column(
              children: [
                NLCard(
                  child: NLBadge(
                    label: '通过',
                    variant: NLBadgeVariant.success,
                    dot: true,
                  ),
                ),
                NLButton(label: '重新检测'),
              ],
            ),
          ),
        ),
      );
      expect(find.text('通过'), findsOneWidget);
      expect(find.text('重新检测'), findsOneWidget);
    }
  });

  testWidgets('NLSkeleton 持续动画不抛异常', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: nlTheme(Brightness.light),
        home: const Scaffold(body: NLSkeleton(width: 120, height: 10)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(NLSkeleton), findsOneWidget);
  });

  testWidgets('NLLogo 亮暗主题与反白变体渲染', (tester) async {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: nlTheme(brightness),
          home: const Scaffold(
            body: Row(
              children: [
                NLLogo(size: 22), // 简化形
                NLLogo(size: 32), // 完整形
                NLLogo(size: 32, onPrimary: true), // 主色砖反白
              ],
            ),
          ),
        ),
      );
      expect(find.byType(NLLogo), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'v7d: destructive/elevated/interactive matrix builds in both themes',
    (tester) async {
      for (final brightness in [Brightness.light, Brightness.dark]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: nlTheme(brightness),
            home: const Scaffold(
              body: Column(
                children: [
                  NLButton(label: '主操作', variant: NLButtonVariant.primary),
                  NLButton(label: '次操作', variant: NLButtonVariant.secondary),
                  NLButton(label: '幽灵', variant: NLButtonVariant.ghost),
                  NLButton(
                    label: '放弃并退出',
                    variant: NLButtonVariant.destructive,
                  ),
                  NLButton(label: '禁用', onPressed: null),
                  NLCard(child: SizedBox(width: 20, height: 8)),
                  NLCard(elevated: true, child: SizedBox(width: 20, height: 8)),
                  NLCard(
                    interactive: true,
                    child: SizedBox(width: 20, height: 8),
                  ),
                ],
              ),
            ),
          ),
        );
        expect(find.text('主操作'), findsOneWidget);
        expect(find.text('放弃并退出'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('v7d: hover and pressed states render without errors', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: nlTheme(Brightness.light),
        home: const Scaffold(
          body: Center(
            child: NLButton(label: '悬停我', variant: NLButtonVariant.secondary),
          ),
        ),
      ),
    );
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer();
    addTearDown(gesture.removePointer);
    await tester.pump();
    // Hover: move the mouse pointer onto the button, then press and release.
    await gesture.moveTo(tester.getCenter(find.text('悬停我')));
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.down(tester.getCenter(find.text('悬停我')));
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('悬停我'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
