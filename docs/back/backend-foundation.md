# FastAPI共通基盤

認証後の登録・お題・作品APIで同じ契約を使うための共通処理です。Firebaseへの接続設定は [firebase-auth.md](firebase-auth.md) を参照してください。

## モジュール

| ファイル | 責務 |
|---|---|
| `back/app/main.py` | アプリ生成、ルーター・共通処理の組み立て |
| `config.py` | 起動時の設定と環境変数の検証 |
| `firebase.py` | Admin SDKの一度だけの初期化とFirestore接続 |
| `auth.py` | Google IDトークン検証、登録済み・active状態の確認 |
| `errors.py` | 共通エラー、HTTP・入力・外部障害の変換、OpenAPIモデル |
| `middleware.py` | リクエストID、メンテナンス、キャッシュ抑止、アクセスログ、想定外例外 |
| `schemas.py` | 厳密な入力、前後空白の除去、ページング契約 |
| `clock.py` | UTC時刻、RFC 3339のZ表記、期限境界 |
| `users.py` | ユーザー登録と本人情報API |
| `ideas.py` | お題・スロット・ピンのAPI、認可、Firestoreトランザクション |

## 設定

`back/.env.example` を `back/.local.env` にコピーして設定すると、Python直接起動時は作業ディレクトリに関係なく自動で読み込みます。環境変数はファイルより優先されます。以下のように環境変数を明示する方法も利用できます。

```powershell
$env:GOOGLE_CLOUD_PROJECT = 'YOUR_PROJECT_ID'
$env:CORS_ORIGINS = 'http://localhost:3000'
$env:MAINTENANCE_MODE = 'false'
$env:RETRY_AFTER_SECONDS = '30'
cd back
./.venv/Scripts/python.exe -m uvicorn app.main:app --reload --port 8080
```

`MAINTENANCE_MODE` はtrue/falseのみ、再試行秒数は正整数です。CORSはカンマ区切りの明示的なOriginを指定し、ワイルドカードは拒否します。ローカル開発時だけ `CORS_ALLOW_LOCALHOST=true` を指定すると、HTTPのlocalhost・127.0.0.1の可変ポートも許可します。既定はfalseで、本番では有効にしません。認証付きPOSTと今後の削除・更新に対応しています。

設定変更は再起動で反映します。Cloud Runでは同じ設定を持つリビジョンへ切り替え、旧リビジョンへトラフィックが残っていないことを確認します。Composeは `back/.local.env` を `env_file` で自動的に渡します。envファイルはDockerイメージには含めません。ADCは別途読み取り専用マウントと `GOOGLE_APPLICATION_CREDENTIALS` の設定が必要です。Cloud Runではサービスに設定した環境変数と実行サービスアカウントを利用します。

## 認証・認可

- 初回登録では `GoogleUid` を引数に指定します。署名・期限・失効・Googleプロバイダーを検証したUIDです。
- 通常APIでは `ActiveUser` を引数に指定します。さらにFirestoreのユーザー存在・active状態を確認し、本人のUIDを付けて返します。`GET /api/v1/me` が使用例です。
- 所有者・受信者・対象の期限などは機能側で検証します。資格なし・欠損・削除済み・期限切れは同じ404にします。
- 書き込みトランザクションでは、事前の依存関係だけに頼らず状態を再読込します。競合中の停止や期限到達を見落とさないためです。
- UIDは認証結果を使い、本文・クエリに入ったUIDを操作主体にしません。

`POST /api/v1/internal/cleanup` は専用サービスアカウントのGoogle OIDCで認証し、期限切れピンを整理します。Firebaseの利用者認証とは別経路です。設定・定期実行は [期限切れピン整理](pin-cleanup.md) を参照してください。作品画像・一時アップロードの整理は未実装です。

## エラー・追跡・ログ

応答は `{ "error": { "code", "message", "details", "requestId" } }` に統一しています。detailsは現時点ではnullです。未知ルートの404、HTTPメソッド違いの405、入力422、外部障害503、想定外例外500も同じ形式です。

応答の `X-Request-Id` とJSONの `requestId` が一致します。IDはサーバーで生成し、クライアント指定の値を採用しません。401は `WWW-Authenticate: Bearer`、429・503は `Retry-After` を付けます。個別処理で指定したRetry-Afterは保持します。OpenAPIの共通エラー定義も更新しています。

