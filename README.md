# EWOCURU

「描いてほしい」と「描いてみたい」をつなぐ、お絵描きマッチングサービスです。Flutter（`flont/`）とFastAPI（`back/`）を使って開発します。フロントエンドのフォルダ名は、このプロジェクトでは `flont` としています。

環境構築・起動・動作確認・Cloud Runへのデプロイ方法は [environment.md](docs/environment.md) を参照してください。


## 現在の実装範囲

Googleログイン、FastAPIでのIDトークン検証、Firestoreへの初回ユーザー登録、登録情報のマイページ表示を実装しています。接続には [Firebase認証の設定](docs/back/firebase-auth.md) が必要です。FastAPIの `/health`、DockerによるAPI起動、基本テストも用意しています。

仕様上の目標構成は、FlutterをFirebase Hostingまたはアプリ配布、FastAPIをCloud Runに配置し、Firebase Authentication・Cloud Firestore・Cloud Storage・Cloud Schedulerを組み合わせる構成です。バックエンドにはCloud Run対応Dockerfileと条件付きデプロイ用GitHub Actionsがあります。GCP側の初期設定・デプロイ有効化・実サービスへのデプロイと本番疎通は環境依存のため、[CI/CD手順](docs/ci-cd.md)に従って別途確認してください。

## フォルダ構成

```text
.
├── README.md
├── compose.yaml
├── .gitignore
├── back/                       FastAPIのAPIとDocker設定
│   ├── app/                    API実装
│   ├── tests/                  APIテスト
│   ├── requirements.txt
│   ├── requirements-dev.txt
│   ├── pytest.ini
│   ├── Dockerfile
│   └── .dockerignore
├── flont/                      Flutterアプリ
│   ├── lib/                    Dartのアプリ実装
│   ├── test/                   Flutterテスト
│   ├── web/                    Web向けの起動ページ・アイコン
│   ├── android/                Android向けプロジェクト
│   ├── ios/                    iOS向けプロジェクト
│   ├── pubspec.yaml
│   ├── pubspec.lock
│   ├── analysis_options.yaml
│   ├── .metadata
│   ├── .gitignore
│   └── README.md
└── docs/                       設計資料
    ├── environment.md           環境構築手順書
    ├── specification.md         M0・M1の総合仕様書
    ├── database/               DB・API仕様書とDB構造図
    │   ├── DB_v0.md
    │   ├── database_v0.html
    │   ├── database_v0.png
    │   └── database_v0.svg
    └── architecture/           アーキテクチャ図
        ├── architecture_v0.html
        └── architecture_v0.png
```

## ルート直下のファイル

| ファイル | 説明 |
|---|---|
| [README.md](README.md) | プロジェクトの概要、現在の実装範囲、各フォルダ・ファイルの案内です。 |
| [compose.yaml](compose.yaml) | ローカルでFastAPIコンテナーをビルド・起動するDocker Compose設定です。8080番ポート、CORSの許可元、ヘルスチェックを設定します。 |
| [.gitignore](.gitignore) | 認証情報、仮想環境、キャッシュ、一時作業ファイルなどをGitの管理対象から除外します。 |

## back/：バックエンド

FastAPIの実装と、ローカル・Cloud Runで動かすための設定を置きます。

| フォルダ・ファイル | 説明 |
|---|---|
| [app/](back/app/) | APIのPythonコードを置くフォルダです。 |
| [app/__init__.py](back/app/__init__.py) | `app` をPythonパッケージとして扱うためのファイルです。 |
| [app/main.py](back/app/main.py) | FastAPIアプリの起点です。現在は `/health` とCORS設定を実装しています。許可元は `CORS_ORIGINS` 環境変数で指定します。 |
| [tests/](back/tests/) | APIの自動テストを置くフォルダです。 |
| [tests/test_main.py](back/tests/test_main.py) | `/health` の応答と、許可した接続元だけにCORSレスポンスヘッダーを返すことを検証します。 |
| [requirements.txt](back/requirements.txt) | APIの実行に必要なPythonパッケージとバージョンを定義します。Dockerビルドでも使用します。 |
| [requirements-dev.txt](back/requirements-dev.txt) | 実行用パッケージに加えて、pytest・httpxなどテストに必要なパッケージを定義します。 |
| [pytest.ini](back/pytest.ini) | pytestのテスト探索先と、APIパッケージを読み込むためのPythonパスを設定します。 |
| [Dockerfile](back/Dockerfile) | Python 3.11ベースのAPIイメージを作成します。非rootユーザーでUvicornを起動し、Cloud Runが渡す `PORT` に対応します。 |
| [.dockerignore](back/.dockerignore) | 仮想環境・キャッシュ・テストなどをDockerのビルドコンテキストから除外します。 |

