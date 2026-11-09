import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:illustration_exchange/main.dart';

void main() {
  // PCでもバーを出さず、ドラッグで一覧を移動できることを確認する。
  testWidgets('共通設定でバーを隠しマウスドラッグを受け付ける', (tester) async {
    final controller = ScrollController();
    await tester.pumpWidget(
      IllustrationExchangeApp(
        home: Scaffold(
          body: ListView.builder(
            controller: controller,
            itemCount: 40,
            itemBuilder: (context, index) =>
                SizedBox(height: 100, child: Text('$index')),
          ),
        ),
      ),
    );
    expect(find.byType(Scrollbar), findsNothing);
    final gesture = await tester.startGesture(
      const Offset(200, 400),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(0, -200));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(0));
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
