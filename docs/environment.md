# Illustration Exchange 環境構築手順

Flutter + FastAPI の開発用ひな形です。指定に合わせてフロントエンドのディレクトリ名は `flont` としています。

## 構成

バックエンドの共通処理・環境変数・API追加時の規約は [FastAPI共通基盤](back/backend-foundation.md) を参照してください。

```text
flont/         Flutter（Android・iOS・Web）、API接続確認画面
back/          FastAPI、テスト、Cloud Run対応Dockerfile
compose.yaml   ローカルAPIのDocker起動設定
readne.md      本手順書
```

## 1. 必要なツール

- Git
- Flutter 3.38.7 stable（Dart 3.10.7同梱、初期生成に使用したバージョン）
- Python 3.11（Dockerを使わずAPIを起動する場合）
- Docker Desktop / Docker Engine + Compose v2（Linuxコンテナーを使用）
- Chrome（Web実行）、Android Studio / Android SDK（Android実行）
- macOS + Xcode（iOSビルドには必須。Windowsではビルド不可）
- Google Cloud CLI（Cloud Runへデプロイする場合）

ツールをインストールしてPATHを通したら、ターミナルで確認します。

```powershell
git --version
flutter --version
flutter doctor -v
python --version
docker version
docker compose version
```

`flutter doctor` のうち使用するプラットフォームの問題を解消してください。Androidでは `flutter doctor --android-licenses` も実行します。DockerはCLIの存在に加え、Desktopを起動して `docker version` にServer情報が表示されることを確認します。

## 2. リポジトリの取得

```powershell
git clone https://github.com/outsidewhite/-Illustration-exchange.git
cd ./-Illustration-exchange
```

以降、特に記載がないコマンドはリポジトリ直下で実行します。既にローカルにこの構成がある場合はclone不要です。リモートへ未反映の場合は管理者が先にコミット・pushする必要があります。

## 3. APIをDockerで起動（推奨）

```powershell
docker compose up --build -d
docker compose ps
curl.exe http://localhost:8080/health
```

macOS/Linuxでは `curl.exe` を `curl` に読み替えてください。

- 起動確認: http://localhost:8080/health → `{"status":"ok"}`
- API仕様・実行画面: http://localhost:8080/docs
- ログ: `docker compose logs -f api`
- 停止: `docker compose down`
- コード変更後: `docker compose up --build -d`（自動リロードなし）

## 4. APIをPythonで起動（Dockerの代替）

Windows PowerShell:

```powershell
python -m venv back/.venv
./back/.venv/Scripts/python.exe -m pip install -r back/requirements-dev.txt
cd back
./.venv/Scripts/python.exe -m uvicorn app.main:app --reload --host 0.0.0.0 --port 8080
```

macOS/Linux:

```sh
python3 -m venv back/.venv
back/.venv/bin/python -m pip install -r back/requirements-dev.txt
cd back
.venv/bin/python -m uvicorn app.main:app --reload --host 0.0.0.0 --port 8080
```

Docker版とPython版は同じポートを使用するため、一方のみ起動します。終了は `Ctrl+C` です。

## 5. Flutter Webを起動

通常のGoogleログイン・DB接続と、認証なしのデザインプレビューは [Flutter起動手順](../flont/README.md) にまとめています。初回のFirebase・ADC設定は [Firebase認証の設定手順](back/firebase-auth.md) を参照してください。

`flont/firebase-config.local.json` を用意すれば、Chromeを選んで `flutter run` だけで設定を読み込めます。通常利用にはAPIも必要です。Flutterの可変ポートを使う場合は、API起動前に開発環境限定で `CORS_ALLOW_LOCALHOST=true` を設定してください。設定例・固定ポートでの起動・停止・エラー対処もFlutter起動手順に記載しています。

## 6. モバイルで起動

```powershell
cd flont
flutter devices
flutter run -d <DEVICE_ID> --dart-define=API_BASE_URL=http://10.0.2.2:8080
```