## flont/：フロントエンド

Flutterアプリの共通コードと、各プラットフォーム向けの設定を置きます。M1の主対象はWebですが、Android・iOSのひな形も生成しています。

### アプリ・共通設定

| フォルダ・ファイル | 説明 |
|---|---|
| [lib/](flont/lib/) | 画面や通信処理など、Dartのアプリ実装を置くフォルダです。 |
| [lib/main.dart](flont/lib/main.dart) | アプリの起点とAPI接続確認画面です。`API_BASE_URL` を `--dart-define` で受け取り、FastAPIの `/health` を呼び出します。 |
| [test/widget_test.dart](flont/test/widget_test.dart) | 初期画面にアプリ名とAPI接続確認ボタンが表示されることを検証します。 |
| [pubspec.yaml](flont/pubspec.yaml) | アプリ名、Dart SDKの条件、依存パッケージ、Materialアイコンの利用などを定義します。 |
| [pubspec.lock](flont/pubspec.lock) | 解決済みの依存パッケージのバージョンを記録します。チームで同じ依存関係を使うために共有します。 |
| [analysis_options.yaml](flont/analysis_options.yaml) | Dartの静的解析ルールを設定します。 |
| [.metadata](flont/.metadata) | Flutterがプロジェクトの生成情報や移行情報を管理するファイルです。通常は手動編集しません。 |
| [.gitignore](flont/.gitignore) | Flutterのビルド結果、ツールのキャッシュ、IDE設定などをGit管理から除外します。 |
| [README.md](flont/README.md) | フロントエンド側からルートの環境構築手順書への案内です。 |

### web/：Web向けファイル

| フォルダ・ファイル | 説明 |
|---|---|
| [web/index.html](flont/web/index.html) | ブラウザーがFlutter Webを読み込むためのHTMLです。 |
| [web/manifest.json](flont/web/manifest.json) | Webアプリの名前、表示方法、アイコンなどを定義します。 |
| [web/favicon.png](flont/web/favicon.png) | ブラウザーのタブなどに表示するアイコンです。 |
| [web/icons/](flont/web/icons/) | ホーム画面などで使用する192px・512pxの通常アイコンとマスカブルアイコンを置きます。 |

### android/：Android向けファイル

| フォルダ・ファイル | 説明 |
|---|---|
| `android/settings.gradle.kts` | Gradleのプラグインやモジュール構成を定義します。 |
| `android/build.gradle.kts` | Androidプロジェクト全体のビルド設定です。 |
| `android/gradle.properties` | GradleやAndroidビルドの動作設定です。 |
| `android/gradle/wrapper/gradle-wrapper.properties` | Gradle Wrapperが使用するGradleのバージョン・配布元を指定します。 |
| `android/app/build.gradle.kts` | アプリID、SDK、ビルド種別など、アプリモジュールの設定です。 |
| `android/app/src/main/AndroidManifest.xml` | アプリ情報・起動Activity・インターネット通信権限を定義します。 |
| `android/app/src/debug/AndroidManifest.xml` | debugビルド用の設定です。ローカルAPIへのHTTP通信を許可しています。 |
| `android/app/src/profile/AndroidManifest.xml` | profileビルド用の設定です。開発ツールとの通信権限を定義します。 |
| `android/app/src/main/kotlin/com/outsidewhite/illustration_exchange/MainActivity.kt` | Flutterを起動するAndroid側のActivityです。 |
| `android/app/src/main/res/` | `drawable*` の起動画面、`mipmap-*` の解像度別アイコン、`values*` の通常・ダーク用テーマを置きます。 |
| `android/.gitignore` | Androidのローカル設定や生成物をGit管理から除外します。 |

### ios/：iOS向けファイル

