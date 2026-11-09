# CI/CD・公開・ブランチ運用

テストとCloud Run、Firebase Hosting、ブランチ運用をまとめています。CIはmain・develop向けPRと両ブランチの更新で実行します。環境の起動とは区別してください。

## 統合元：ci-cd.md

# GitHub Actions: テストとCloud Runデプロイ

PRおよびmain更新時に、Python 3.11のpytest・pip check、Flutter 3.47.9の解析・テスト・Webビルド、Linux/amd64のDockerビルドと起動確認を実行します。Flutterはlockfileが要求するSDKに合わせています。実際の.local.envやFirebase設定、Google Cloud認証はCIでは不要です。サンプルFirebase設定をコピーしたWebビルドは検証用で、Hostingには公開しません。

## 自動デプロイの有効化

初期状態はテストのみです。GitHubのリポジトリ変数 `CLOUD_RUN_DEPLOY_ENABLED` を `true` にすると、mainへのpush（PRマージ含む）とmainからの手動実行で、全チェック成功後にCloud Runへデプロイします。PRのコードにはGCP権限を渡しません。

次を事前設定してください。このPRだけではGCPリソース・IAM・GitHub変数の作成は行いません。

1. GCPの課金、Cloud Run / Artifact Registry / IAM Credentials / Security Token Service APIを有効化し、Docker用Artifact Registryリポジトリを作成する。
2. Cloud Runサービスを初期作成し、実行用サービスアカウント、GOOGLE_CLOUD_PROJECT、ARTWORK_BUCKET、CORS_ORIGINS等の環境変数、必要なSecret Manager参照、公開・認証設定を用意する。実行主体にFirestore・Storage・Vision等の必要な権限を与える。GitHubに.local.envや認証JSONを登録しない。
3. デプロイ専用サービスアカウントを用意する。対象Cloud Runサービスにroles/run.developer、対象Artifact Registryリポジトリにroles/artifactregistry.writer、Cloud Run実行用アカウントに対するroles/iam.serviceAccountUserを付与する。
4. GitHub OIDC用のWorkload Identity PoolとProviderを設定する。issuerは `https://token.actions.githubusercontent.com`。google.subject、attribute.repository_id、attribute.repository_owner_id、attribute.ref、attribute.environmentを対応するassertionにマッピングする。Provider条件でリポジトリID・所有者ID・mainブランチ・production環境を制限する。リポジトリIDは `gh api repos/outsidewhite/-Illustration-exchange --jq .id` で確認する。
5. 該当リポジトリIDのprincipalSetに対して、デプロイ専用アカウントのroles/iam.workloadIdentityUserを付与する。条件を緩めて他リポジトリやPRのトークンを許可しない。
6. GitHubのproduction Environmentを作成し、デプロイ可能ブランチをmainに限定する。必要ならレビュー承認ルールを設定する。

GitHub Settings → Secrets and variables → Actions → Variablesに以下を登録します（有効化フラグを含めて**リポジトリ変数**に登録）。

|変数|値の例|
|---|---|
|GCP_PROJECT_ID|利用するプロジェクトID|
|GCP_REGION|asia-northeast1|
|ARTIFACT_REGISTRY_REPOSITORY|illustration-exchange|
|CLOUD_RUN_SERVICE|illustration-exchange-api|
|GCP_WORKLOAD_IDENTITY_PROVIDER|projects/番号/locations/global/workloadIdentityPools/プール/providers/プロバイダー|
|GCP_DEPLOY_SERVICE_ACCOUNT|デプロイ用アカウント@プロジェクト.iam.gserviceaccount.com|
|CLOUD_RUN_DEPLOY_ENABLED|準備完了後にtrue|

初回はActionsのTest and deployからmainを選んで手動実行し、productionのURLでログイン・投稿・受信を確認してください。main以外の手動実行ではデプロイしません。デプロイにはCIで検証したDockerイメージをそのまま使用し、コミットSHAのタグでArtifact Registryに保存します。既存の環境変数・IAM公開設定・実行用アカウントは変更しません。Scheduler登録やHostingデプロイは含みません。

## マージ条件とロールバック

mainのブランチ保護でBackend tests、Flutter checks、Docker build and smoke testを必須にすることを推奨します。ワークフローの追加だけではブランチ保護は有効になりません。投稿制限のPRも、マージ前にmainを取り込むか更新してCIを実行してください。

