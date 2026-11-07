# お絵描きマッチングサービス ハッカソン版 DB・API仕様書

> 現行サーバー実装: 画像は `POST /api/v1/artworks` でFastAPIへ直接送信し、再検証・Vision承認後にWebPで正式保存する。以下のprepare/commit・一時アップロード方式は従来案。現行の投稿・再送・回収契約は [作品投稿API](../back/artwork-submission.md) を参照。

- **版**：v0.9（2026-11-05、細部整理案採用）
- **対象**：Flutter Webのハッカソン版。設計仕様であり、実装完了を示さない。
- **技術**：Firebase Authentication（Google）、Firestore、Cloud Storage、Cloud Run / FastAPI、Firebase Hosting
- **表記**：確定＝合意済みの機能範囲、実装案＝実装時に調整可能な詳細、未決定＝実装前に確定する値
- **正本**：DB・APIと機能範囲は本書を優先。総合仕様書も同じ範囲にそろえる。

## 0. 採用範囲と保存階層

| 機能 | 今回の方針 |
|---|---|
| ログイン | 画面のGoogleログイン。招待コード・メール許可リストなし |
| 表示名 | 初回登録時にサーバーでランダム生成し保存。変更機能なし |
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
│   ├─ users/{uid}                  ランダム表示名・状態・累計
│   │   └─ drawnHistory/{submissionId} 描いた履歴（別文書）
│   ├─ userSlots/{uid}              掲載枠（独立文書）
│   │   └─ slots                   文書内map。サブコレクションではない
│   ├─ userPins/{uid}               ピンID配列（独立文書）
│   ├─ ideas/{ideaId}               お題
│   ├─ artworks/{submissionId}      受信作品情報
│   └─ uploadSessions/{uploadId}    アップロード管理
└─ Cloud Storage
    ├─ 一時アップロード画像
    └─ 正規化済み作品画像（表示・保存に共用）
