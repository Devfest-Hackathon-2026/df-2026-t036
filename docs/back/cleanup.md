# 定期削除・回収とTTL

ピン整理・アップロード回収・作品期限削除の運用手順です。内部APIごとにSchedulerを設定します。TTLは作品文書の削除だけを担当します。

- POST /api/v1/internal/cleanup：ピン整理
- POST /api/v1/internal/artwork-cleanup：アップロード試行・孤立画像回収
- POST /api/v1/internal/artwork-expiry-cleanup：作品期限削除・TTLへの引渡し


## 期限切れピンの定期整理

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

ピン整理はお題・作品・累計を変更しません。作品期限削除とアップロード回収は別の内部APIで実装しています。




## 受信作品の期限削除とFirestore TTL

実装仕様: [`docs/back/cleanup.md`](cleanup.md)

この運用手順は、Cloud Runへ新しいAPIをデプロイした後に適用する。Scheduler・TTLの設定を行うまでは自動削除は有効にならない。

## 削除の流れ

- 作品は送信確定から7日でAPI上の閲覧対象外となる。
- 受信者の削除要求は`deletedAt`を記録し、その時点からAPI上で閲覧不可になる。
- `POST /api/v1/internal/artwork-expiry-cleanup`が最大100件ずつ候補を処理する。
- Storage画像の削除に成功した場合だけ、作品文書に`purgeAt`を設定する。
- Firestore TTLが`artworks.purgeAt`を基準に文書を非同期削除する。
- Storage削除に失敗した文書には`purgeAt`を設定しない。次回の定期処理で再試行する。

`expiresAt`をFirestore TTLに設定してはならない。TTLはStorage画像を削除せず、期限到達時の即時削除も保証しない。

## Firestore TTLの設定

対象のGoogle CloudプロジェクトとFirestoreデータベースを確認してから実行する。Firestore TTLポリシーは`firestore.indexes.json`の複合インデックスとは別設定である。

```powershell
$ProjectId = 'YOUR_PROJECT_ID'
gcloud config set project $ProjectId
gcloud firestore fields ttls update purgeAt --collection-group=artworks --enable-ttl --project=$ProjectId
gcloud firestore fields ttls list --project=$ProjectId
```

一覧で`collectionGroup=artworks`、`field=purgeAt`、状態`ACTIVE`を確認する。反映中は`CREATING`等になることがあるため、`ACTIVE`になるまで本番のTTL完了とみなさない。

## Cloud Schedulerの登録

既存の`CLEANUP_SERVICE_ACCOUNT`と`CLEANUP_AUDIENCE`設定を使う。Cloud Runの実行サービスアカウントにはFirestoreの読書きと作品バケットのオブジェクト削除権限が必要。SchedulerサービスアカウントはCloud Run呼出権限と、OIDCトークン発行権限を持つ。

```powershell
$ProjectId = 'YOUR_PROJECT_ID'
$Region = 'asia-northeast1'
$Service = 'illustration-exchange-api'
$ServiceUrl = 'https://YOUR_CLOUD_RUN_SERVICE_URL'
$SchedulerAccount = 'YOUR_CLEANUP_SERVICE_ACCOUNT'

gcloud scheduler jobs create http artwork-expiry-cleanup `
  --project=$ProjectId --location=$Region --schedule='*/5 * * * *' `
  --time-zone='Asia/Tokyo' `
  --uri="$ServiceUrl/api/v1/internal/artwork-expiry-cleanup" `
  --http-method=POST `
  --oidc-service-account-email=$SchedulerAccount `
  --oidc-token-audience=$ServiceUrl `
  --attempt-deadline=300s --max-retry-attempts=3 `
  --min-backoff=30s --max-backoff=300s

gcloud scheduler jobs run artwork-expiry-cleanup --project=$ProjectId --location=$Region
```

環境に既存の同名ジョブがある場合は新規作成せず、設定を確認して`gcloud scheduler jobs update http`で更新する。サービスの`CLEANUP_SERVICE_ACCOUNT`と`CLEANUP_AUDIENCE`がScheduler設定と一致することを確認する。

