# 作品画像処理・通信設計書

> 現行デモの変更: Flutterで事前変換し、FastAPIで再検証後、画像バイト列をVisionへ直接送信する。Vision用の一時Storage保存は廃止した。以下の一時保存を用いた記述・図は従来の設計案であり、通常投稿の正式保存はまだ未接続。現行手順は [Visionデモ](back/vision-web-demo.md) を参照。

- 対象: M1のイラスト投稿
- 方針: Flutterでアップロード前圧縮し、FastAPIで最終検証・WebP変換・不適切画像判定を行う
- 関連資料: [総合仕様書](specification.md)、[DB・API仕様書](database/DB_v0.md)
- Vision実装詳細: [Google Cloud Vision SafeSearch 実装設計書](back/google-cloud-vision-safesearch.md)

## 1. 要約

Flutterは画像を選択・プレビューし、`flutter_image_compress`で可能な範囲で縮小・圧縮してからCloud Storageの非公開一時領域へ送る。FastAPIは一時画像を読み、実形式・寸法・デコード可否を確認し、メタデータを除去してWebPへ変換する。Cloud Vision SafeSearchで変換後画像を判定し、方針上許可されたものだけを非公開の完成領域へ保存し、Firestoreの投稿情報を確定する。

このため、先に作成したFastAPI画像処理コードは丸ごと不要にはならない。**画像形式・画素数検査、EXIF向き補正、メタデータ除去、サイズ調整の処理は流用可能**。ただし最終出力形式はJPEG/PNGではなくWebPへ変更し、Flutter側圧縮済み画像をもう一度高品質で再圧縮して劣化させない設定に見直す。現在は独立した変換関数であり、まだStorage・Vision・commit APIには接続されていない。

## 2. 層ごとの責務

| 層 | 責務 | 信用するもの |
|---|---|---|
| Flutter Web | 選択、プレビュー、形式の早期確認、`flutter_image_compress`による可能な範囲の事前圧縮、進捗・再試行表示 | ファイル選択と圧縮結果はUX向け。認可・最終形式判定には使わない |
| Cloud Storage一時領域 | prepareで発行した1オブジェクト分の短期アップロード先を受け、一時画像を非公開で保持 | クライアント指定MIMEやメタデータは信用しない |
| FastAPI / Cloud Run | 投稿資格、オブジェクトgeneration、実バイト列、容量・画素数を検証。メタデータ除去・WebP変換、SafeSearch判定、完成保存とDB確定、受信者認可付き配信、cleanup | 唯一の確定判断主体 |
| Cloud Vision API | SafeSearchのカテゴリ別尤度を返す | 自動判定は確率的。境界例は要確認扱いにできるよう状態設計する |
| Cloud Storage完成領域 | 判定を通過したWebPを非公開で保存 | Flutterや一般利用者から直接読めない |
| Firestore | uploadSession、作品状態、所有者、Storageパス、形式、期限を管理 | トランザクションで投稿・履歴・累計の整合を取る |

## 3. 通信シーケンス

