# Flutterアプリ

初回設定・起動手順の正本はdocs側にまとめています。

- [環境構築](../docs/environment.md)：必要なSDK、Firebase設定、依存関係
- [起動・停止・エラー対処](../docs/startup.md)：通常ログイン、Docker、認証なしプレビュー
- [デザインガイド](../docs/flont/design.md)：色・フォント・共通UI
- [受信画像の表示・保存](../docs/flont/received-artwork.md)：形式・権限・確認手順
- [プロフィール編集・公開](../docs/back/profile.md)
- [バージョン履歴](../docs/version/README.md)

プレビューの編集結果は画面内だけに反映します。永続保存・Googleログイン・DB接続の検証には通常起動を使用してください。モバイルの認証にはプラットフォームごとのFirebase設定も必要です。
