# プライバシーポリシー v0：公開前の確認メモ

作成日：2026年11月8日。本文は [privacy-policy-v0.md](privacy-policy-v0.md)。このメモは運営内の確認用です。v0はコミットしてレビューするための草案であり、そのまま公開・適用しません。草案原本をFlutterのアセットに登録し、ログイン前・設定画面から参照できるようにしています。公開版としての確定や同意取得は行いません。

## 今回の文章整理

- 本文の10項構成を維持し、利用者向けの説明に統一した。
- アプリの文書画面は表を描画しないため、取得情報・保存期間の表を段落に変更した。
- Firebase Authenticationの情報と独自users文書の情報、通常閲覧と運営による確認を区別した。
- 7日間の閲覧期限と、環境設定が必要な非同期の物理削除、投稿制限の判定期間と記録の削除時期を明確にした。
- 運営者・適用日・保持期間・外部処理・紹介利用の未確定事項は確定させず、本文にも利用者の判断に必要な説明を残した。
- 保存期間・第三者提供・安全管理について、未確認の保証や新たな運営方針は追加していない。

## 公開までに決める事項

- [ ] 運営者の氏名または名称、住所、法人の場合の代表者、必要事項の公表方法を決める。
- [ ] テストの招待窓口が実際に応答・引継ぎできることを確認し、一般公開の連絡先を決める。
- [ ] アカウント、削除済みお題、描いた履歴、投稿予約、ログ、問い合わせ、バックアップごとの保存期間と削除担当を決める。
- [ ] 確定作品の7日期限後の削除について、各公開環境でCloud Scheduler・Firestore TTL・IAMを設定し、画像削除と文書削除まで動作確認する。
- [ ] 未確定画像と期限切れピンのScheduler設定、失敗時の監視・再試行を確認する。
- [ ] 手動の退会・削除手順を作る。Firebase Authentication、Firestore、Storage、関連履歴等の対象と例外、本人確認、回答時期を明確にする。
- [ ] Googleとの契約主体、利用リージョン・処理国、再委託先、外国での取り扱い、必要な情報提供・同意を確認する。国内リージョン指定だけで判断しない。
- [ ] Cloud Visionの送信データ・保存・利用条件を確認し、利用規約の生成AI禁止と画像審査の関係を明確にする。
- [ ] Googleログインの実際のスコープ、Firebase Authenticationが保存する属性、ブラウザ保存領域、Cloud Run等のアクセスログ・保存期間を確認する。
- [ ] Google Fontsなど、ブラウザから追加の外部通信が発生するSDK・資産取得と、アクセス解析・広告の有無を実環境で確認する。
- [ ] 発表資料等での作品利用の案内・同意方法・保存期間を決め、既存利用規約第5〜7条と合わせる。v0では新たな許諾を取得しない。
- [ ] 対象年齢と未成年者への案内、適用日、改定通知方法を決める。
- [ ] 本文の未定・草案表記を解消し、公開前に法務確認を行う。
- [x] ログイン前・設定画面から草案を参照可能にする。ログイン画面で草案への同意を自動取得したと表示しない。
- [ ] 正式公開時の同意方針と記録方法を確定する。

## 実装との照合

| 確認項目 | 参照箇所と注意点 |
|---|---|
| 認証・独自ユーザー情報 | back/app/auth.py、users.py、flont/lib/screens/settings_screen.dart。Googleアカウント名・メールを独自users文書に保存しないことと、Firebase側の取得・保存を区別する。 |
| 投稿と画像審査 | back/app/artwork_submission.py、vision_demo.py。作品とデモの画像がCloud Visionへ送信される。 |
| 閲覧権限・期限 | back/app/artworks.py、artwork_expiry.py。受信者と期限をAPIで検証し、期限削除APIがStorage画像の削除後にFirestore TTLへ引き渡す。定期実行・TTL設定は環境ごとに必要。 |
| 投稿制限 | back/app/post_limits.py。記録は上限件数までで、期限経過後の次回投稿時に除去する。 |
| 共通APIログ | back/app/middleware.py。本文等を記録しない設計だが、Uvicorn・Cloud Run・Firebase等の別ログまで同じとは限らない。 |
| 現行規約 | flont/assets/legal/terms-test.md。問い合わせ窓口、手動退会、非表示と物理削除の区別を引き継ぐ。 |
| ポリシー表示 | ログイン前・設定画面から草案原本をアセットとして読み込む。内部確認メモは同梱しない。 |

## 参照した公式資料

2026年11月8日に参照。本文は法的適合性が確認済みであることを示すものではありません。

- [個人情報保護委員会：個人情報保護法ガイドラインQ&A](https://www.ppc.go.jp/personalinfo/faq/APPI_QA/)
- [個人情報保護委員会：クラウド利用と第三者提供・委託の考え方](https://www.ppc.go.jp/all_faq_index/faq1-q7-53/)
- [個人情報保護委員会：外国にある第三者への提供編](https://www.ppc.go.jp/personalinfo/legal/guidelines_offshore/)

## コミット例

```powershell
git add docs/legal/privacy-policy-v0.md docs/legal/privacy-policy-review.md flont/lib/screens/privacy_policy_screen.dart flont/lib/screens/terms_screen.dart flont/lib/screens/login_screen.dart flont/lib/screens/settings_screen.dart flont/pubspec.yaml flont/test/terms_screen_test.dart
git commit -m "feat: make privacy policy v0 accessible"
```
