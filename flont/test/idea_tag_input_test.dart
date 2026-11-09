import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:illustration_exchange/screens/idea_composer_screen.dart';
import 'package:illustration_exchange/screens/ideas_screen.dart';

const inputKey = ValueKey('idea-tag-input');
const previewKey = ValueKey('idea-preview-button');

Future<void> openComposer(
  WidgetTester tester, {
  Future<List<String>> Function()? suggestions,
  Future<void> Function(IdeaDraft)? submit,
}) async {
  await tester.binding.setSurfaceSize(const Size(900, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: IdeaComposerScreen(
        loadTagSuggestions: suggestions,
        onSubmit: submit ?? (_) async {},
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> fillRequired(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const ValueKey('idea-title-input')),
    'A title',
  );
  await tester.enterText(
    find.byKey(const ValueKey('idea-description-input')),
    'A description',
  );
}

void main() {
  testWidgets(
    'filters suggestions and adds a selected tag without pending text',
    (tester) async {
      await openComposer(
        tester,
        suggestions: () async => ['fantasy', 'forest', 'sea', 'forest'],
      );
      expect(find.byType(ActionChip), findsNWidgets(3));
      await tester.enterText(find.byKey(inputKey), 'for');
      await tester.pump();
      expect(find.byType(ActionChip), findsOneWidget);
      await tester.tap(find.widgetWithText(ActionChip, 'forest'));
      await tester.pump();
      expect(find.widgetWithText(InputChip, 'forest'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byKey(inputKey)).controller!.text,
        isEmpty,
      );
      expect(find.widgetWithText(ActionChip, 'forest'), findsNothing);
    },
  );

  testWidgets('confirmation includes a pending tag', (tester) async {
    IdeaDraft? submitted;
    await openComposer(
      tester,
      submit: (draft) async {
        submitted = draft;
      },
    );
    await fillRequired(tester);
    await tester.enterText(find.byKey(inputKey), 'forest');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(find.widgetWithText(InputChip, 'forest'), findsOneWidget);
    await tester.enterText(find.byKey(inputKey), 'sea');
    await tester.pump();
    await tester.ensureVisible(find.byKey(previewKey));
    await tester.tap(find.byKey(previewKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('idea-submit-button')));
    await tester.pumpAndSettle();
    expect(submitted!.tags, ['forest', 'sea']);
  });

  testWidgets('pending sixth tag blocks confirmation and preserves input', (
    tester,
  ) async {
    await openComposer(tester);
    await fillRequired(tester);
    for (var index = 0; index < 5; index++) {
      await tester.enterText(find.byKey(inputKey), 'tag$index');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
    }
    await tester.enterText(find.byKey(inputKey), 'sixth');
    await tester.pump();
    await tester.ensureVisible(find.byKey(previewKey));
    await tester.tap(find.byKey(previewKey));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('idea-submit-button')), findsNothing);
    expect(find.byType(InputChip), findsNWidgets(5));
    expect(
      tester.widget<TextField>(find.byKey(inputKey)).controller!.text,
      'sixth',
    );
  });

  testWidgets('IME composition is not added by submission callback', (
    tester,
  ) async {
    await openComposer(tester);
    final field = tester.widget<TextField>(find.byKey(inputKey));
    field.controller!.value = const TextEditingValue(
      text: 'sample',
      selection: TextSelection.collapsed(offset: 6),
      composing: TextRange(start: 0, end: 6),
    );
    field.onSubmitted!('sample');
    await tester.pump();
    expect(find.byType(InputChip), findsNothing);
    field.controller!.clearComposing();
    field.onSubmitted!('sample');
    await tester.pump();
    expect(find.widgetWithText(InputChip, 'sample'), findsOneWidget);
  });

  testWidgets('failed suggestions can retry without losing manual input', (
    tester,
  ) async {
    var calls = 0;
    await openComposer(
      tester,
      suggestions: () async {
        if (++calls == 1) throw StateError('offline');
        return ['forest'];
      },
    );
    await tester.enterText(find.byKey(inputKey), 'for');
    await tester.pump();
    await tester.tap(find.widgetWithIcon(TextButton, Icons.refresh));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ActionChip, 'forest'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byKey(inputKey)).controller!.text,
      'for',
    );
  });

  testWidgets('duplicate tags stay unique and can be removed', (tester) async {
    await openComposer(tester);
    for (var index = 0; index < 2; index++) {
      await tester.enterText(find.byKey(inputKey), 'forest');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
    }
    expect(find.byType(InputChip), findsOneWidget);
    tester.widget<InputChip>(find.byType(InputChip)).onDeleted!();
    await tester.pump();
    expect(find.byType(InputChip), findsNothing);
  });

  testWidgets('oversized pending tag prevents confirmation', (tester) async {
    await openComposer(tester);
    await fillRequired(tester);
    final controller = tester
        .widget<TextField>(find.byKey(inputKey))
        .controller!;
    controller.text = 'a' * 21;
    await tester.pump();
    await tester.ensureVisible(find.byKey(previewKey));
    await tester.tap(find.byKey(previewKey));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('idea-submit-button')), findsNothing);
    expect(find.byType(InputChip), findsNothing);
    expect(controller.text.length, 21);
  });

  testWidgets('tag suggestions fit a narrow screen', (tester) async {
    await openComposer(
      tester,
      suggestions: () async => ['abcdefghijklmnopqrst', 'forest'],
    );
    await tester.binding.setSurfaceSize(const Size(320, 900));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(inputKey), 'abcdefghijklmnopqrst');
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('idea-add-tag')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'composer gets suggestions from the existing authenticated ideas API',
    (tester) async {
      var requested = false;
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/me/slots')) {
          return http.Response(jsonEncode({'slots': {}}), 200);
        }
        expect(request.url.path, '/api/v1/ideas');
        expect(request.url.queryParameters['limit'], '1');
        expect(request.headers['Authorization'], 'Bearer token');
        requested = true;
        return http.Response(
          jsonEncode({
            'items': [],
            'tags': ['forest'],
          }),
          200,
        );
      });
      addTearDown(client.close);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IdeasScreen(
              authenticated: true,
              client: client,
              idTokenProvider: () async => 'token',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('idea-slot-1')));
      await tester.pumpAndSettle();
      expect(requested, isTrue);
      await tester.ensureVisible(find.widgetWithText(ActionChip, 'forest'));
      expect(find.widgetWithText(ActionChip, 'forest'), findsOneWidget);
    },
    skip: const bool.fromEnvironment('DEV_PREVIEW'),
  );
}