通常APIの成功・失敗とも `Cache-Control: private, no-store` を付けます。許可したOriginには500・メンテナンス503でもCORSヘッダーを付け、リクエストIDと再試行秒数をブラウザーから読めるようにしています。

Uvicornで起動すると、アクセスログにイベント名・ID・HTTPメソッド・ルートのテンプレート・応答ステータス・所要時間をJSONで記録します。本文、トークン、クエリ、実際のUIDや文書ID、例外メッセージは共通ログへ出しません。Uvicorn自身の標準アクセスログには実パスとクエリが含まれるため、個人情報をURLへ入れず、必要なら `--no-access-log` で標準アクセスログを停止してください。独自の共通ログは残ります。

想定外例外の `unhandled_failure` ログには、`requestId`・`exceptionType` と、呼び出し順の `frames`（ファイル名・関数名・行番号）を記録します。配列末尾が例外の発生位置です。絶対パス、ソース本文、ローカル変数、例外メッセージは含めず、クライアントへの500応答も従来の共通形式を維持します。Cloud Runのログで `unhandled_failure` または応答の `X-Request-Id` を検索すると、発生箇所を追跡できます。反映にはAPIの再デプロイが必要です。

応答開始後の画像ストリームなどで失敗した場合は、JSONエラーへ差し替えられません。失敗を記録し、ストリームを終了します。

## メンテナンス

通常の `/api/v1` 配下は503 MAINTENANCEを返します。`/health` と `POST /api/v1/internal/cleanup` は対象外です。cleanupの除外は認証の免除を意味しません。CORSのプリフライトも通常どおり処理します。

発行済み一時アップロード権限や配信済みのデータの回収はしません。管理画面や切替APIは作っていません。

## 入力・日時・一覧

リクエストモデルは `InputModel` を継承します。未知項目や文字列から数値への暗黙変換を拒否し、文字列と文字列配列の前後空白を長さ検証より先に除去します。必須・文字数・タグの重複排除・各種IDの検証は各モデルで追加します。文字数はPython/PydanticのUnicodeコードポイント数です。ネストした入力には個別の入力モデルを定義します。

DTOの日時には `UtcDatetime` を使います。内部ではタイムゾーン付きdatetimeを保持し、JSON化時にUTC・末尾Zへ揃えます。タイムゾーンなしの日時は拒否します。Firestore保存時はTimestampへ変換されるdatetimeを渡します。

時刻取得は `utc_now()`、有効期限判定は `is_unexpired(expires_at, now)` です。期限と一致した時点で無効です。トランザクションの各再試行内で現在時刻を取り直してください。createdAtとその派生期限は同じ時刻を基準に計算します。

一覧には `PageQuery`（limit既定20・最大50、不透明cursor）と `Page[DTO]`（items / nextCursor / serverTime）を用意しています。FastAPIでは `Annotated[PageQuery, Query()]` で受け付けます。スロット・ピンにはページングを使いません。

具体的なFirestoreクエリ・インデックス・カーソルの生成と復元は各一覧APIの実装時に追加します。時刻DESC・文書ID DESCの順序、利用者・検索条件のスコープ、ページごとの認可再評価を揃える必要があります。共通の一覧応答だけでアクセス制御が完了するわけではありません。

## 検証

```powershell
cd back
./.venv/Scripts/python.exe -m pytest -q
```

外部サービスを差し替えたテストで、認証・登録の回帰、エラー・CORS・ログ、厳密な入力、UTC境界、一覧契約、メンテナンスを検証します。実際のFirebaseでの認証・競合・IAM権限とCloud Run全インスタンスの設定反映は別途確認が必要です。

## APIとFlutterの設定の分離

APIは `back/.local.env` または環境変数から設定を取得します。環境変数が優先されます。`GOOGLE_CLOUD_PROJECT` には利用するFirebaseプロジェクトIDを明示してください。

Flutterは `flont/firebase-config.local.json` を使用します。APIはこのJSONを読み込まず、Composeでも共有しません。同じFirebaseプロジェクトを利用する場合は、両方に同じプロジェクトIDをそれぞれ設定してください。APIのenv自動読み込みとComposeの `env_file` は引き続き利用できます。
