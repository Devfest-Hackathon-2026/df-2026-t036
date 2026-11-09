# 定期削除・回収とTTL

ピン整理と作品期限削除の運用手順をまとめています。最初の2節は実装後の運用、末尾は元の設計記録です。設計記録の「追加候補」「実装前」は当時の状態であり、未実装の判定には使いません。作品期限整理のコードは back/app/artwork_expiry.py です。

- POST /api/v1/internal/cleanup：ピン整理
- POST /api/v1/internal/artwork-cleanup：アップロード試行・孤立画像回収
- POST /api/v1/internal/artwork-expiry-cleanup：作品期限削除・TTLへの引渡し

## 統合元：pin-cleanup.md

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


---

## 統合元：artwork-expiry-cleanup.md

# 受信作品の期限削除とFirestore TTL

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

<details>
<summary>作品期限削除の元の実装計画・確認項目を開く</summary>

## 統合元：artwork-expiry-cleanup-plan.md

# 作品画像の期限削除 実装計画

- 状態: 実装中（API・定期処理コードあり。テスト・クラウド設定・本番確認は未完了）
- 対象: 受信済み作品のStorage画像とFirestore作品文書の期限・手動削除整理
- 関連資料: [`docs/database/DB_v0.md`](../database/DB_v0.md)、[`docs/back/cleanup.md`](cleanup.md)

## 1. 目的と現状

作品画像は送信確定時刻から7日後に閲覧期限を迎える。現在のコードでは、期限後の受信箱表示・既読・いいね・画像取得を拒否する。また、`POST /api/v1/internal/artwork-cleanup` は期限切れ・失敗したアップロード試行や孤立画像を回収し、`POST /api/v1/internal/cleanup` は無効なピンを整理する。

一方、受信作品そのものについて、期限切れまたは受信者による削除後に完成画像をStorageから削除し、その後Firestoreの`artworks/{submissionId}`文書を削除する処理はまだない。本計画はその実装を追加する。

## 2. 目標と対象外

### 目標

- `expiresAt <= now` または `deletedAt != null` の受信作品を、StorageとFirestoreから安全に物理削除する。
- 期限到達後は整理処理を待たず、既存のAPI認可により作品を即時に利用不可とする。
- Storage削除失敗時にFirestore文書とStorage参照を残し、次回に再試行できるようにする。
- バッチ上限、多重実行防止、継続カーソル、内部認証、ログを備える。
- 処理の一部が失敗しても、再実行で破損や二重処理が起きない。
- 攻撃者が作品IDを推測・入手しても、他人の作品を削除できず、内部定期処理を起動できない。
- 受信者向けの手動削除を実装し、論理削除から物理削除までを同じ再試行可能な流れに統一する。

### 対象外

- 期限切れアップロード試行・審査用一時画像・孤立オブジェクトの回収方式変更。既存`/artwork-cleanup`を継続する。
- 描いた履歴、いいね累計、利用者データの削除。
- 退会・ユーザー全データ削除。

## 3. 削除条件と順序

定期処理の対象は次のOR条件とする。

1. `expiresAt <= now`（送信確定時刻から7日）
2. `deletedAt != null`（将来追加する受信者の手動削除）

候補文書ごとに最新状態を再確認し、以下の順序で処理する。

1. Firestoreから候補を取得する。クエリ時刻はサーバーUTCとする。
2. 候補の`storageBucket`と`storagePath`を読み、文書の期限・削除状態を再検証する。
3. Storageの対象オブジェクトを削除する。オブジェクトが既にない場合は成功として扱う。
4. Storage削除成功後に限り、作品文書にTTL用`purgeAt`を設定する。
5. Firestore TTLが`purgeAt`に基づいて文書を非同期に物理削除する。
6. Storage削除または`purgeAt`設定が失敗した場合は`purgeAt`を設定せず、文書を保持して再試行する。

### Firestore TTLの採用方針

Firestore TTLによる`artworks`文書の自動削除を**採用する**。ただし、閲覧期限の`expiresAt`をTTLフィールドに直接指定してはならない。TTLはCloud Storageの画像を削除せず、期限ちょうどの削除も保証しないためである。

TTL専用日時フィールド`purgeAt`を作品文書に追加する。定期処理は期限切れまたは手動削除済み作品を確認し、Storage画像を削除した後に限り、文書を再取得して対象参照が変わっていないことを確認して`purgeAt = server_now`を設定する。Firestore TTLポリシーはコレクショングループ`artworks`の`purgeAt`に設定する。

Storage削除失敗時は`purgeAt`を設定せず、文書と画像パスを保持して再試行する。`purgeAt`設定後にTTL削除が遅れても、画像はすでに削除済みであり、APIは期限または`deletedAt`によりアクセスを拒否する。TTLはFirestore文書の最終整理であり、閲覧停止やStorage削除の代替ではない。削除時刻は保証されないため、「7日後に閲覧できなくなる」と「その時刻に全データが消える」は区別して案内する。