## 導入確認

### 先に行う簡易確認（データ削除なし）

次のコマンドでTTLポリシーとSchedulerの設定を確認できる。これは設定確認であり、作品の削除処理が成功した証明ではない。

```powershell
$ProjectId = 'YOUR_PROJECT_ID'
$Region = 'asia-northeast1'

gcloud firestore fields ttls list --project=$ProjectId --collection-group=artworks
gcloud scheduler jobs describe artwork-expiry-cleanup --project=$ProjectId --location=$Region `
  --format="yaml(state,schedule,timeZone,httpTarget.uri,httpTarget.oidcToken,status,lastAttemptTime)"
```

- TTL一覧で`artworks`の`purgeAt`が`ACTIVE`であることを確認する。
- Scheduler出力で`state: ENABLED`、想定するURL、OIDCサービスアカウント、audienceを確認する。
- `gcloud scheduler jobs run ...`は実行を開始する操作。実際のHTTP成功はCloud Schedulerの実行履歴またはCloud Runログで確認する。
- 期限削除APIを含む新しいCloud Runリビジョンがまだデプロイされていない場合、ジョブの起動だけでは新機能を検証できない。先に対象リビジョンへデプロイする。

1. ステージングで期限切れ作品を作成し、内部APIを手動実行する。
2. Storage画像が削除され、文書に`purgeAt`が入ったことを確認する。
3. Firestore TTLの`ACTIVE`状態を確認し、TTL処理後に作品文書が消えることを確認する。TTLは非同期なので即時消去を期待しない。
4. Storage削除権限を一時的に外したテストでは、文書が残り`purgeAt`が付かないこと、権限復旧後の再実行で完了することを確認する。
5. Schedulerの実行履歴とCloud Runログで成功・失敗・再試行を確認する。応答は件数だけとし、UID・作品ID・Storageパスをログや応答に出さない。
6. 本番では少量から開始し、Scheduler失敗、未処理件数、`purgeAt`付き文書の残留を監視する。

TTLポリシーまたはSchedulerが未設定・失敗しても、APIの期限判定は維持される。これは物理削除が完了したことを意味しないため、障害を通知して復旧する。


---

## アップロード試行・孤立画像の回収

POST /api/v1/internal/artwork-cleanup は期限切れ・失敗した試行を最大100件、保存先オブジェクトも最大100件ずつ巡回します。確定済み作品から参照される画像は削除せず、未確定の孤立画像だけをgeneration一致条件付きで削除します。詳細は [作品投稿API](artwork-submission.md) を参照してください。

ピン整理と同じCLEANUP_SERVICE_ACCOUNT・CLEANUP_AUDIENCEを使用し、本文・クエリは不要です。scanned / scannedObjects / failed / hasMoreを返します。hasMoreがtrueなら再実行します。定期実行する場合は作品期限削除のScheduler登録例で、ジョブ名をartwork-upload-cleanup、URIの末尾を /api/v1/internal/artwork-cleanup に変更します。

## 手動削除・再試行・監視

- 受信者の DELETE /api/v1/artworks/{submissionId} はdeletedAtを設定します。本人による削除済み作品の再送は204です。他人・欠損・期限切れは共通404、利用者ごとの1時間20回の制限超過は429です。
- 作品期限整理はcleanupState/artworkExpiryの5分リース・カーソルを使用し、最大100文書ずつ走査します。別の処理中は409です。
- StorageのNotFoundは削除成功として扱います。削除失敗・purgeAt更新失敗では文書を残し、再試行します。
- 画像参照と削除対象状態を再確認し、Storage操作はFirestoreトランザクション外で行います。
- 描いた履歴・累計は維持します。ログ・応答にUID・作品ID・Storageパスを出しません。
- TTL・Scheduler・IAMは環境ごとの適用と実測が必要です。削除失敗・未処理量・purgeAt付き文書の残留、大量削除を監視します。
