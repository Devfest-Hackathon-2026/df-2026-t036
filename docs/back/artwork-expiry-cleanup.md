# 受信作品の期限削除とFirestore TTL

実装仕様: [`back/artwork-expiry-cleanup-plan.md`](../../back/artwork-expiry-cleanup-plan.md)

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
