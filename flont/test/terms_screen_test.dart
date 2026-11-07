import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:illustration_exchange/screens/settings_screen.dart';
import 'package:illustration_exchange/screens/terms_screen.dart';
import 'package:illustration_exchange/screens/login_screen.dart';

// 一度だけ読み込みに失敗するアセットで、再試行の導線を確認する。
class RetryTermsBundle extends CachingAssetBundle {
  int attempts = 0;

  @override
  Future<ByteData> load(String key) => throw UnimplementedError();

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    if (++attempts == 1) throw StateError('読み込み失敗');
    return '# EWOCURU テスト版利用規約\n\n## 1．サービスについて\n\n規約本文';
  }
}

// 実際のアセット本文を読み込んだ後、描画テスト内では同じ文字列を同期的に供給する。
class LoadedTermsBundle extends CachingAssetBundle {
  LoadedTermsBundle(this.source);
  final String source;
  @override
  Future<ByteData> load(String key) => throw UnimplementedError();
  @override
  Future<String> loadString(String key, {bool cache = true}) async => source;
}

void main() {
  // 規約の閲覧で認証処理を呼ばず、ログイン画面へ戻れることを確認する。
  testWidgets('ログイン前に規約を開いて戻る', (tester) async {
    var signInCount = 0;
    await tester.pumpWidget(
      DefaultAssetBundle(
        bundle: LoadedTermsBundle(
          '# EWOCURU テスト版利用規約\n\n## 1．サービスについて\n\n規約本文',
        ),
        child: MaterialApp(home: LoginScreen(onSignIn: () => signInCount++)),
      ),
    );
    final link = find.byKey(const ValueKey('login-terms-button'));
    await tester.ensureVisible(link);
    await tester.pumpAndSettle();
    await tester.tap(link);
    await tester.pumpAndSettle();
    expect(find.byType(TermsScreen), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);
    expect(signInCount, 0);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
  });
  testWidgets('設定から実際の利用規約全文を開いて戻る', (tester) async {
    final source = await tester.runAsync(
      () => rootBundle.loadString('assets/legal/terms-test.md'),
    );
    expect(source, contains('## 10．規約の変更・お問い合わせ'));
    await tester.pumpWidget(
      DefaultAssetBundle(
        bundle: LoadedTermsBundle(source!),
        child: const MaterialApp(
          home: SettingsScreen(
            nickname: 'テスト',
            googleEmail: 'test@example.test',
          ),
        ),
      ),
    );
    await tester.ensureVisible(find.text('利用規約'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('利用規約'));
    await tester.pumpAndSettle();
    expect(find.byType(TermsScreen), findsOneWidget);
    final text = tester
        .widget<SelectableText>(find.byType(SelectableText))
        .textSpan!
        .toPlainText();
    expect(text, contains('EWOCURU テスト版利用規約'));
    expect(text, contains('10．規約の変更・お問い合わせ'));
    expect(text, contains('そのURLを受け取った連絡手段でご連絡ください。'));
    expect(text, isNot(contains('公開前の確認メモ')));
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
  });

  testWidgets('規約の読み込み失敗後に再試行できる', (tester) async {
    final bundle = RetryTermsBundle();
    await tester.pumpWidget(
      DefaultAssetBundle(
        bundle: bundle,
        child: const MaterialApp(home: TermsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('利用規約を読み込めませんでした。'), findsOneWidget);
    await tester.tap(find.text('再試行'));
    await tester.pumpAndSettle();
    expect(find.byType(SelectableText), findsOneWidget);
    expect(bundle.attempts, 2);
  });
}
