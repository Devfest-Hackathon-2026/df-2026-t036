import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:illustration_exchange/screens/inbox_screen.dart';
import 'package:illustration_exchange/screens/artwork_detail_screen.dart';
import 'package:illustration_exchange/screens/ideas_screen.dart';
import 'package:illustration_exchange/widgets/artwork_actions.dart';

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
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(Image)),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveTo(
      tester.getCenter(find.byKey(const ValueKey('quick-action-like'))),
    );
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(
      tester.widget<ArtworkActions>(find.byType(ArtworkActions)).liked,
      isTrue,
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('既読'), findsOneWidget);
    await tester.tap(find.byType(IdeaSlotCard).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(
      tester.widget<ArtworkActions>(find.byType(ArtworkActions)).liked,
      isTrue,
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
  }, skip: !const bool.fromEnvironment('DEV_PREVIEW'));
}