| フォルダ・ファイル | 説明 |
|---|---|
| `ios/Flutter/Debug.xcconfig` / `Release.xcconfig` | FlutterをiOSのdebug・releaseビルドに組み込む設定です。 |
| `ios/Flutter/AppFrameworkInfo.plist` | Flutterのアプリフレームワークに関する情報です。 |
| `ios/Runner/AppDelegate.swift` | iOSアプリの起動処理とFlutterプラグインの登録を行います。 |
| `ios/Runner/Info.plist` | アプリ名、画面方向などiOSアプリの基本情報を定義します。 |
| `ios/Runner/Runner-Bridging-Header.h` | SwiftからObjective-Cのプラグイン登録コードを参照するためのヘッダーです。 |
| `ios/Runner/Assets.xcassets/` | アプリアイコンと起動画像を置きます。各 `Contents.json` が画像とサイズの対応を定義し、起動画像フォルダの `README.md` が差し替え方法を説明します。 |
| `ios/Runner/Base.lproj/Main.storyboard` / `LaunchScreen.storyboard` | Flutter画面を表示する土台と、アプリ起動時の画面を定義します。 |
| `ios/Runner.xcodeproj/` | `project.pbxproj` のビルド設定、`Runner.xcscheme` の実行設定、プロジェクト内部のワークスペース情報を管理します。 |
| `ios/Runner.xcworkspace/` | Xcodeで開くワークスペースです。`contents.xcworkspacedata` に構成、`xcshareddata/` に共有設定を持ちます。 |
| `ios/RunnerTests/RunnerTests.swift` | iOSネイティブ側のテスト用ひな形です。 |
| `ios/.gitignore` | iOSのローカル設定や生成物をGit管理から除外します。 |

## docs/：設計資料

| フォルダ・ファイル | 説明 |
|---|---|
| [environment.md](docs/environment.md) | 第三者向けの環境構築手順書です。必要なツール、ローカル起動、テスト、Cloud Runへのデプロイ手順を記載しています。 |
| [specification.md](docs/specification.md) | サービスの目的、M0・M1の範囲、画面、データ・API、権限、期限・削除、受け入れテストを定義した仕様書です。 |
| [architecture/](docs/architecture/) | アーキテクチャ図を保管するフォルダです。 |
| [architecture_v0.html](docs/architecture/architecture_v0.html) | 総合仕様書をもとに作成した構成図のHTMLです。ロゴ・フォントを埋め込み、ブラウザーで表示できます。 |
| [architecture_v0.png](docs/architecture/architecture_v0.png) | 構成図を共有・閲覧するためのPNG画像です。仕様上の目標構成を示しています。 |

## ローカルで生成されるフォルダ・ファイル

以下は開発ツールなどが生成するもので、通常はGit管理しません。存在する項目は作業環境によって異なります。

| パス | 説明 |
|---|---|
| `.git/` | Gitの履歴・ブランチ・リモート接続情報です。Gitが管理します。 |
| `.tmp/` | 構成図生成に使用したスキル、ロゴ、作業用仮想環境などの一時ファイルです。 |
| `back/.venv/` | バックエンド用のPython仮想環境です。 |
| `__pycache__/` / `.pytest_cache/` | Pythonやpytestが生成するキャッシュです。 |
| `flont/.dart_tool/` | Dart・Flutterが生成する依存関係情報や作業用データです。 |
| `flont/build/` | Flutterのビルド出力先です。Web公開用ファイルは `flont/build/web/` に生成されます。 |
| `.idea/` / `*.iml` | IDEが使用するローカルのプロジェクト設定です。 |
| `flont/android/local.properties` | ローカル環境のAndroid SDK・Flutter SDKパスなどを記録します。 |

DBのコレクション・ID参照は [DB構造図（HTML）](docs/database/database_v0.html) ／ [PNG](docs/database/database_v0.png) ／ [SVG](docs/database/database_v0.svg) を参照してください。詳細は [DB・API仕様書](docs/database/DB_v0.md) に記載しています。

現行のハッカソン版はGoogleログイン・HEIC・受信箱自動更新と作品既読・累計・タグ・描いた履歴を維持し、通知・退会・名前変更・サムネイル生成は対象外です。名前はランダム生成、メンテナンスはサーバー設定で切り替えます。

## タイムラインのタグ検索

`GET /api/v1/ideas?limit=10&tag=風景` は、掲載中かつ未削除のお題をタグ文字列の完全一致で絞り込みます。`tag` を省略すると全体を返します。タグは前後空白を除去し、1〜20文字で検証します。

レスポンスの `tags` は、選択タグやページに依存しない、掲載中のお題全体の重複なし・昇順のタグ文字列一覧です。既存のタグ保存形式を利用するためデータ移行は不要です。カーソルは選択タグに結び付き、タグを変更する場合はカーソルを省略して先頭から取得します。

タグ候補は各一覧リクエストで掲載中のお題の `tags` フィールドを読み取って集計します。件数が増えた場合はタグ集計の別管理・キャッシュを検討してください。利用環境では `firestore.indexes.json` の新しい複合インデックスをデプロイし、構築完了後にタグ検索を利用してください。

## 開発ドキュメント

- [環境構築](docs/environment.md)
- [起動・停止とトラブル対処](docs/startup.md)
- [変更履歴](docs/version/README.md)
