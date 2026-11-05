# Illustration Exchange

「描いてほしい」と「描いてみたい」をつなぐ、お絵描きマッチングサービスです。Flutter（`flont/`）とFastAPI（`back/`）を使って開発します。フロントエンドのフォルダ名は、このプロジェクトでは `flont` としています。

環境構築・起動・動作確認・Cloud Runへのデプロイ方法は [environment.md](docs/environment.md) を参照してください。

## 現在の実装範囲

現在は開発用のひな形として、FlutterのAPI接続確認画面、FastAPIの `/health`、DockerによるAPI起動、基本テストを用意しています。

仕様上の目標構成は、Flutter WebをFirebase Hosting、FastAPIをCloud Runに配置し、Firebase Authentication・Cloud Firestore・Cloud Storage・Cloud Schedulerを組み合わせる構成です。これらのクラウド連携や入会・退会、アイデア・作品の機能はまだ実装していません。

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
