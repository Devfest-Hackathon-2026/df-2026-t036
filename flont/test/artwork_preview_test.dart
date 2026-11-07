import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:illustration_exchange/screens/inbox_screen.dart';
import 'package:illustration_exchange/screens/artwork_detail_screen.dart';
import 'package:illustration_exchange/screens/ideas_screen.dart';

void main() {
  testWidgets('preview image displays and read state persists when returning', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: InboxScreen())),
    );
    await tester.tap(find.byType(IdeaSlotCard).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ArtworkDetailScreen), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('既読'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  }, skip: !const bool.fromEnvironment('DEV_PREVIEW'));
}