期限切れ・手動削除済みの文書は、既存APIがすでに受信箱・画像・既読・いいねから拒否することを維持する。掃除対象の作品が走査中に更新された場合も、Storage削除直前に現在の文書を再読し、状態と参照先を確認する。完成画像は確定後に差し替えない設計だが、削除対象確認と文書削除の間に状態変更があり得るため、削除後の文書削除では対象の`storagePath`等が同じであることを再確認する。別画像を指す文書は削除しない。

## 4. APIと既存クリーンアップとの関係

既存の内部認証は`cleanup_identity`（Google OIDCトークン、許可サービスアカウント、audienceを検証）を再利用する。

追加候補:

- `POST /api/v1/internal/artwork-expiry-cleanup`
- 空の本文・クエリのみ許可
- 認証設定がない場合は実行拒否
- Cloud Scheduler専用サービスアカウントからのみ呼び出す

この専用エンドポイントを選ぶ理由は、既存`/internal/cleanup`がピン整理、`/internal/artwork-cleanup`がアップロード回収という別の対象を担うため。将来、既存の画像回収と同じエンドポイントへ統合する判断も可能だが、同一リクエストの実行時間・障害影響・独立した再試行を分けるため、初期実装では独立させる。

`POST /api/v1/internal/artwork-cleanup` は現行どおり一時画像・孤立画像回収を担当する。実行頻度は別々に設定できるようにする。

### 4.1 受信者向け手動削除API（実装対象として確定）

- `DELETE /api/v1/artworks/{submission_id}` を追加する。
- Firebase IDトークンで認証し、activeな利用者であることを確認する。
- `artworks/{submission_id}`の`recipientId`が認証UIDと一致する場合だけ削除を受け付ける。描き手・別ユーザー・未認証利用者は削除できない。
- ID不存在、他人の作品、期限切れ、削除済みは共通の`404 RESOURCE_UNAVAILABLE`とし、作品の存在や受信者を応答から推測できないようにする。
- URLに含まれるsubmission ID以外に、Storage bucket/path、削除条件、ユーザーIDをクライアントから受け取らない。
- APIは画像を同期削除せず、Firestore文書に`deletedAt`を初回だけ設定して204を返す。以後、既存の画像・受信箱・既読・いいねAPIは削除済み作品を拒否する。内部定期処理が画像を削除し、成功後に`purgeAt`を設定してTTLへ引き渡す。
- 同じ要求の再送は冪等に扱う。削除済みであっても受信者本人の再送なら成功応答とするか、情報非開示の404とするかをコード契約で一意に固定し、テストする。推奨は受信者本人には204を返す。
- 削除要求では作品メタデータ、描いた履歴、いいね累計を削除・減算しない。期限削除と同じく、履歴・累計は維持する。

## 5. Firestore走査・継続・多重起動

- 作品コレクションを上限付きで走査する。推奨初期値は1回100文書。
- 期限条件・削除条件をFirestoreのクエリとインデックスで実現できるか確認する。ORクエリが複合インデックスやSDK制約で扱いにくい場合は、期限切れと手動削除を別クエリで走査し、同一文書の重複を排除する。
- 成功したページのみカーソルを進める。途中失敗時は同じ位置を再処理する。
- `cleanupState/artworkExpiry`等の共有状態文書にリース所有者・期限・カーソル・最終成功時刻を保存する。
- リースの取得・更新・解放をFirestoreトランザクションで行い、別インスタンスによる同時実行を防ぐ。期限切れリースは次回実行で引き継げる。
- 走査末尾に達したら次回は先頭へ戻る。`hasMore`を返し、処理残量を運用ログから把握できるようにする。
- Storage操作はFirestoreトランザクション内で行わない。
- TTLポリシーはコレクショングループ`artworks`の`purgeAt`に設定する。`firestore.indexes.json`とは別のFirestore TTL設定として環境へ適用し、反映を確認する。
- 新規作品文書の`purgeAt`は未設定またはnullとする。`expiresAt`やアップロード試行期限をTTLフィールドに流用しない。
- `purgeAt`はStorage削除完了後にだけ書き込むサーバー管理フィールドとし、一般利用者から変更できないようにする。
- TTLは非同期・ベストエフォートで、`purgeAt`設定と文書消失の時刻は一致しない。

## 6. エラー処理・冪等性・安全性