```

B案を維持し、Firestore直下6種類とusers配下の履歴1種類で構成する。通知・publicProfiles・jobs・idempotencyKeysは設けない。サブコレクション更新だけでは親usersは更新されないが、累計更新や認可の読み取りによる競合は残る。

構造図： [HTML](database_v0.html) ／ [PNG](database_v0.png) ／ [SVG](database_v0.svg)

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

全てlowerCamelCase。UIDはFirebase Auth UID。文書IDは保存パスの一部であり、各文書への重複保存は必須ではない。

### 2.1 users/{uid}

| フィールド | 型 | 意味 |
|---|---|---|
| nickname | string | 初回登録でサーバーがランダム生成して固定 |
| status | string | active / suspended。deletingは今回導入しない |
| ideaCount | integer | 未削除のお題累計。30日経過で減らさず、手動削除時に1回だけ減算 |
| drawnCount | integer | 確定送信累計。作品削除後も維持 |
| likesReceived | integer | 描き手が受けたいいね累計。取消・作品削除による減算なし |
| createdAt | timestamp | 登録時刻 |

表示名の実装案：固定の単語リストとランダムな文字・数字を組み合わせる。重複を許可し、識別はUIDで行う。Googleの本名・メールから生成しない。登録を再送しても名前・カウンターを再生成しない。表示形式は未決定。

メールはAuthにのみ保持。本人にはMe DTO、他人にはUIDとnicknameだけを公開する。お題一覧のownerNickname・受信一覧のartistNicknameへAPIがまとめて名前を付加し、1カードずつのAPI呼び出しを避ける。

### 2.2 userSlots/{uid}

`maxSlots: integer = 5`、`slots: map`。slot_0～slot_4はnullまたは `{ ideaId: string, expiresAt: timestamp }`。expiresAtはお題のpublishedUntilと一致する。期限切れはDB整理を待たず空き扱い。古いお題を削除する際は、枠内のideaIdが一致する場合だけ解放する。

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
| storagePath | string | 正規化済み画像1枚の非公開パス |
| liked | boolean | 初期false、trueへの変更だけ許可 |
| readAt | timestamp / null | 必須。初期null、受信者の初回詳細表示時に設定 |
| createdAt | timestamp | 送信確定時刻 |
| expiresAt | timestamp | createdAt＋7日 |
| deletedAt | timestamp / null | 初期null、受信者の手動削除時に設定 |

thumbnailPathは作らない。FlutterでJPEG・PNG等を可能な範囲で事前圧縮し、FastAPIで実データを検証、メタデータ除去後WebPへ正規化し、Vision SafeSearchで審査する。WebPは完成画像の保存形式とする。入力形式・Web HEIC対応、圧縮品質、最大画素数・安全容量上限は実機・Cloud Run・Vision上限を確認して決める。

### 2.6 users/{uid}/drawnHistory/{submissionId}

`artistId: string`、`ideaId: string`、`submittedAt: timestamp`、`lastLiked: boolean = false`。artistIdはパスのuidと一致。作品と同じsubmissionIdを使う。画像削除後も履歴画面・累計・再投稿防止に使い、画像URLやStorageパスは保存しない。削除済みのお題は参照不可カードで表示する。

submissionIdは描き手×お題で一意にする。実装案は `UTF8(artistId) + 0x00の1バイト + UTF8(ideaId)` のSHA-256小文字16進。IDはサーバーで生成し、入力IDのNULを許可しない。

### 2.7 uploadSessions/{uploadId}

`artistId, ideaId, submissionId, status, tempPath, objectGeneration, createdAt, expiresAt, committedAt` を持つ。時刻はtimestamp、committedAtは初期null。objectGenerationはstring/null。statusはpending / committed / expired。有効期間は暫定30分。uploadIdはAPIがランダム生成する。

同じ画面内の再試行は同じuploadIdを使う。タブ終了後のアップロード再開・進捗復元は実装しない。新しい画面では送信済み履歴を確認し、未確定なら新規prepareから始める。放置セッションと画像のサーバー回収は残す。

## 3. API・認可の共通方針

Firestoreの全クライアント読み書きをRulesで拒否し、データ操作はFastAPIへ集約する。Admin SDKはRulesを通らないため、APIがIDトークン・active状態・所有者／受信者・期限を検証する。AuthのGoogleログインとprepare発行の期限付き一時画像書込だけは別経路。完成画像の直接アクセスは禁止。

メンテナンスはサーバー設定（実装案：MAINTENANCE_MODE）で切り替え、通常API・画像API・prepare・commitへ503 MAINTENANCEを返す。設定変更後の反映手順・全インスタンスへの適用を確認する。/healthと内部の期限削除は停止対象外。発行済み一時アップロード権限や配信済みデータの回収は保証しない。メンテナンス管理画面は作らない。

JSONはUTF-8、未知フィールド・不正な型を拒否。入力の前後空白を除去し、必須判定・長さ検証を行う。文字数はUnicodeコードポイント数とする実装案。タグは完全一致の重複を排除する。全APIパスは /api/v1 配下。/healthだけプレフィックス外。

## 4. API一覧と主要入出力

| HTTP | パス | 入力・処理 | 成功 |
|---|---|---|---|
| POST | /users/register | 本文なし。Google認証UIDで初期化・ランダム名生成 | 初回201、再送200、Me |
| GET | /me | 本人の名前・状態・3種の累計 | 200、Me |
| GET | /ideas | 有効なTLを新着順に取得 | 200、一覧 |
| POST | /ideas | ideaId / title / description / tags | 初回201、同じ要求の再送200、Idea |
| GET | /ideas/{ideaId} | お題詳細と閲覧・送信資格 | 200、Idea |
| DELETE | /ideas/{ideaId} | 本人の論理削除・枠解放・累計減算 | 204、論理削除済みの再送も成功 |
| GET | /me/ideas | 本人の未削除お題履歴 | 200、一覧 |
| GET | /me/slots | 掲載枠・空き枠 | 200、maxSlots / slots / serverTime |
| GET | /me/pins | 有効なピンとお題 | 200、maxPins / items / serverTime |
| POST | /pins/{ideaId} | 他人のお題をピン。既存の有効ピンは追加しない | 204 |
| DELETE | /pins/{ideaId} | ピン解除。未登録・欠損でも成功 | 204 |
| POST | /artworks/prepare | ideaId / contentType / byteSize | 201、uploadId / uploadUrl / method / requiredHeaders / expiresAt |
| POST | /artworks/commit | uploadId。画像検証・送信資格再確認 | 初回201、同じuploadIdの再送200、submissionId / submittedAt |
| GET | /me/artworks/inbox | 本人の有効な受信作品、自動更新対象 | 200、一覧 |
| POST | /artworks/{submissionId}/read | 受信者の初回既読、再送は初回時刻を維持 | 200、readAt |
| GET | /artworks/{submissionId}/image | 受信者限定で正規化画像を配信 | 200、画像 |
| GET | /artworks/{submissionId}/download | 同じ正規化画像を端末保存 | 200、画像 |
| POST | /artworks/{submissionId}/like | 受信者の取消不可いいね | 200、submissionId / liked: true |
| DELETE | /artworks/{submissionId} | 即時不可視化、画像削除は定期処理 | 204 |
| GET | /me/drawn-history | 本人の履歴・参照可能なお題・最終いいね | 200、一覧 |
| POST | /internal/cleanup | 内部認証で作品・一時画像・期限切れピンを整理 | 実装時に応答を固定 |

名前変更・通知・退会のAPIは作らない。画像APIはCache-Control: private, no-store、保存APIはContent-Disposition: attachmentを付ける。公開URLや署名URLへのリダイレクトを返さない。

### 実装進捗（2026-11-06）

以下はこのリポジトリのFastAPIコード上の実装状況。**実装済みはコードがある状態を示し、実Firebase／Firestore／Storageを使った本番相当の動作確認完了を意味しない。**

| 状態 | API | 実装内容・残作業 |
|---|---|---|
| 実装済み | `GET /health` | 起動確認。認証・外部サービス接続を必要としない。 |
| 実装済み | `POST /users/register`、`GET /me` | Google IDトークン検証、初回登録、本人情報と累計取得。 |
| 実装済み | `/ideas`、`/me/ideas`、`/me/slots`、`/me/pins`、`/pins/{ideaId}` | お題の作成・閲覧・削除、枠、ピンの取得・操作。Firestore処理を含む。 |
| 準備済み | `ArtworkPrepareInput` | JPEG/PNG/HEIC/HEIFと正の申告サイズ（512 MiBの高い安全上限）の入力契約。Storageアップロード発行APIは未実装。 |
| 実装済み・未動作確認 | `GET /me/drawn-history` | 描いた履歴と参照可能なお題、いいね状態をページ取得。 |
| 実装済み・未動作確認 | `GET /me/artworks/inbox` | 有効な受信作品のメタデータ、描き手名、既読・いいね状態をページ取得。画像は扱わない。 |
| 実装済み・未動作確認 | `POST /artworks/{submissionId}/read` | 受信者の初回既読時刻を冪等に記録。Flutterは画像表示成功後に呼ぶ。 |
| 実装済み・未動作確認 | `POST /artworks/{submissionId}/like` | 受信者のいいねを一度だけ反映し、描き手の履歴と累計を更新。 |
| 未実装 | `POST /artworks/prepare` | 送信資格・入力画像条件を確認し、一時アップロード用セッションと制限付きアップロード先を発行する。Cloud Storage連携が必要。 |
| 未実装 | `POST /artworks/commit` | アップロード実体・形式・サイズ・送信資格を再検証し、画像を正規化して作品・描いた履歴・累計・セッション状態を一度だけ確定する。Cloud StorageとFirestoreの回復可能な連携が必要。 |
| 未実装 | `GET /artworks/{submissionId}/image` | 受信者・期限・削除状態を確認して画像を認証付きで返す。Cloud Storage連携が必要。公開URLや長期有効URLは返さない。 |
| 未実装 | `GET /artworks/{submissionId}/download` | 画像APIと同じ認可を適用し、正規化画像を添付ファイルとして返す。Cloud Storage連携が必要。 |
| 未実装 | `DELETE /artworks/{submissionId}` | 受信者のみ作品を即時不可視化する。画像の物理削除は定期整理で再試行できるようにする。 |
| 未実装 | `POST /internal/cleanup` | 内部呼び出しを認証し、期限切れ作品・一時セッション・一時画像・無効ピン等を上限付きで整理する。Cloud Storage連携とScheduler等の呼出設定が必要。 |

未実装の作品送信・画像取得・削除・期限整理は、メタデータAPIとは別の作業段階。特にprepare/commitおよびimage/download/cleanupはCloud Storageを伴う。read/like・履歴・受信箱は画像バイト列を扱わない。Flutter側では画像が表示できてからreadを呼び、Storage実体の受け渡しとAPI認可を分離する。

現状、描いた履歴・受信箱・既読・いいねの追加コードはテスト実行環境の問題でpytest未実行であり、Firebase実データを用いた統合確認も未完了。Firestore複合インデックスをデプロイする環境では、同梱の `firestore.indexes.json` も適用する。

Meはuid / nickname / status / ideaCount / drawnCount / likesReceived。Ideaはお題の保存項目とideaId / ownerNickname / canPin / canSubmit。InboxItemはsubmissionId / artistId / artistNickname / sourceIdeaId / sourceIdeaSnapshot / liked / readAt / createdAt / expiresAt。Storageパスは返さない。履歴はsubmissionId / ideaId / submittedAt / lastLiked / idea / ideaAvailability、参照不可ならideaはnull。

### 一覧・受信箱の自動更新（確定方針）

一覧はlimit（既定20、最大50）と不透明なcursorを受け取り、items / nextCursor / serverTimeを返す。同時刻の順序は文書ID DESC。期限・認可はページごとに再評価。スロット・ピンは固定上限のためページングしない。

受信箱は表示時に取得し、表示中・タブが前面の間だけ3分（180秒）間隔で先頭ページを再取得する。非表示・画面離脱で停止、復帰時に即取得。リクエストを重ねず、失敗時は待ち時間を延ばす。先頭ページの取得成功時に一覧をそのページで置き換え、既存の後続ページ・旧カーソルを破棄する。追加読込は新しいnextCursorから開始する。更新失敗時は既存一覧を維持する。古い追加読込の遅延応答が新しい一覧へ混ざらないよう、取得世代を確認して破棄する。期限切れは画面から除外する。手動更新も可能。WebSocket・SSE・Firestoreリスナーは使わない。

一覧更新で既読化しない。詳細画面で画像を表示できた後にread APIを呼ぶ。失敗時は同じAPIを再試行し、readAtの初回値を上書きしない。既読要求も受信者・有効期限を検証する。受信箱・描いた履歴はlimit（既定20、最大50）と認証UIDに結び付いたカーソルでページングする。

### エラー・再試行

共通形式は `{ error: { code, message, details, requestId } }`。401は認証不正、403は停止中、404 RESOURCE_UNAVAILABLEは不存在・資格なし・削除済み・期限切れ。認可済みの受付終了・上限・重複は409。容量413、形式415、入力422、制限429、一時障害・メンテナンス503。一時障害はRetry-Afterを尊重する。不存在・資格なし・削除済み・期限切れの画面表示は共通の「参照できません」とし、応答から存在を区別しない。通信障害は「読み込みに失敗しました／再試行」として分ける。

通信断後も同じideaId / uploadIdで再試行する。別uploadIdで送信履歴があれば409 ALREADY_SUBMITTED。同じuploadIdの確定済み再送は履歴から結果だけを返し、画像や作品を再生成しない。セッション整理後は404となり得るため、履歴で送信結果を確認する。

## 5. トランザクションと画像回復

| 操作 | 原子的に確認・更新する対象 |
|---|---|
| 初回登録 | usersの不存在確認、ランダム名保存、枠・ピン初期化。再送で初期化し直さない |
| お題作成 | ユーザー状態、ID重複、空き枠、ideas作成、ideaCount加算 |
| お題削除 | deletedAt初回設定、一致する枠のみ解放、ideaCount一度だけ減算 |
| ピン操作 | userPins、登録時のお題資格、上限・重複確認 |
| 作品確定 | 両当事者active、お題・ピン・期限、履歴不存在、作品・履歴作成、drawnCount加算、セッション確定 |
| いいね | 受信者・作品期限、likedの初回変更、描き手の履歴lastLikedとlikesReceived加算 |
| 作品既読 | 本人・作品の有効性、readAtがnullなら初回時刻設定 |

必要な読み取りを全て先に行う。時刻は各再試行で再評価する。StorageはFirestoreトランザクションの対象外なので、変換・画像保存・削除をトランザクション関数内で実行しない。

1. prepareで資格を確認し、セッション・書込専用の一時アップロード先を発行。資格は予約しない。
2. commitで実体を検証し、世代番号を固定してWebPへ変換する。SafeSearch対象となるstaging WebPを非公開保存し、Vision APIへgs:// URIを渡す。HEIC/HEIFをM1で受け付ける場合はサーバーでデコード可能なことをDocker/Linux実機サンプルで検証。
3. SafeSearch通過後、uploadIdから決定する完成パスに、未存在条件でWebPを1枚copyする。保存時にセッション識別子・入力generation・staging generation・変換仕様versionをサーバー管理メタデータとして記録する。完成物保存後にDB確定が失敗した場合、同じuploadIdの再試行では既存完成画像のメタデータ・世代とセッションを照合し、一致する検証済み画像を上書きせず再利用する。並行保存で未存在条件が失敗した場合も、保存済み画像を再取得して同じ照合を行う。不一致なら確定せず409 UPLOAD_CONFLICTとし、上書きしない。入力世代は一度固定したら再試行で変更しない。
4. 完成画像を再利用する場合も、Firestoreで資格・pending状態・期限・固定した入力世代を再確認し、作品・履歴・累計・committedを確定する。committedの再送は画像再処理より先に判定し、送信結果だけを返す。
5. 期限切れセッションはexpiredへ遷移してから掃除し、commitと競合させる。committedが参照する完成画像は消さず、入力一時画像と審査staging画像だけ回収する。
6. 未確定セッションは1回の掃除直後に消さず、実行中処理・発行済み書込権限の終了を待つ猶予期間中、繰り返し掃除する。猶予期間・処理上限を実装前に決定し、遅れて保存された画像も回収する。

受信作品はdeletedAt設定時またはexpiresAt到達で即時に取得不可。定期処理は画像を削除してから作品文書を消す。失敗時は文書・パスを残して再試行。既にない画像は成功扱い。作品文書や掃除前のセッションへ直接TTLを設定しない。多重起動を避け、失敗をサーバーログに残す。

## 6. 検索・認可・運用

| 用途 | 対象と条件 |
|---|---|
| TL | ideas：deletedAtがnull、publishedUntil > now、新着順 |
| 本人のお題 | ideas：ownerId == uid、deletedAtがnull、新着順 |
| 受信箱 | artworks：recipientId == uid、deletedAtがnull、expiresAt > now、新着順 |
| 履歴 | users/{uid}/drawnHistory：submittedAt DESC |
| 掃除 | artworks：deletedAtまたはexpiresAt、uploadSessions：statusとexpiresAt |

表は論理条件。実際の不等号条件・並び順をSDKで検証し、必要なインデックスを設定ファイルへ保存する。APIが認証UIDから本人のパスを決め、クライアント指定UIDは操作主体にしない。通知の検索・TTLは不要。停止ユーザーはデータ操作を拒否する。停止中のお題の公開扱いは実装前に固定する。

退会機能は今回作らない。作品の7日期限・手動作品削除・お題の論理削除・放置画像の回収は引き続き実装する。管理者の停止・削除手順、実験データの最終保持期間は別途運用で決定する。将来usersを物理削除する場合は、サブコレクションが自動削除されない点を考慮する。

## 7. 受け入れ条件

- [ ] Googleログインで誰でも初回登録でき、ランダム名・累計・枠・ピンが初期化される。再送で値が変わらない。
- [ ] 最大5掲載・5ピン。6件目・自己ピン・自己送信を拒否し、同時操作でも上限を守る。
- [ ] タイトル・説明・タグの検証、編集不可、7日／30日境界と本人・送信済み描き手の例外が一致する。
- [ ] Flutter圧縮後の画像をFastAPIで再検証し、WebPへ正規化してVision SafeSearchを通す。1枚の完成画像を表示と保存に共用し、サムネイルを生成しない。
- [ ] 送信は1人1お題1回。通信断・並行commitでも作品・履歴・累計は1回だけ確定する。
- [ ] 受信者のみ画像を取得可能。自動更新で新着表示され、一覧取得では未読を維持し、初回詳細表示で既読になる。
- [ ] 画面離脱・背景タブでポーリングを停止し、復帰時に再取得。タブ終了後のアップロード再開は行わない。
- [ ] いいねは1回、取消不可。作品削除後も3種の累計と描いた履歴の整合性が保たれる。
- [ ] 古いお題の枠再利用後に古いお題を削除しても、新しい枠を消さない。
- [ ] 期限・手動削除直後に作品を取得不可にし、失敗した物理削除と遅れて作られた画像も定期処理で回収できる。
- [ ] 画像保存後のDB失敗・並行commitから再試行しても同じ検証済み完成画像を再利用し、上書き・二重加算をしない。不一致はUPLOAD_CONFLICT。
- [ ] 自動更新成功時に後続ページと旧カーソルを破棄し、失敗時は既存一覧を保持。更新前の遅延応答が混入しない。
- [ ] 不存在・資格なし・削除済み・期限切れは「参照できません」、通信障害は再試行表示へ統一。
- [ ] 通知・退会・名前変更の画面、API、データが今回の必須機能に含まれない。
- [ ] サーバー設定で503へ切替・解除でき、全インスタンスへの反映、画像APIとcommitへの適用を確認する。
- [ ] Firestore直接アクセス拒否とAPI認可を検証し、iPad・スマホ・PCで一連の操作を確認する。

## 8. 実装前に決める詳細

ランダム表示名の形式、画像出力形式・画素数・容量の実測値、セッション期限（暫定30分）と掃除の猶予期間、内部削除の実行頻度、メンテナンス設定の反映手順、停止中ユーザーの公開内容、submissionId生成規則を固定する。これらは通知・退会機能を復活させる理由にはしない。

## 9. DB要件（将来）

ユーザーのプロフィール拡充として、**ユーザーアイコン**と**メイン作品**を登録・参照できるようにしたい。ハッカソン版の実装・受け入れ条件には含めず、導入時にDB・Storage・APIの設計を追加する。

| 項目 | 将来追加したい情報・用途 |
|---|---|
| ユーザーアイコン | ユーザーに紐付くプロフィール画像。画像の保存先・変更・削除を管理する |
| メイン作品 | ユーザーがプロフィールで代表として扱う作品。ユーザーとの紐付けと、作品画像または作品参照を管理する |

保存するフィールド名・コレクション、画像形式・容量、公開範囲、差替え・削除、保持期間は未決定。メイン作品を専用画像として登録するか、既存作品から選択するかも導入時に決める。現行の受信作品は受信者限定・7日保持のため、公開プロフィールへ自動転用せず、公開可否・権利と保存期間を別途定義する。

## 10. 公式参考資料

- [Firestoreトランザクション](https://firebase.google.com/docs/firestore/manage-data/transactions)
- [Firestoreの削除とサブコレクション](https://firebase.google.com/docs/firestore/manage-data/delete-data)
- [Security RulesとサーバーSDK](https://firebase.google.com/docs/firestore/security/rules-conditions)
- [Cloud Storageの世代条件](https://cloud.google.com/storage/docs/request-preconditions)
