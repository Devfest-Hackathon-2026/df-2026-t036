import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:illustration_exchange/screens/profile_screen.dart';

const _previewEnabled = bool.fromEnvironment('DEV_PREVIEW');

void main() {
  testWidgets('profile layout fits phone, tablet, and desktop widths', (
    tester,
  ) async {
    for (final size in [
      const Size(320, 800),
      const Size(768, 1024),
      const Size(1280, 900),
    ]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          home: ProfileScreen(
            active: false,
            me: const {
              'uid': 'preview-user',
              'nickname': 'サンプルのえふで01ab',
              'ideaCount': 2,
              'drawnCount': 4,
              'likesReceived': 3,
              'bio': '水彩で風景を描いています。',
              'socialLinks': <Map<String, dynamic>>[],
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'layout: $size');
    }
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }, skip: !_previewEnabled);

  testWidgets('profile preview edits bio and adds a social link locally', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(
          active: false,
          me: const {
            'uid': 'preview-user',
            'nickname': 'サンプルのえふで01ab',
            'ideaCount': 2,
            'drawnCount': 4,
            'likesReceived': 3,
            'bio': '水彩で風景を描いています。',
            'socialLinks': <Map<String, dynamic>>[
              {
                'type': 'pixiv',
                'label': 'pixiv',
                'url': 'https://www.pixiv.net/users/example',
              },
            ],
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('プロフィール'), findsOneWidget);
    expect(find.text('水彩で風景を描いています。'), findsOneWidget);
    expect(find.text('https://www.pixiv.net/users/example'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('profile-edit')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('profile-bio-input')),
      '物語のある背景を描きます。',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('profile-link-add')));
    await tester.tap(find.byKey(const ValueKey('profile-link-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('profile-link-label-1')),
      'X',
    );
    await tester.enterText(
      find.byKey(const ValueKey('profile-link-url-1')),
      'https://x.com/example',
    );
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('profile-preview-save')),
    );
    await tester.tap(find.byKey(const ValueKey('profile-preview-save')));
    await tester.pumpAndSettle();

    expect(find.text('物語のある背景を描きます。'), findsOneWidget);
    expect(find.text('https://x.com/example'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, skip: !_previewEnabled);
}