- Storageの`NotFound`は削除成功として扱う。
- Storageの一時障害・権限エラーではFirestore文書を削除しない。
- Storage削除後にのみ`purgeAt`を設定し、Firestore TTLで作品文書を自動削除する。TTLはStorage画像を削除しない。
- `expiresAt`をTTLフィールドに指定しない。Storage削除前に文書がTTLで消える構成は禁止する。
- `purgeAt`設定に失敗した場合は文書を残し、次回処理で画像状態を再確認して再試行する。
- Firestore文書が既にない候補は、画像パスが安全に特定できる場合のみ孤立画像回収へ委ねる。任意のパスを推測して削除しない。
- `storageBucket`が空の場合は設定済みの作品バケットを使用する。設定がなく、文書にもバケットがない候補は失敗として残し、警告ログを出す。
- 文書削除前に、再取得した文書の期限・削除状態・バケット・パスが対象スナップショットと一致することを確認する。
- 作品投稿処理・画像取得処理との競合を想定し、削除済み作品を復活させない。確定済み作品の画像は投稿の再送処理で再作成されないことを維持する。
- ログと応答にユーザーID、作品ID、画像パス、画像内容を出さない。全体件数と失敗数、エラー種別を記録する。
- HTTP応答に処理済み件数・失敗件数・継続有無だけを含める。

### 6.1 脅威モデルと必須防御

| 想定する攻撃 | 必須の防御・期待動作 |
|---|---|
| 未認証の削除リクエスト | 認証依存で拒否。Firestore/Storage操作を開始しない。 |
| 他ユーザー・描き手によるsubmission ID指定 | 認証UIDとrecipientIdをサーバー側で比較し、本人以外は共通404。 |
| ID列挙・存在確認 | 不存在・権限なし・期限切れ・削除済みを同一応答にそろえ、レスポンスに内部ID・パスを含めない。 |
| 繰り返し・大量削除要求 | 1作品の削除は冪等。既存ユーザー単位の投稿/API制限に加え、手動削除API専用のレート制限を実装し、過剰要求は429で拒否する。 |
| 任意Storageパス・バケット指定 | 入力項目を設けず、Firestore上のサーバー管理フィールドからのみ対象を決める。 |
| 一般ユーザーから内部掃除APIを起動 | OIDC署名・issuer・audience・許可メールを検証し、専用Scheduler主体以外を拒否。Firebase利用者トークンでは起動できない。 |
| 複数Scheduler・再送 | Firestoreリースで単一実行に制限。409/5xxとScheduler再試行でも処理を重複適用できる。 |
| Storage削除失敗を利用した文書消失 | 画像削除成功またはNotFoundの確認前にFirestore作品文書を削除しない。 |
| 競合中のパス差し替え | 文書を再取得し、bucket/path/削除対象状態の一致を確認。別参照なら処理を中断し、誤ったオブジェクト・文書を消さない。 |
| 運営/IAM資格情報侵害 | Cloud Run実行主体を最小権限に限定し、ユーザー向け削除APIと内部掃除権限を分離する。監査ログと異常件数アラートを設定する。 |

アプリケーションの防御は、Cloudプロジェクト管理者や侵害済みの高権限IAM主体による操作を単独で防止するものではない。IAM最小権限、監査ログ、バックアップ、アラートを環境側にも必須とする。

## 7. Cloud Scheduler運用

- Cloud Schedulerから専用OIDCサービスアカウントで内部APIを呼ぶ。
- 既存の`CLEANUP_SERVICE_ACCOUNT`と`CLEANUP_AUDIENCE`認証設定を利用する。用途別に別サービスアカウントを採用する場合は設定・IAM・運用資料を追加する。
- 期限到達後の削除遅延はScheduler実行間隔で決まる。初期案は5分間隔とし、運用コスト・API負荷を見て確定する。
- `attempt-deadline`はStorage処理を含むバッチが収まる時間を確保する。Schedulerの再試行を有効にし、409（別処理中）と一時的な5xxを再試行可能にする。
- Cloud Run実行サービスアカウントにはFirestore読書きと対象バケットのオブジェクト削除権限が必要。
- Cloud Scheduler実行主体には、専用サービスアカウントを使う権限とCloud Run呼出権限が必要。
- Scheduler登録はデプロイとは別工程である。設定手順を追加し、作成後に手動実行してCloud Runログと応答を確認する。

## 8. 実装作業の分割