失敗時は各ジョブのログを確認してください。デプロイを止めるにはCLOUD_RUN_DEPLOY_ENABLEDをfalseにします。公開後の問題はCloud Runで前の正常なリビジョンへトラフィックを戻して対応します。イメージとリビジョンは自動削除しないため、Artifact Registryの保持方針は別途設定してください。デプロイ後の本番APIの外部疎通・負荷テストは別途必要です。

公式資料: [GitHub OIDC認証](https://github.com/google-github-actions/auth#setting-up-workload-identity-federation)、[デプロイパイプラインのWIF](https://docs.cloud.google.com/iam/docs/workload-identity-federation-with-deployment-pipelines)、[Flutter Action](https://github.com/subosito/flutter-action)。

---

## 統合元：firebase-hosting.md

# Firebase Hostingへの公開

公開ディレクトリは `flont/build/web` です。Firestoreのルール・インデックスは既存設定を維持し、Hostingだけを明示して公開します。

リポジトリ直下から実行します。

```powershell
# APIの公開先をビルド時に指定し、ローカル設定は上書きしない。
Set-Location flont
flutter build web --dart-define=API_BASE_URL=https://illustration-exchange-api-c3ovewncia-an.a.run.app
Set-Location ..
# ビルド済みのWebアプリだけを公開する。
npx firebase-tools deploy --only hosting --project project-025f8d03-50f2-4a97-a05
```

Firebase CLIのログインと、正しいFirebaseプロジェクトのWeb公開設定を含む `flont/firebase-config.local.json` が必要です。このJSONはビルドに同梱されるため、サービスアカウントの秘密鍵などを入れないでください。DEV_PREVIEWは指定せず、通常の認証を使います。

公開先は https://ewocuru.web.app です。Cloud RunのCORS_ORIGINSにはこのURLと対応するfirebaseapp.comのURLを登録します。Firebase AuthenticationのGoogleプロバイダーと承認済みドメインも確認してください。

公開後はGoogleログイン、お題投稿、作品送受信を実際のアカウントで確認します。ヘルスチェックや未認証での401確認だけでは、Cloud Run実行用サービスアカウントのFirestore・Storage・Vision権限は検証できません。

Cloud Run実行用サービスアカウントは `illustration-api-runtime@project-025f8d03-50f2-4a97-a05.iam.gserviceaccount.com` です。プロジェクトにはDatastore User、Firebase Authentication Viewer、Service Usage Consumer、作品バケットにはStorage Object Userを付与しています。サービスアカウント秘密鍵は発行していません。

公開先サイトIDは `ewocuru` です。`firebase.json` の hosting.site で指定します。旧サイトは削除していません。新ドメインの `ewocuru.web.app` と `ewocuru.firebaseapp.com` をFirebase Authenticationの承認済みドメインにも登録します。


---

## 統合元：branch-workflow.md

# ブランチ運用

機能開発・修正は作業ブランチからdevelopへのPRで取り込み、リリース時は同じリポジトリのdevelopからmainへPRを作成します。デフォルトブランチはdevelopです。

```text
feature/*、fix/* → develop → main
```

developは削除・強制pushを禁止し、PRとCI成功を必須にします。mainも削除・強制push・直接pushを禁止し、PR・CI成功・送信元チェックを必須にします。承認レビューの必要人数は0人とし、一人での運用も可能にします。バイパス権限は設定しません。ただし、管理者は保護ルール自体を変更できます。

mainの送信元チェックはpull_request_targetで動作し、PR側のコードをcheckout・実行せず、リポジトリとブランチ名を確認します。別ブランチからのPR作成を禁止するものではなく、必須チェックでマージを防ぎます。

既存CIはmain・develop向けPRと両ブランチへのpushで実行します。本番デプロイは従来どおりmainだけで、CLOUD_RUN_DEPLOY_ENABLEDによる有効化も維持します。GitHubの保護設定はワークフローを置くだけでは有効にならないため、Rulesets側にも登録します。

リリースPRは履歴を維持する通常のマージコミットでマージしてください。長期ブランチ間でsquash/rebaseを繰り返すと差分の比較が難しくなるためです。必要に応じてmainの変更をdevelopへ取り込みます。