- Android標準エミュレーター: ホストPCのAPIは `http://10.0.2.2:8080`。
- iOSシミュレーター: `http://localhost:8080`。HTTPがOS設定で拒否される場合はHTTPSのAPIを使用してください。
- 実機: 同じネットワーク上のPCのLAN IP、またはCloud RunのHTTPS URL。ファイアウォールで開発用ポートへの接続が許可されている必要があります。
- AndroidのHTTP許可はdebugビルドに限定しています。releaseビルドにはHTTPSのAPIを指定してください。

`--dart-define` を変更した場合はアプリを停止して起動し直します。API_BASE_URLに秘密情報を含めないでください。

## 7. 検証

Python依存関係をインストールした後、リポジトリ直下で実行します。

```powershell
cd back
./.venv/Scripts/python.exe -m pytest
cd ../flont
flutter analyze
flutter test
flutter build web --dart-define=API_BASE_URL=https://YOUR_API_URL
```

macOS/LinuxのPython実行パスは `.venv/bin/python` です。最後のURLは実際のAPIに置き換えます。

## 8. Cloud RunへDockerイメージをデプロイ

課金が有効なGoogle Cloudプロジェクトと、API有効化・Artifact Registry・Cloud Build・Cloud Run・サービスアカウント使用の権限を用意します。以下はPowerShellの例です。値を自分の環境に置き換えてください。

```powershell
$ProjectId = "YOUR_PROJECT_ID"
$Region = "asia-northeast1"
$Repository = "illustration-exchange"
$Service = "illustration-exchange-api"
$Image = "${Region}-docker.pkg.dev/${ProjectId}/${Repository}/${Service}:v1"

gcloud auth login
gcloud config set project $ProjectId
gcloud services enable run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com
# 同名リポジトリが既にある場合は作成不要。
gcloud artifacts repositories create $Repository --repository-format=docker --location=$Region
# back/Dockerfileを使用してCloud Build上でビルドする。
gcloud builds submit ./back --tag $Image
# この雛形のhealth APIをFlutterから直接呼び出せるよう、公開サービスとして作成する。
gcloud run deploy $Service --image $Image --region $Region --port 8080 --allow-unauthenticated --set-env-vars "CORS_ORIGINS=https://YOUR_FRONTEND_HOST"
gcloud run services describe $Service --region $Region --format="value(status.url)"
```

取得したURLの `/health` にアクセスして確認します。Flutterには `--dart-define=API_BASE_URL=https://取得したURLのホスト名` を渡します。ローカルFlutter WebからCloud Runへ接続する場合は、CORS_ORIGINSを `http://localhost:3000` に設定してください。公開用Webの許可元にはパスや末尾スラッシュを含めません。

コンテナーは `0.0.0.0` とCloud Runが渡す `PORT` で待機します。公開設定はこの疎通確認API向けです。ユーザー情報やイラストを扱う機能を追加する際にはアプリケーションの認証・認可を実装してください。クラウドへの実際のデプロイはこの初期構築には含めていません。

## 参考資料

- [Flutterのインストール](https://docs.flutter.dev/install)
- [Flutterのネットワーク通信](https://docs.flutter.dev/cookbook/networking/fetch-data)
- [FastAPI Docker構成](https://fastapi.tiangolo.com/deployment/docker/)
- [Cloud Runコンテナー実行契約](https://docs.cloud.google.com/run/docs/container-contract)
- [Cloud Run向けイメージのビルド](https://docs.cloud.google.com/run/docs/building/containers)

## 初期構築時の検証結果（2026-11-05）

- Flutter 3.38.7 / Dart 3.10.7、Python 3.11.9で確認。
- `flutter pub get`、`flutter analyze`、`flutter test`（1件）、`flutter build web` が成功。
- APIのpytestは2件成功（依存ライブラリ由来の非推奨警告1件あり）。
- `docker compose config --quiet`、Dockerイメージのビルド・起動が成功。
- コンテナーがhealthyになり、`http://localhost:8080/health` が `{"status":"ok"}` を返すことを確認。
- Webビルド時に未使用のCupertinoIconsフォントに関する警告が出るが、ビルドは成功。
- Android/iOSのビルド、実機確認、Cloud Runへのデプロイは未実施。
- Gitのoriginは指定のGitHub URLに設定済み。コミット・pushは未実施。
