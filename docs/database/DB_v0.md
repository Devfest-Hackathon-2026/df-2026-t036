# EWOCURU ハッカソン版 DB・API仕様書


- **整理日**：2026-11-10。現行コードのDB・API契約。公開版は [版別履歴](../version/README.md) を参照。
- **対象**：Flutter Webのハッカソン版。コード実装と、本番環境への適用・動作確認は区別する。
- **技術**：Firebase Authentication（Google）、Firestore、Cloud Storage、Cloud Run / FastAPI、Firebase Hosting
- **正本**：DB・APIと機能範囲は本書を優先。総合仕様書も同じ範囲にそろえる。

## 0. 採用範囲と保存階層

| 機能 | 今回の方針 |
|---|---|
| ログイン | 画面のGoogleログイン。招待コード・メール許可リストなし |
| 表示名 | 初回登録時にサーバーでランダム生成。以降は本人がプロフィール編集で変更可能 |
| プロフィール文・SNSリンク | 任意の自己紹介とHTTPSリンクをusers/{uid}へ保存し、本人更新・公開項目のみ取得 |
| お題・ピン | 5スロット、タグ、ピン5件、7日／30日のルールを維持 |
| 作品 | JPEG/PNG/HEIC/HEIF入力（WebP入力非対応）、WebP完成画像、1人1お題1回、受信者限定、送信から7日 |
| 受信箱 | 自動更新、作品の未読・既読を維持 |
| 実績 | お題数・描いた数・いいね数、描いた履歴画面を維持 |
| 画像保存 | 変換・正規化した1枚を表示・ダウンロードに共用。サムネイルなし |
| 再試行 | 同じ画面内で再試行可。タブを閉じた後のアップロード再開なし |
| 通知 | ベル・通知一覧・通知データ・通知APIを作らない |
| 退会 | 退会画面・退会API・自動退会処理は実装対象外 |
| メンテナンス | サーバー設定で通常APIを停止。管理画面は作らない |

```text
Firebaseプロジェクト
├─ Authentication
│   └─ Googleアカウント（uid）
├─ Firestore
│   ├─ users/{uid}                  ランダム表示名・状態・累計・自己紹介・SNSリンク
│   │   └─ drawnHistory/{submissionId} 描いた履歴（別文書）
│   ├─ userSlots/{uid}              掲載枠（独立文書）
│   │   └─ slots                   文書内map。サブコレクションではない
│   ├─ userPins/{uid}               ピンID配列（独立文書）
│   ├─ ideas/{ideaId}               お題
│   ├─ artworks/{submissionId}      受信作品情報
│   ├─ artworkSubmissions/{submissionId} 投稿予約・完了結果
│   ├─ artworkUploads/{token}       試行の保存先・回収管理
│   └─ cleanupState/{job}           内部処理のリース・カーソル
└─ Cloud Storage
    └─ artworks/{submissionId}/{token}.webp（非公開の完成画像）
```

上記のコレクションとusers配下の履歴で構成する。通知・publicProfiles・jobs・idempotencyKeysは設けない。公開プロフィールはusers文書の許可項目だけを公開API DTOで返す。自己紹介・SNSリンクは任意項目で、未設定時は空値として扱う。プロフィール画像・代表作品は画像保存・公開範囲の設計が別途必要なため、このAPIには含めない。サブコレクション更新だけでは親usersは更新されないが、累計更新や認可の読み取りによる競合は残る。


## 1. 業務ルール（確定）

1. Googleログイン後、初回登録APIでusers・userSlots・userPinsを初期化する。招待確認はしない。1人がお題主と描き手を兼ねる。
2. お題は投稿から7日未満だけTL掲載。同時掲載は最大5件。7日到達・手動削除で枠が空く。お題本文・タグは投稿後編集不可。
3. 7日未満は登録済みactiveユーザーが閲覧でき、未送信の他人はピン不要で作品送信可能。7日以上30日未満の新規送信には現在も保持する事前ピンが必要。
4. お題主と過去に送信した描き手は、未削除のお題を全期間、本人の履歴経由で閲覧可能。これは閲覧の例外であり、自己送信・再送信は許可しない。
5. ピンは最大5件。自分のお題へのピン不可。7日以降の新規ピン不可。解除後に7日以上なら再ピン不可。30日・お題削除で無効化する。
6. 30日で新規受付終了。お題自体は自動削除しない。お題単体の手動削除は論理削除で、本文の通常閲覧と新規送信を停止する。
7. 描き手1人につき1お題1作品。送信確定後の取消・差替え不可。送信後の画像・受信作品詳細は受信者だけが閲覧・保存できる。
8. 作品・画像は送信確定から7日。お題が受付終了・論理削除されても作品自身の期限まで維持する。作品手動削除は受信者だけができる。
9. いいねは受信者のみ、作品の有効期間内に1回だけ。取消不可。作品削除後も履歴・描いた数・付いたいいねを維持する。
10. 作品既読は初回の詳細表示時に記録する。一覧取得・自動更新だけでは既読にしない。通知機能とは別で、通知は今回作らない。