1. **削除API契約**：`DELETE /api/v1/artworks/{submission_id}`の認証、受信者限定、共通404、冪等応答を確定し、OpenAPIとコードへ反映する。
2. **手動削除の論理状態**：トランザクションで受信者・作品状態を検証し、`deletedAt`を一度だけ設定する。投稿時の状態・集計・履歴は変更しない。
3. **定期処理の候補検索**：期限切れ／手動削除済みの検索、ページカーソル、必要インデックスを実装する。
4. **同時実行制御**：`cleanupState/artworkExpiry`のリース・カーソル取得と解放を実装する。
5. **1作品の物理削除**：最新状態と参照先確認 → Storage削除 → 同一参照確認 → `purgeAt`設定 → TTLによる文書削除を確認。
6. **バッチAPI**：1回100件上限、部分失敗、再実行可能な結果集計、内部OIDC認証を実装する。
7. **手動削除APIのレート制限**：他ユーザー・未認証拒否とあわせて単体テストを追加する。投稿回数制限とは用途を分け、利用者単位で乱用を抑止する。
8. **セキュリティ・障害テスト**：未認証、第三者、ID差し替え、列挙、連続要求、Storage権限エラー、Firestore削除失敗、同時実行、カーソル再開、参照先変更競合を検証する。
9. **TTLポリシー**：コレクショングループ`artworks`の`purgeAt`だけをTTL対象にし、Firestore環境へ適用する。`expiresAt`はTTL対象にしない。
10. **インデックス・CI**：`firestore.indexes.json`とCI検証を更新し、関連pytestを必須チェックにする。
11. **最小権限と監視**：Cloud Run実行SAのFirestore/Storage権限を確認し、監査ログ、削除失敗、TTL対象文書の残留を監視する。
12. **Scheduler運用**：OIDC専用SA、Cloud Run呼出権限、実行間隔、再試行、タイムアウトの手順を追加し、デプロイ後に手動実行する。
13. **段階導入**：ステージングで画像削除・`purgeAt`設定・TTLによる文書削除を実測後、本番で小さく開始する。

## 9. 受け入れ条件

- `expiresAt == now`を含め、期限到達作品は画像取得・受信箱・既読・いいねから即時に利用できない。
- 期限前の作品と、削除マークのない作品は掃除対象にならない。
- Storage画像削除後にだけ`purgeAt`が設定され、Firestore TTLで作品文書が非同期削除される。
- `expiresAt`にTTLポリシーが設定されておらず、Storage削除前に作品文書が消えない。
- TTLポリシーが対象Firestore環境に適用済みで、ステージングで非同期削除を実測している。
- 画像がすでに存在しない場合もFirestore文書を整理できる。
- Storage削除失敗時にFirestore文書・参照先が残り、再実行で削除できる。
- Storage削除後に`purgeAt`設定が失敗しても、文書が残り再実行で安全に完了する。
- Firestore文書の参照先が処理中に変わった場合、新しい参照先・文書を誤削除しない。
- 1回の処理件数を超えず、継続カーソルで全件を順次処理する。
- 同時起動では一方だけが処理し、リース失効後に再開できる。
- Scheduler OIDC認証のない呼び出しは拒否される。
- Cloud Runログに個人・作品・Storageパスを含めず、成功・部分失敗・完全失敗を判別できる。
- 描いた履歴、いいね累計、利用者文書には影響しない。
- 未認証・第三者の手動削除は拒否され、第三者に対象の存在を明かさない。
- 手動削除APIは連続要求の制限を持ち、利用者が任意のStorageパスを削除対象にできない。
- 内部定期処理は正規のScheduler OIDC主体以外から実行できない。
- Storage削除権限を持つ実行主体は限定され、失敗・大量削除の監査記録と通知が確認できる。

## 10. 実装前に確定する運用値

設計上の処理方針は既存の`DB_v0.md`で定義済み。以下は実装時の設定値として確定する。

| 項目 | 初期提案 | 備考 |
|---|---:|---|
| バッチ件数 | 100文書 | 既存ピン・アップロード整理と揃える。負荷試験で調整可能にする。 |
| Scheduler間隔 | 5分 | 期限後の削除遅延とコストの折衷案。 |
| リース期間 | 5分 | Schedulerの最大実行時間以下を目安にし、延長または再取得を実装する。 |
| 失敗再試行 | 次回Scheduler実行 | 個別失敗は文書を保持し、成功済みの他作品処理は戻さない。 |
| Firestore TTLフィールド | `artworks.purgeAt` | Storage削除成功後にだけ設定する。 |
| 削除ログ保持 | Cloud Loggingの既定保持方針 | アプリ側に追加の個人情報・画像情報を保存しない。 |

この提案値を実装の初期値として採用する。TTLポリシーの環境適用、Cloud Schedulerの有効化、本番IAM変更、一般利用者への公開は環境側の設定として別途実施し、ステージング検証後に行う。

## 11. 関連コード・資料

- `back/app/artworks.py`: 受信箱・既読・いいね・画像取得と期限判定
- `back/app/artwork_submission.py`: 作品確定、アップロード試行回収、孤立画像回収
- `back/app/cleanup.py`: 内部OIDC認証、リース方式のピン整理
- `back/app/config.py`: 内部クリーンアップ認証設定
- `docs/database/DB_v0.md`: 作品期限・削除順序の基準設計
- `docs/back/cleanup.md`: Cloud Scheduler OIDC登録の既存例
- `docs/back/cleanup.md`: TTL・Schedulerの環境設定と導入確認手順

</details>
