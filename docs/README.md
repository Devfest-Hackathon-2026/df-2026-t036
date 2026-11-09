# ドキュメント案内

日常の開発では、環境構築・起動方法・総合仕様を入口にしてください。

| 分類 | 文書 |
|---|---|
| 初回準備・日常操作 | [環境構築](environment.md)、[起動・停止](startup.md) |
| サービス全体 | [総合仕様](specification.md) |
| DB・API契約 | [DB仕様](database/DB_v0.md)、[お題・ピンAPI](database/ideas-api.md) |
| API基盤・認証 | [共通基盤・認可](back/backend-foundation.md)、[Firebase設定](back/firebase-auth.md)、[投稿制限](back/post-rate-limits.md) |
| 画像・プロフィール | [作品投稿API](back/artwork-submission.md)、[画像処理・審査](back/image-processing.md)、[プロフィール](back/profile.md) |
| 運用 | [CI/CD・Hosting・ブランチ](ci-cd.md)、[定期削除・TTL](back/cleanup.md) |
| Flutter | [デザイン](flont/design.md)、[受信画像保存](flont/received-artwork.md) |
| 法務 | [利用規約](legal/terms-test.md)、[プライバシーポリシー](legal/privacy-policy-v0.md) |
| 版別更新履歴 | [バージョン一覧](version/README.md) |

## 管理方針

- 起動コマンドはstartup、初回設定はenvironmentを正本とします。各READMEは案内に留めます。
- backはAPI実装・認証・定期処理、flontは画面・端末側の動作、databaseはDB・API契約です。
- architectureは構成図です。HTML・SVG・PNGは同じ図の表示形式として扱い、すべてを別の仕様書として更新しません。
- 統合した文書の旧設計・未決事項は各文書内の記録として保持しています。「実装前」「案」は当時の記載であり、現行の説明と区別します。
- 法務のreview文書は運営内の確認事項です。アプリに表示する本文とは分けて残します。