### 時刻と期限境界

- 時刻はサーバーUTC。FirestoreはTimestamp、APIはRFC 3339のUTC文字列（末尾Z）。1日は24時間。
- `now < publishedUntil`：TL掲載。`publishedUntil <= now < acceptUntil`：ピン限定受付。`now >= acceptUntil`：受付終了。
- 作品は `expiresAt > now` かつ `deletedAt == null` の場合だけ有効。定期削除の遅延にかかわらずAPIが拒否する。
- お題削除・作品削除・停止状態はAPIで毎回確認。表示済み画像も期限到達時に画面から外す。端末に保存済みの画像は回収できない。

## 2. コレクション定義

### プロフィールAPI

| Method / path | 認証 | 用途 |
|---|---|---|
| `GET /api/v1/me` | Google認証・active | 本人情報に自己紹介 `bio` と `socialLinks` を含める |
| `PATCH /api/v1/me/profile` | Google認証・active | `nickname`・`bio`・SNSリンク一式を更新。nicknameは省略可、部分フィールド・未知フィールドは受け付けない |
| `GET /api/v1/me/artworks/{submissionId}/artist-profile` | Firebase認証・作品の受信者 | 描き手が送信時に公開を選んだ作品に限りプロフィールを返す |

`nickname` は1〜24文字、前後空白を除去し、空欄と制御文字を拒否する。省略された場合は従来値を維持する。`bio` は最大300文字、SNSリンクは最大5件。リンク種別は `x` / `instagram` / `pixiv` / `youtube` / `other`。全てHTTPSのみとし、各既知SNS種別は対応ホスト名を検証する。`other` は任意のHTTPSホストを許す。各リンクの `label` は1〜40文字、URLは最大2048文字。同一URLの重複は末尾スラッシュと大文字小文字を正規化して拒否する。集計値は更新不可。

**作品ごとのプロフィール公開**: 作品送信時に描き手が受信者へのプロフィール公開を選ぶ。作品文書に `artistProfileVisibleToRecipient` を保存し、既定値はfalse。falseの場合はInbox DTOの `artistId` と `artistNickname` をnullにする。受信者限定取得APIは作品文書のrecipientId・公開選択・期限・削除状態を検証する。一般公開のユーザープロフィール取得APIは設けない。

プロフィール画像・代表作品の登録APIは未実装。Cloud Storageでの公開方式、画像制限、公開同意、古い画像の削除方式を決めてから追加する。

全てlowerCamelCase。UIDはFirebase Auth UID。文書IDは保存パスの一部であり、各文書への重複保存は必須ではない。

### 2.1 users/{uid}

| フィールド | 型 | 意味 |
|---|---|---|
| nickname | string | 初回登録でサーバーがランダム生成。その後は本人がプロフィールAPIで更新可能 |
| status | string | active / suspended。deletingは今回導入しない |
| ideaCount | integer | 未削除のお題累計。30日経過で減らさず、手動削除時に1回だけ減算 |
| drawnCount | integer | 確定送信累計。作品削除後も維持 |
| likesReceived | integer | 描き手が受けたいいね累計。取消・作品削除による減算なし |
| bio | string | 任意の公開自己紹介。最大300文字 |
| socialLinks | array | 任意のHTTPS SNSリンク。最大5件 |
| createdAt | timestamp | 登録時刻 |

表示名の初期生成：固定の単語リストとランダムな文字・数字を組み合わせる。重複を許可し、識別はUIDで行う。Googleの本名・メールから生成しない。登録を再送しても名前・カウンターを再生成しない。プロフィール編集後は変更後の名前を表示する。

メールはAuthにのみ保持。本人にはMe DTOを返す。プロフィールDTO（UID・nickname・bio・socialLinks）は、描き手が送信時に公開を許可した作品の受信者に限り返す。お題一覧のownerNicknameはAPIがまとめて名前を付加する。受信箱のartistNicknameは公開許可がある場合だけ返す。一覧上の名前はプロフィール編集時点と異なる場合があり、プロフィール画面はAPIから最新値を取得する。

### 2.2 userSlots/{uid}

`maxSlots: integer = 5`、`slots: map`。slot_0～slot_4は空Map `{}` または `{ ideaId: string, expiresAt: timestamp }`。expiresAtはお題のpublishedUntilと一致する。期限切れはDB整理を待たず空き扱い。古いお題を削除する際は、枠内のideaIdが一致する場合だけ解放する。