```mermaid
sequenceDiagram
    participant U as Flutter Web
    participant A as FastAPI / Cloud Run
    participant T as GCS 入力一時領域
    participant Q as GCS 審査ステージング
    participant V as Cloud Vision SafeSearch
    participant F as GCS 完成領域
    participant D as Firestore

    U->>U: 1 画像選択・プレビュー
    U->>U: 2 flutter_image_compressで縮小/圧縮
    U->>A: 3 prepare (Firebase ID token, ideaId, 出力byteSize/contentType)
    A->>D: 4 投稿資格・受付状態・重複・利用者状態を確認
    A->>D: 5 pending uploadSession作成
    A-->>U: 6 uploadId, 一時PUT URL, headers, expiresAt
    U->>T: 7 圧縮後バイト列を一時領域へPUT
    T-->>U: 8 成功
    U->>A: 9 commit (uploadId)
    A->>D: 10 session・期限・投稿資格を再確認
    A->>T: 11 generation固定で一時画像を取得
    T-->>A: 12 画像バイト列
    A->>A: 13 実形式・寸法・画素数・デコードを検証
    A->>A: 14 EXIF向き補正・メタデータ除去・WebP変換
    A->>Q: 15 正規化WebPを非公開stagingへ保存
    A->>V: 16 stagingのgs:// URIでSafeSearch
    V-->>A: 17 カテゴリ尤度
    alt 許可
        A->>F: 18 staging WebPをgeneration条件付きで完成領域へcopy
        F-->>A: 19 完成オブジェクト情報
        A->>D: 20 artwork・history・counter・sessionをtransaction確定
        D-->>A: 21 committed
        A->>T: 22 入力・staging画像を削除（失敗時cleanup）
        A-->>U: 23 投稿完了
    else 拒否または要確認
        A->>D: 18 rejected / review_requiredを記録
        A->>T: 19 入力・staging画像を削除（失敗時cleanup）
        A-->>U: 20 投稿不可または確認中
    end

    U->>A: 23 受信者が画像要求 (ID token, submissionId)
    A->>D: 24 recipient・期限・削除・approved状態を確認
    A->>F: 25 WebPを取得
    F-->>A: 26 bytes
    A-->>U: 27 認可済み image/webp (private, no-store)
```

### 通信量の意味

