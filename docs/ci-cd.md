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