### 2.3 userPins/{uid}

`maxPins: integer = 5`、`pinnedIdeaIds: string[] = []`。重複なし、pinnedAtなし。新規登録・上限判定はトランザクションで行い、無効なお題を上限から除外する。解除は対象お題が欠損・期限切れでも可能とする。

### 2.4 ideas/{ideaId}

| フィールド | 型 | 意味 |
|---|---|---|
| ownerId | string | 投稿者UID |
| title | string | 必須、1～40文字 |
| description | string | 必須、1～600文字 |
| tags | string[] | 任意入力、保存時は配列。最大5件・各20文字は暫定 |
| createdAt | timestamp | 投稿時刻 |
| publishedUntil | timestamp | createdAt＋7日 |
| acceptUntil | timestamp | createdAt＋30日 |
| deletedAt | timestamp / null | 初期null、手動削除時に設定 |

ideaIdはFlutterが操作ごとにUUID v4を生成し、同じ操作の再送では同じIDと入力を使用する。作成済みなら所有者・正規化済み入力を照合して既存結果を返す。入力違いは409、他人のIDは404。論理削除済みのIDは復活させない。

### 2.5 artworks/{submissionId}

| フィールド | 型 | 意味 |
|---|---|---|
| artistId | string | 描き手UID |
| recipientId | string | 受信者UID |
| sourceIdeaId | string | 元のお題ID |
| sourceIdeaSnapshot | map | title / description / tags / ownerIdの送信時点の複製 |
| artistProfileVisibleToRecipient | boolean | 描き手が送信時に選択。既定false、未設定の旧作品もfalseとして扱う |
| storagePath | string | 正規化済み画像1枚の非公開パス |
| storageBucket | string | 画像の保存バケット |
| contentType | string | image/webp |
| visionPolicyVersion | string | 審査ポリシーの版 |
| purgeAt | timestamp / 未設定 | 画像削除成功後に設定するTTL用時刻 |
| liked | boolean | 初期false、trueへの変更だけ許可 |
| readAt | timestamp / null | 必須。初期null、受信者の初回詳細表示時に設定 |
| createdAt | timestamp | 送信確定時刻 |
| expiresAt | timestamp | createdAt＋7日 |
| deletedAt | timestamp / null | 初期null、受信者の手動削除時に設定 |

サムネイルは作らない。画像の検証・審査・完成形式と受付上限は [画像処理](../back/image-processing.md) に従う。

### 2.6 users/{uid}/drawnHistory/{submissionId}

`artistId: string`、`ideaId: string`、`submittedAt: timestamp`、`lastLiked: boolean = false`。artistIdはパスのuidと一致。作品と同じsubmissionIdを使う。画像削除後も履歴画面・累計・再投稿防止に使い、画像URLやStorageパスは保存しない。削除済みのお題は参照不可カードで表示する。

submissionIdは描き手×お題で一意にする。生成方式は `UTF8(artistId) + 0x00の1バイト + UTF8(ideaId)` のSHA-256小文字16進。IDはサーバーで生成し、入力IDのNULを許可しない。

### 2.7 artworkSubmissions/{submissionId}

status、token、digest（入力バイト列のSHA-256）、expiresAt、artistProfileVisibleToRecipientを保持する。処理中はprocessing、確定後はcommittedとresult（submissionId / submittedAt）を記録する。未完了の予約は30分有効。同じ確定済み画像の再送は保存結果を返し、異なる画像で置換しない。

### 2.8 artworkUploads/{token}

submissionId、token、bucket、storagePath、status、expiresAt、artistProfileVisibleToRecipientを保持する。画像保存前に作成し、試行ごとに別パスを使用する。processing / committed / abandoned等の回収状態はAPIが管理する。正確な状態遷移は [作品投稿API](../back/artwork-submission.md) を参照。

### 2.9 cleanupState/{job}

pins、artworkExpiry等の内部処理がリース・カーソル・完了時刻を保持する。孤立画像走査ではページ位置を保存する。一般利用者は直接操作できない。

### サーバー管理項目

usersには投稿・削除の頻度制限用時刻配列も保存する。クライアントから更新させず、Me DTOにも含めない。上限は [投稿制限](../back/post-rate-limits.md)、[定期削除](../back/cleanup.md) を参照。

## 3. API・認可の共通方針

Firestoreのクライアント直接読み書きをRulesで拒否し、データ操作・画像送信・取得をFastAPIへ集約する。通常APIはGoogle IDトークン、登録済みactive状態、所有者／受信者・期限を検証する。内部APIは専用サービスアカウントのOIDCで認証する。

