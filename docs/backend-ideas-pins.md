# お題・スロット・ピン API 設計

- 基準: [`database/DB_v0.md`](database/DB_v0.md) v0.9
- 対象: お題作成・一覧・詳細・削除、本人の掲載スロット、ピンの取得・追加・解除
- API prefix: `/api/v1`。`/health`を除きFirebase IDトークン必須
- 状態: 実装契約。Storage・作品送信APIは対象外

## 1. 共通

- 操作主体はFirebase Admin SDKが検証したGoogle IDトークン内のUIDのみ。本文・クエリのUIDは操作主体にしない。
- 通常APIは登録済みかつ`active`のユーザーのみ利用可能。更新トランザクション内でもユーザー状態を読み直す。
- FirestoreパスはDB_v0.mdに従う: `users/{uid}`、`userSlots/{uid}`、`userPins/{uid}`、`ideas/{ideaId}`。
- 日時はUTC。お題作成時の同じ`now`から`createdAt`、`publishedUntil = now + 7日`、`acceptUntil = now + 30日`を計算する。
- `now < publishedUntil`を掲載中、`publishedUntil <= now < acceptUntil`をピン限定受付、`now >= acceptUntil`を受付終了として判定する。期限を過ぎた枠は掃除前でも空きとして扱う。
- エラーは共通形式`{ "error": { "code", "message", "details", "requestId" } }`。非公開・欠損・削除済み・閲覧資格なしは`404 RESOURCE_UNAVAILABLE`で区別しない。
- Firestore SDKは同期呼出しなので、asyncルートからは`run_in_threadpool`で実行する。

## 2. DTO

### Idea

```json
{
  "ideaId": "UUID v4",
  "ownerId": "Firebase UID",
  "ownerNickname": "ランダム表示名",
  "title": "タイトル",
  "description": "説明",
  "tags": ["タグ"],
  "createdAt": "2026-11-06T00:00:00Z",
  "publishedUntil": "2026-11-13T00:00:00Z",
  "acceptUntil": "2026-12-06T00:00:00Z",
  "canPin": true,
  "canSubmit": true
}
```

`canPin` / `canSubmit`は認証済み閲覧者について、現在の状態を使ってサーバーが算出する表示用情報。更新APIでは必ず条件を再検証する。閲覧可能性は`GET /ideas/{ideaId}`で別途判定する。

停止中ownerの既存お題は、停止中ownerの公開扱いがDB_v0.mdで未確定のため閲覧期間の期限ルールは維持し、`canPin` / `canSubmit`はfalseにする。再開後に期限内であれば通常の資格判定へ戻る。この扱いはチームで確定する。

### Page

```json
{
  "items": [],
  "nextCursor": "opaque cursor or null",
  "serverTime": "2026-11-06T00:00:00Z"
}
```

既存の`PageQuery`を使用し、limit既定20・最大50。不透明カーソルは一覧種別と本人一覧の場合のUIDに結び付け、最後の文書IDを保持する。並び順は日時DESC、文書ID DESC。TLは`publishedUntil`が`createdAt + 7日`であるため同値な新着順として`publishedUntil DESC, __name__ DESC`で問い合わせる。カーソル文書が物理的に存在しない場合は`422 INVALID_INPUT`として先頭からの再取得を促す。

## 3. API一覧

| Method / Path | 成功 | 認可・処理 |
|---|---:|---|
| `GET /api/v1/ideas?limit=&cursor=` | 200 Page[Idea] | `deletedAt == null`かつ`publishedUntil > now`のTL。登録済みactiveユーザー向け。 |
| `POST /api/v1/ideas` | 初回201、同一要求の再送200 | UUID v4・本文を検証し、空きスロット確保、お題作成、`ideaCount`加算を一トランザクションで行う。 |
| `GET /api/v1/ideas/{ideaId}` | 200 Idea | 掲載期間中はactiveユーザー、7〜30日はowner／現存ピン保持者／過去送信者、30日以降はowner／過去送信者のみ。削除済みは不可。 |
| `DELETE /api/v1/ideas/{ideaId}` | 204 | ownerのみ論理削除。該当スロット解放と`ideaCount`一度だけ減算。再送も204。 |
| `GET /api/v1/me/ideas?limit=&cursor=` | 200 Page[Idea] | 本人の`deletedAt == null`のお題を、期限状態を問わず新着順で返す。 |
| `GET /api/v1/me/slots` | 200 Slots | 本人の5枠。期限切れ・空き枠はnullとして返す。 |
| `GET /api/v1/me/pins` | 200 Pins | 欠損・削除済み・30日期限切れを除いた有効ピンとIdeaを返す。 |
| `POST /api/v1/pins/{ideaId}` | 204 | 他人のお題、7日未満、active、5件未満を確認して追加。重複はno-opで204。 |
| `DELETE /api/v1/pins/{ideaId}` | 204 | 本人の配列から除去。すでにない／対象Idea欠損でも成功。 |