- Flutter圧縮で減るのは、ブラウザーからStorageへのアップロード量、およびその後のCloud Run→Visionへの入力データ量。
- FastAPIによるWebP変換は、最終保存容量と受信者への配信量を減らす役割。
- 画像データはFlutter→一時Storageへ1回送る。FastAPIが一時画像を読み込み、完成WebPを別オブジェクトとして保存する。これは同じファイルの二重アップロードではなく、仮置きと承認済み成果物の分離。
- Vision APIへbase64で画像を送るJSONリクエストは10 MB上限があり、Visionの画像上限も20 MB。大きい画像を扱えるよう、FastAPIが検証・WebP正規化した画像を非公開の審査ステージングへ置き、Vision APIにGCS URIを渡す。Vision呼出元に対象オブジェクトの読取権限を与え、対応形式・サイズ内であることも確認する。承認後はサーバー側copyで完成領域へ移し、審査用オブジェクトを削除する。[Vision SafeSearchのGCS入力](https://cloud.google.com/vision/docs/detecting-safe-search)、[Visionの形式・サイズ上限](https://cloud.google.com/vision/docs/supported-files)

## 4. Flutter圧縮の設計

### 使い方とプラットフォーム差

`flutter_image_compress`は画像バイト列を受け取り、指定した出力寸法・品質・形式で画像バイト列を返す。Webでは`compressWithList`を使う。ファイルパスを使う`compressWithFile` / `compressAndGetFile`はWebで使えない。Web版はCanvas `toBlob`に依存するため、品質とエンコード対応はブラウザーによって差がある。JPEG/PNG出力はWebを含む対応表にあるが、HEIC出力はWeb非対応。PNGのquality指定はiOS等で無視されることがある。[flutter_image_compress公式説明](https://pub.dev/packages/flutter_image_compress)

### 推奨処理

1. 元画像のbyteSizeが小さく、寸法も既に上限内なら、再エンコードを省いてよい。PNGは再エンコードしても小さくならず、少し大きくなる場合がある。
2. 元画像寸法を読み、長辺が暫定2,560pxを超える場合だけアスペクト比を保って縮小する。
3. 不透過のJPEGはJPEG出力で高めの品質から圧縮する。品質は初期案90〜94。通信削減率と画質を実画像で比較して調整する。
4. 透過PNGはPNG出力で透過を保ち、寸法縮小だけを行う。PNGのquality値で圧縮率が上がるとは期待しない。
5. `keepExif: false`を指定し、orientation補正が二重に掛からないよう`autoCorrectionAngle`の既定動作と元画像の向きを確認する。
6. 出力が元より大きいときは、圧縮出力を採用せず元画像を使う。ただし元画像もprepare/commitでサーバー検証し、高い上限を超える場合は拒否する。
7. 返り値が空または例外の場合は、圧縮失敗を扱う。受け付ける形式の元画像をそのままアップロードするフォールバックを許すか、明示的な再試行を求めるかを決める。HEICのWeb入力などデコード不能ケースは無条件のraw fallbackにせず、許容形式・サーバー処理能力を確認する。

`minWidth`/`minHeight`という引数名は上限寸法として働き、縦横比を保ち、拡大しない。固定byteSizeを狙うには品質や寸法を反復調整する必要があり、クライアント側で厳密な容量保証はできない。サーバーが実サイズを確認する。[API使用説明](https://pub.dev/documentation/flutter_image_compress/latest/)

### 入力形式

- JPEG・PNGはFlutter Webの主対象。
- WebPは入力非対応。
- HEIC/HEIFを投稿形式として維持する場合、Webでのデコード・圧縮を保証できない。ネイティブiOS/Androidでの対応もOS・エンコーダーに依存し得るため、Flutter圧縮できない時のサーバー変換fallbackを用意するか、M1でHEICを外してJPEG/PNGに限定するかを確定する。
- Web版利用者がHEICを選んだ時、処理に失敗してもアプリが黙って壊れないよう、対応外案内またはサーバー処理へ送る選択を示す。

## 5. FastAPIの既存画像処理コードをどう使うか

| 現在の処理 | 今後 | 理由 |
|---|---|---|
| 実画像デコーダーによる形式判定 | 維持 | Flutterの拡張子・MIME・圧縮結果を信用しない |
| 空/破損画像・アニメーション拒否 | 維持 | サーバー境界で不正データを排除 |
| 最大画素数の検査 | 維持 | 圧縮後でも画素爆弾や処理負荷を防ぐ |
| EXIF orientation適用 | 維持または出力確認後に簡素化 | 圧縮側の自動回転が確実とは限らない。サーバーが最終表示方向を保証 |
| メタデータ除去 | 維持 | プラグインは既定で除去を意図するが、プラットフォーム別結果もあり、サーバーで最終確認する |
| 2,560pxへの縮小 | 維持を安全fallbackとして推奨 | クライアントが縮小しない・迂回する場合にも完成品の寸法を揃える |
| PNG/JPEGへの出力 | 変更 | 審査・完成画像はWebPへ出力。透過はWebP alphaで保持 |
| 512 MiB固定上限 | 確定値ではなく設定化 | 安全弁として大きい値を仮置きしただけ。Cloud Run・GCS・Vision上限を測り調整 |
| Storage/Firestore接続 | 新規実装 | 現モジュールは独立関数で、Storage/API連携は未実装 |

FastAPIは通信経路に残り、作品を確定する信頼境界として必要。クライアント圧縮によりサーバーでの圧縮量は減るが、形式検証・画素制限・審査・権限確認・DB整合性は代替されない。

## 6. SafeSearchの判断と保存状態

SafeSearchはadult、spoof、medical、violence、racyの尤度を返す。APIが成功したことだけで承認せず、各カテゴリの判定しきい値と「要確認」状態を定義する。絵柄や文脈による誤判定を考慮し、M1で人手確認を用意しない場合は、結果をどう利用者に示すかを明記する。

| 判定結果 | 状態案 | 完成領域への保存 |
|---|---|---|
| 全カテゴリが許容範囲 | approved/committed | 可 |
| しきい値超過 | rejected | 不可。一時画像を削除 |
| 境界値・判定が曖昧 | review_required | 人手確認機能がなければ、M1では送信保留または拒否のどちらかを決める |
| APIタイムアウト・エラー・応答欠落 | moderation_pending / retryable | 不可。fail-openしない |

Vision障害時、Flutterは同じ`uploadId`でcommitを再試行できる。画像を再アップロード・再課金せず、保存済みgenerationに対する判定を再試行する。Vision利用料金・月次無料枠・課金アラートは環境担当と確認する。

## 7. 状態とAPIの契約案

### Upload session

`pending_upload → uploaded → processing → moderation_pending → committed`

終端・例外状態: `rejected`, `expired`, `failed_retryable`。セッションにはartistId、ideaId、submissionId、tempPath、inputGeneration、inputContentType、inputByteSize、status、expiresAt、moderation結果、完成path、変換仕様versionを保存する。Visionの生レスポンス全文や画像データは不要以上に保存しない。

### prepare

`POST /api/v1/artworks/prepare`は認証済みFlutterからideaId、圧縮後のcontentType・byteSizeを受ける。FastAPIは投稿資格・重複・受信者状態を確認し、pendingセッションと一時画像1個に限定した短期PUT権限を返す。公開read/list/delete権限は付けない。

### commit

`POST /api/v1/artworks/commit`はuploadIdを受ける。generationを固定し、検証→WebP化→審査用staging保存→SafeSearch (gs:// URI)→承認済みWebPを完成領域へcopy→Firestore transactionの順に行う。committed再送は既存結果を返す。Vision一時障害は再試行可能状態を返し、投稿を完成領域へ公開しない。

### image / download

FastAPIがFirebase ID tokenからUIDを得て、recipientId、deletedAt、expiresAt、approved状態を確認してから完成WebPを返す。公開URLや長期署名URLを返さず、`Cache-Control: private, no-store`を設定する。downloadも同じ権限確認を使う。

## 8. 失敗と再試行

| 失敗 | Flutter側 | サーバー側 |
|---|---|---|
| Flutter圧縮エラー | エラーを表示。安全に扱える許容形式のみ元画像で続行可能 | 実データを必ず検証 |
| PUT失敗/通信切断 | 同一画面で同じsessionに再送。完了有無を確認して二重作成を防ぐ | expiry後の一時物をcleanup |
| format/画素数拒否 | 対応形式・解像度の変更を案内。自動再試行しない | 415/413等で拒否し完成保存しない |
| WebP変換失敗 | 送信失敗を表示し再試行可能 | 一時物を保持して同一generationで処理再試行、期限後cleanup |
| Vision判定エラー | 「確認処理中・再試行」 | pendingのまま保持。承認扱いにしない |
| 判定拒否 | 結果を案内し、投稿を確定しない | rejected状態を記録し一時画像削除 |
| 完成保存後のDB失敗 | 同じuploadIdでcommit再送 | 完成物のgeneration・uploadId・仕様versionを照合して再利用し、二重加算を防止 |
| 応答が消えた | 同じuploadIdでcommit再送 | committedなら結果のみ返す |
| uploadId期限切れ | 送信履歴を確認して必要ならprepareからやり直す | expired化し、発行済み権限終了後に一時画像を回収 |

## 9. 開発・検証手順

1. Flutter Webで`compressWithList`によるJPEG/PNGの縮小・圧縮を試す。ChromeとSafari、代表的なiPadで品質、出力byteSize、透過、向き、処理時間、失敗を測る。
2. Android/iOSネイティブは別に確認する。Web結果と同一バイト列になる要件は置かず、画質・寸法・透過・メタデータの受け入れ条件を共通化する。
3. HEIC/HEIFはWeb・実機ごとに入力デコード可否を確認し、fallbackかM1対象外かを決定する。
4. FastAPIの画像処理関数をWebP出力へ変更し、入力形式・巨大画素・破損・orientation・metadata・透明度・出力寸法を単体検証する。
5. Vision APIはfakeで判定・エラー・timeout・しきい値を試し、開発用GCPプロジェクトでSafeSearchの実接続と費用を少数画像で確認する。
6. Storage/Firestoreはfake/emulatorで再試行・競合・cleanupを確認する。短期PUT・generation条件・VisionがGCS URIを読む権限は開発用実バケットで確認する。
7. 同じDockerイメージをローカル・Cloud Runへ使い、Cloud Runのmemory、timeout、concurrencyで最大寸法・代表HEIC/JPEG/PNGを処理する。
8. 利用者テストでは、圧縮前後の見た目、送信時間、失敗時説明、SafeSearch誤判定時の扱いを確認する。

## 10. 決定事項

- [ ] FastAPI完成画像はWebPとするか（この設計はWebPを推奨。PNG透過はアルファ保持WebPを利用）
- [ ] Flutter圧縮後の最大辺、JPEG品質の初期値と画質評価方法
- [ ] HEIC/HEIFをM1で維持するか。Flutter Webで未対応時のfallbackを設けるか
- [ ] FastAPIの画素数・入力byteSize・最終byteSizeの高い安全上限
- [ ] SafeSearchカテゴリごとの閾値、review_requiredのM1での扱い
- [ ] Vision失敗時の再試行回数・session保持期限
- [ ] 一時アップロードURL方式、TTL、bucket prefix、IAM/Roles、CORS
- [ ] Storage/Firestore/Firebase担当者との責任分界、API契約の確定
- [ ] 20ドルクレジット内での試験画像数・予算アラート

## 11. 受け入れ条件

- [ ] Flutter圧縮でJPEG/PNGのアップロード量が減るケースを測定し、増える画像では元画像を選べる。
- [ ] PNG透過、向き、色、見た目を維持し、可能な環境では位置情報等のメタデータを除去する。
- [ ] Web・iOS・Androidの出力が完全一致するとは仮定せず、FastAPIで実データを再検査する。
- [ ] WebP入力、破損画像、偽装MIME、アニメーション、巨大画素数を拒否する。完成画像はWebP。
- [ ] FastAPIが画像をWebPへ正規化し、許可されたContent-Typeと寸法のみ完成領域に保存する。
- [ ] SafeSearch判定が失敗・timeout・不明の場合、完成画像を公開・確定しない。
- [ ] Vision通過画像のみcompleted状態になり、DB失敗後の再試行でも作品・履歴・累計が一度だけ確定する。
- [ ] 受信者以外、期限後、削除後は画像を取得できない。
- [ ] 一時画像・拒否画像・孤立完成画像をcleanupで回収できる。

## 12. バックエンド全体への影響と変更案

この方式はバックエンド全体の置き換えではなく、**作品投稿の開始から承認・確定・閲覧・削除までを新しい縦断機能として追加**する変更である。既存のユーザー登録、お題CRUD、ピン、認証基盤は原則維持する。作品を確定する前にSafeSearchを通すため、既存の受信箱・描いた履歴・累計更新と投稿commitの接続点は変更対象となる。

| 領域・現状 | 変更案 | 影響 |
|---|---|---|
| `back/app/artworks.py`：受信箱・履歴・既読・いいねのみ実装。画像バイトや投稿APIなし | prepare/commitを追加し、Storage取得、実体検査、WebP化、SafeSearch、完成領域保存、Firestore確定をサービス層に分割。image/download/deleteも追加 | 主な実装対象。作品ドキュメントは承認後にだけ作成し、既存受信箱は未承認データを表示しない |
| `back/app/ideas.py`：`can_submit`相当の一覧判定・描いた履歴参照あり | 投稿資格を共有可能な関数へ切り出すか、既存ルールを参照してprepareとcommitの両方で再検証。最終確定トランザクションで重複を防ぐ | 受付期限・削除・ピン・自己投稿不可の判定を二重実装しない。idea投稿機能自体は変更不要 |
| `back/app/image_processing.py`：形式検証、EXIF補正、縮小、metadata除去、JPEG/PNG出力 | Flutter圧縮を前提にしつつ、サーバーを最終検証者として残す。出力をWebPへ変更し、透過alpha保持、入力・出力容量と画素数、アニメーション拒否を設定化 | 既存処理を再利用するが、そのまま投稿フローへはつながっていない。512 MiBは製品上限として扱わず、高い安全弁の設定値と実測値を分ける |
| `back/app/schemas.py`：prepare用入力モデルあり、APIは未実装 | Flutterが実際に送る圧縮後MIME・byteSizeと照合し、許容する入力形式・高位安全上限・応答契約を確定 | 現行HEIC/HEIF受入れはFlutter Web圧縮と不整合の可能性があり、Webでの扱いを別途確定。宣言値だけで実体を信用しない |
| `back/app/config.py`、`back/.env.example`：project/CORS等 | bucket名、prefix、session期限、画像安全上限、Vision閾値・timeout/retry等、環境差のある値を追加。秘密鍵を設定ファイルに置かずADC/IAMを使う | ローカル・CI・Cloud Runの設定項目とデプロイ手順に影響 |
| `back/requirements.txt`、`back/Dockerfile`：Firebase Adminと画像codecあり | GCS・Vision連携ライブラリを追加し、WebP encodeと必要入力codecをDocker内で確認。対応codec込みの同一イメージをローカル/Cloud Runで利用 | 依存関係・イメージサイズ・ビルド時間・メモリに影響 |
| `back/app/firebase.py` / `auth.py`：ADC初期化、Firebase ID token、active確認 | Firestore/Admin初期化とBearer認証は再利用。Storage/Visionクライアントを同じADC/IAM原則で初期化し、APIで所有者・受信者を明示認可 | 既存認証を置き換えない。Admin SDKはRulesを迂回するため認可実装が必須 |
| `back/app/errors.py`、`middleware.py`、`main.py` | 共通JSONエラー・requestId・no-storeを利用。Storage/Vision失敗をretryable 503等の業務エラーへ写像。cleanup routeは内部認証を必須化 | 共通基盤は小規模拡張。通常APIの保守応答、CORS、ログに画像データ・署名URL・tokenを出さないことを確認 |
| `artworks`/`drawnHistory` Firestore、indexes | uploadSessionsに状態、入力generation、変換version、moderation概要、期限を記録。作品・描いた履歴・累計は承認後に一度だけ確定。inboxは現行indexを維持できる形を優先 | pending画像をartworksに入れない。状態フィルターを加える場合はクエリ・index・DB仕様を同時更新 |
| Firebase/Storage運用設定 | private bucket、staging/final prefixのIAM、短期書込権限、generation precondition、Storage CORS、ライフサイクル/cleanupを設定 | GCP側設定も実装範囲。Firestore rulesだけではStorage保護にならない |

### 既存領域の扱い

- **原則そのまま**: Firebase ID tokenの検証、active user依存、ユーザー登録、アイデア作成・一覧・削除、pin CRUD、共通ページングとエラーenvelope。
- **接続・確認が必要**: 投稿資格判定、投稿済み重複判定、`drawnHistory`と`drawnCount`の確定、受信箱の承認済み作品だけ表示、既読・いいねが作品期限/削除後に既存仕様どおり動くこと。
- **追加**: Storage/Vision client、アップロードセッション状態機械、commitの再試行/idempotency、画像配信認可、cleanup内部認証と上限付きバッチ処理、Cloud Scheduler等の呼び出し設定。
- **他層**: Flutterの`flutter_image_compress`とPUT実装、Flutter側依存追加、Storage bucket/IAM/CORS、Vision API有効化・権限・予算監視も必要。Flutter圧縮だけではサーバー検証・Vision・認可・DB整合性を省略できない。

### 推奨する確定順序

1. 画像入力形式をFlutter Webを含めて固定し、特にHEIC/HEIFをM1で維持するかを決める。容量上限・最大画素数・出力形式・alpha・EXIF方針も同時に固定する。
2. API/Firestore契約と状態遷移を確定する。投稿資格の共有ルール、submissionIdの一意性、承認前に作品を作らないこと、Vision失敗時の再試行、拒否時の利用者表示を決める。
3. GCP環境を準備する。private bucket/prefix、IAM最小権限、Storage CORS、Vision API、ADC、費用アラートを開発環境から設定する。
4. `image_processing`のWebP出力と安全制限、設定・依存関係を更新する。
5. prepare/PUT/commitを実装する。prepareとcommit双方で投稿資格を確認し、generation固定・SafeSearch成功後に限って完成StorageとFirestoreへ冪等確定する。
6. 画像取得・download・削除・cleanupを追加し、受信者限定、期限時点の拒否、期限切れ一時物/孤立成果物回収を通す。
7. Flutter圧縮・通信再試行・進捗UIをAPI契約に接続し、全層をローカル/fake・開発GCP・Cloud Runで順に確認する。

### これまでの実装計画から変わる点

| これまでの計画 | 更新後 |
|---|---|
| Flutterで形式確認・必要なら圧縮する案の検討 | `flutter_image_compress`を使った事前圧縮を前提にする。Web・iOS・Androidで品質やcodecが違うため、寸法/画質などの受入基準を定めて実機確認する |
| FastAPI画像処理を中心に先に実装 | FastAPI画像処理は検証・最終正規化の部品として維持し、投稿資格・セッション・Storage/Vision・Firestore確定を合わせた投稿縦断フローを実装単位とする |
| PNG/JPEG出力・PNG透過保持を前提にした既存処理 | 入力の透過を保ったWebP alphaを最終形式にする。JPEGとPNGを同じエンコード品質で扱わない |
| 画像処理/APIだけを主な作業対象とする | `artworks.py`だけで完結しない。`ideas.py`の投稿条件、schema/config/errors/dependencies、Firestore indexes/model、Storage IAM/CORS/cleanup、Flutterクライアントを計画に含める |
| prepare/commitを後続のAPI作業として扱う | SafeSearch判定をM1投稿確定の必須ゲートとしてcommitに組み込む。Vision障害・不明結果はfail-closedかつ再試行可能状態とする |
| 投稿commit時に作品作成を中心に記述 | moderation通過後だけartwork/history/countを一度だけ確定。承認前の状態はuploadSession側に置き、受信箱・いいね・既読へ流さない |
| M1後半に期限削除・放置画像回収 | 一時領域のcleanup、拒否画像、staging画像、DB確定前に作った孤立完成画像の回収を投稿APIと同時に設計し、運用呼出元・内部認証まで実装対象に含める |

本変更はユーザーAPIやお題APIを置き換えない。ただしcommitが投稿資格・submissionId・履歴・累計を横断更新するため、これらの整合性確認は画像機能の受入条件に含める。

## 13. 実装状況と未確定事項の境界

このリポジトリの現状コードでは、認証・ユーザー・お題の各APIと受信箱/描いた履歴/既読/いいねは存在する。画像処理モジュールとprepare入力schemaは存在するが、画像処理はAPIやStorageへ接続されておらず、Storage/Vision client、prepare/commit、画像配信、cleanupは未実装である。M0の基盤APIを変更するより、M1作品投稿の縦断機能として拡張する。

また、総合仕様書のHEIC/HEIF入力維持と「Flutter Webでも圧縮」という方針には未解決の組合せがある。HEICをWebで安定して扱えない場合の選択肢（M1はJPEG/PNGに限定、またはWeb利用者向けサーバーfallback）を決めるまで、対応形式を確定扱いにしない。

## 参考資料

- [flutter_image_compress (pub.dev)](https://pub.dev/packages/flutter_image_compress)
- [flutter_image_compress API documentation](https://pub.dev/documentation/flutter_image_compress/latest/)
- [Cloud Vision SafeSearch](https://cloud.google.com/vision/docs/detecting-safe-search)
- [Cloud Vision image request formats](https://cloud.google.com/vision/docs/request)