パスは /api/v1 配下。/healthは例外で認証・外部接続が不要。メンテナンス時は通常APIに503を返し、healthと認証付き内部整理は継続する。入力・UTC・ページング・エラー形式は [共通基盤](../back/backend-foundation.md) に従う。

## 4. 現行API一覧

| Method | パス（/api/v1配下） | 内容 |
|---|---|---|
| POST | /users/register | 本文なし。初回201、再送200 |
| GET | /me | 本人の名前・状態・累計・bio・socialLinks |
| PATCH | /me/profile | 本人のプロフィール更新 |
| GET / POST | /ideas | TL取得・お題作成 |
| GET / DELETE | /ideas/{ideaId} | 詳細取得・本人の論理削除 |
| GET | /me/ideas、/me/slots、/me/pins | 本人のお題履歴・枠・ピン |
| POST / DELETE | /pins/{ideaId} | ピン追加・解除 |
| POST | /artworks | multipart直接投稿。初回201、同一確定画像の再送200 |
| GET | /me/artworks/inbox | 受信作品一覧 |
| GET | /me/artworks/{submissionId}/artist-profile | 公開選択した作品の受信者へ作者情報 |
| GET | /me/drawn-history | 描いた履歴 |
| GET | /artworks/{submissionId}/image | 受信者限定の画像取得 |
| POST | /artworks/{submissionId}/read | 初回既読、再送で時刻を維持 |
| POST | /artworks/{submissionId}/like | 受信者の取消不可いいね |
| DELETE | /artworks/{submissionId} | 受信者の論理削除、204 |
| POST | /vision-demo | 判定だけのデモ。作品保存なし |
| POST | /internal/cleanup | ピン整理 |
| POST | /internal/artwork-cleanup | アップロード試行・孤立画像回収 |
| POST | /internal/artwork-expiry-cleanup | 作品画像削除・purgeAt設定 |

お題の入出力は [詳細API](ideas-api.md)、プロフィールは [プロフィール仕様](../back/profile.md)、投稿・再送は [投稿API](../back/artwork-submission.md) を参照。端末保存は取得済みbytesを使用し、専用のダウンロードAPIは設けない。画像応答はprivate, no-storeとし、公開URLへリダイレクトしない。

## 5. 再試行・トランザクション

お題作成はクライアント生成のideaIdと正規化済み入力で再送を判定する。作品は描き手とお題で一意のsubmissionId、入力digest、予約・試行状態で判定する。確定済みの同一画像は結果だけを返し、異なる画像は409。処理中の並行送信も409。クライアントへ試行tokenを発行して再開させる方式ではない。

作品の予約・確定時に資格を検証する。Firestore確定では作品・描いた履歴・drawnCount・完了状態を一度だけ更新する。いいねでは作品・履歴・likesReceivedを一度だけ更新する。Storage操作はFirestoreトランザクション外で行う。

DB確定の成否が不明なら状態を確認し、確定済み画像は削除しない。未確定試行を回収可能な状態へ変更してから削除する。保存失敗・回収失敗は追跡文書を残し、内部APIで再試行する。

## 6. 一覧・削除・運用

一覧はlimit（既定20、最大50）、不透明cursorを受け取り、items / nextCursor / serverTimeを返す。認可・期限はページごとに再評価する。スロット・ピンは固定上限なのでページングしない。

受信箱は表示中・前面の間だけ180秒ごとに先頭ページを更新する。背景・画面離脱で停止し復帰時に取得。成功時は後続ページと旧カーソルを破棄し、失敗時は表示を保持する。古い通信結果を混在させない。一覧取得では既読にせず、画像表示成功後にreadを呼ぶ。

作品はdeletedAt設定・expiresAt到達で即時取得不可。内部期限処理が画像を削除し、成功した文書だけpurgeAtを設定する。Firestore TTLはartworks.purgeAtで非同期に文書を削除する。expiresAtにTTLを設定しない。履歴・累計は維持する。Scheduler・TTL・IAMは [定期削除](../back/cleanup.md) に従い環境ごとに設定・検証する。

一覧の複合インデックスはfirestore.indexes.jsonを適用する。停止ユーザーは通常API操作を拒否する。機能のコード実装、ローカルテスト、本番相当の外部サービス検証は別々に確認する。

## 7. 未対応・今後の判断

プロフィールのアイコン・代表作品、一般公開のプロフィールURL、退会・通知・ブロックは今回の対象外。導入時には公開同意・画像の権利・容量・審査・保持期間・削除を定義する。受信者限定作品を代表画像へ自動転用しない。

管理者による停止・削除の運用、実験データの最終保持期間、負荷に応じた上限・監視・Scheduler間隔は環境側で決める。usersを物理削除する場合、サブコレクションは自動削除されないため別途対応する。