## 4. リクエスト・応答の詳細

### `POST /ideas`

```json
{
  "ideaId": "UUID v4",
  "title": "1〜40文字",
  "description": "1〜600文字",
  "tags": ["任意、最大5個、各1〜20文字"]
}
```

- 前後空白を除去してから文字数を検証する。未知フィールド・不正型を拒否。
- タグは順序を保ち、前後空白除去後の完全一致重複を一つにする。
- 既存ideaIdが同じowner・同じ正規化入力なら既存Ideaを200で返す。別ownerなら404、入力違いまたは論理削除済みIDの再利用は409 `IDEA_ID_CONFLICT`。
- トランザクションはusers・ideas・userSlotsを全て読み取ってから書く。userはactiveを確認する。
- slot_0から順に、nullまたは`expiresAt <= now`の最初の枠を選ぶ。空きがなければ409 `SLOT_LIMIT_REACHED`。
- 作成ではidea文書、slot `{ideaId, expiresAt}`、users.ideaCountを原子的に更新する。
- 競合再試行のたびに`now`を再取得し、期限を判定する。

### `GET /ideas/{ideaId}` / `GET /ideas` / `GET /me/ideas`

- `ideaId`はUUID v4形式。無効形式は422。
- TLと本人履歴にdeletedAtのあるIdeaを含めない。
- TLでは最大50件のowner UIDを重複除去してusersをまとめて読み、`ownerNickname`を付ける。Storage情報・メールを返さない。
- `canPin`: 自分以外のactiveなownerのお題で、7日未満・未ピン・有効ピン数5未満の場合true。
- `canSubmit`: ownerとviewerがactiveで、自分以外・未送信・未削除・30日未満で、7日以降なら有効な事前ピンがある場合true。
- 7日後の詳細は事前ピンまたは送信履歴がある利用者に限る。30日後は送信履歴がある利用者とownerに限る。資格なしと存在しないIDは同じ404。

### `GET /me/slots`

```json
{
  "maxSlots": 5,
  "slots": {
    "slot_0": null,
    "slot_1": {"ideaId": "...", "expiresAt": "...", "title": "..."},
    "slot_2": null,
    "slot_3": null,
    "slot_4": null
  },
  "serverTime": "..."
}
```

Firestoreの保存データを直接返さず、`expiresAt <= serverTime`は空きとしてnull化する。

### `GET /me/pins`

```json
{"maxPins": 5, "items": [/* Idea DTO */], "serverTime": "..."}
```

保持中IDのうち`deletedAt == null`かつ`acceptUntil > now`だけを返す。GETで永続文書を必ず掃除する必要はない。POST追加時の上限判定では同じ条件で無効IDを除外し、成功時に配列を整理する。

## 5. トランザクション・エラー

| 操作 | 必要な読取 | 原子的な書込 |
|---|---|---|
| お題作成 | user、対象ideaId、userSlots | idea作成、1 slot設定、ideaCount +1 |
| お題削除 | user、idea、userSlots | deletedAt、ideaId一致時のみslot解放、ideaCountを初回だけ-1 |
| ピン追加 | user、idea、userPins、保持IDの各idea | 有効IDの整理と新しいIDの追加 |
| ピン解除 | user、userPins | 対象IDの除去（反復可能） |

主要な409: `SLOT_LIMIT_REACHED`、`PIN_LIMIT_REACHED`、`IDEA_ID_CONFLICT`、`IDEA_NOT_PINNABLE`。自己ピンは403 `FORBIDDEN`。不存在・未公開・資格なしは404 `RESOURCE_UNAVAILABLE`。不正入力422 `INVALID_INPUT`。Firestore一時障害は共通基盤で503 `SERVICE_UNAVAILABLE` + Retry-After。

削除では全ユーザーのuserPinsを走査しない。Ideaの削除・期限切れは詳細取得／pin一覧／ピン上限判定で即時無効として扱い、Cloud Schedulerの後続cleanupが無効ピンを物理的に除去する。既に保持している有効ピンの再送要求は7日後でも204のno-opとし、新規追加だけを7日で締め切る。

## 6. Firestoreインデックス

クエリ実装に合わせて `firestore.indexes.json` を追加する。最低限、次の複合クエリをFirebase Emulatorまたは開発プロジェクトで実行して必要なindexを確定する。

- ideas: `deletedAt == null`, `publishedUntil > now`, `publishedUntil DESC`, document ID DESC
- ideas: `ownerId == uid`, `deletedAt == null`, `createdAt DESC`, document ID DESC

Firestoreが返すindex作成リンクを確認し、生成した定義をリポジトリ管理に含める。

