# 期限切れピンの定期整理

`POST /api/v1/internal/cleanup` は1回につき最大100件の `userPins` 文書を文書ID順に走査します。30日の受付期限に到達したお題、論理削除・欠損したお題、自己ピン、不正ID・重複を除去します。7日のTL掲載期限だけではピンを削除しません。投稿者の一時停止だけでも物理削除しません。

ピン文書・参照先のお題をトランザクション内で再読込し、利用者の追加・解除と競合した場合はSDKの再試行で再評価します。お題・作品・累計は変更しません。通常APIの期限判定は整理の完了を待たずに有効です。

## 内部認証

以下の2項目をAPIに設定します。両方未設定なら内部APIは実行を拒否し、片方だけの設定では起動エラーになります。認証を省略するローカル用スイッチはありません。

```dotenv
CLEANUP_SERVICE_ACCOUNT=pin-cleanup@YOUR_PROJECT_ID.iam.gserviceaccount.com
CLEANUP_AUDIENCE=https://YOUR_CLOUD_RUN_SERVICE_URL
```

AuthorizationのBearerトークンについてGoogleの署名・発行者・有効期限・audienceを検証し、検証済みemailが設定したサービスアカウントと完全一致する場合だけ実行します。一般利用者のFirebase IDトークンでは実行できません。証明書取得障害は503です。メンテナンス中も内部認証を要求します。

Cloud Schedulerは専用サービスアカウントのOIDCトークンを発行してHTTP対象を呼び出せます。audienceはSchedulerとAPIの両方で同じ値を明示します。[Google Cloud公式手順](https://docs.cloud.google.com/scheduler/docs/http-target-auth)、[Google Authの検証仕様](https://google-auth.readthedocs.io/en/latest/reference/google.oauth2.id_token.html)。

## Cloud Schedulerへの登録

以下はPowerShellでの登録例です。APIをデプロイした後に実行してください。この手順を記載しただけでは定期実行は有効になりません。サービスアカウントが既にあれば作成は不要です。ジョブ作成者にはそのサービスアカウントを使用する権限が必要です。

```powershell
$PinCleanupProject = 'YOUR_PROJECT_ID'
$PinCleanupRegion = 'asia-northeast1'
$PinCleanupService = 'illustration-exchange-api'
$PinCleanupUrl = 'https://YOUR_CLOUD_RUN_SERVICE_URL'
$PinCleanupAccount = "pin-cleanup@${PinCleanupProject}.iam.gserviceaccount.com"

gcloud services enable cloudscheduler.googleapis.com --project=$PinCleanupProject
gcloud iam service-accounts create pin-cleanup --project=$PinCleanupProject --display-name='Pin cleanup scheduler'
gcloud run services add-iam-policy-binding $PinCleanupService --project=$PinCleanupProject --region=$PinCleanupRegion --member="serviceAccount:$PinCleanupAccount" --role=roles/run.invoker
# 通常API用の既存環境変数を維持して内部認証設定を追加する。
gcloud run services update $PinCleanupService --project=$PinCleanupProject --region=$PinCleanupRegion --update-env-vars="CLEANUP_SERVICE_ACCOUNT=$PinCleanupAccount,CLEANUP_AUDIENCE=$PinCleanupUrl"
gcloud scheduler jobs create http pin-cleanup --project=$PinCleanupProject --location=$PinCleanupRegion --schedule='*/5 * * * *' --time-zone='Asia/Tokyo' --uri="$PinCleanupUrl/api/v1/internal/cleanup" --http-method=POST --oidc-service-account-email=$PinCleanupAccount --oidc-token-audience=$PinCleanupUrl --attempt-deadline=300s --max-retry-attempts=3 --min-backoff=30s --max-backoff=300s
# 登録後に手動実行し、Schedulerの成功とCloud Runのログを確認する。
gcloud scheduler jobs run pin-cleanup --project=$PinCleanupProject --location=$PinCleanupRegion
```

新規ジョブは5分間隔です。100件を超える場合は次回実行で続きから処理し、末尾に達したら先頭へ戻ります。1周の目安は `ceil(userPins文書数 / 100) × 5分` です。新しい文書が走査位置より前に追加された場合は次の周回で処理します。利用規模に応じて実行間隔を調整してください。

## リース・応答・再試行

Admin SDK専用の `cleanupState/pins` に `cursor`、`leaseOwner`、`leaseUntil`、`lastCompletedAt` を保存します。Firestore Rulesの全直接アクセス拒否はそのまま適用されます。5分のリースで多重実行を防ぎ、各ユーザーの更新でも所有権と有効期限を確認します。処理が停止した場合はリース失効後に再開できます。

成功したページだけカーソルを進めます。途中失敗時は走査位置を維持し、次回同じページを再処理します。部分的に整理済みでも再実行は安全です。走査位置の文書が消えても続行できます。別インスタンスが実行中の場合は409 `CLEANUP_BUSY` を返します。

```json
{"scannedUsers":100,"updatedUsers":12,"removedPins":18,"hasMore":true}
```

上記は各回の例です。利用者IDやお題IDは応答・整理ログに含めません。成功ログは `pin_cleanup_completed`、失敗は `pin_cleanup_failed`、リース解放失敗は `pin_cleanup_release_failed` です。障害時はSchedulerの再試行とCloud Runログを確認してください。リクエスト本文・クエリは不要で、付けると422になります。

作品の7日期限削除・一時アップロード画像回収は、このピン整理とは別途実装します。
