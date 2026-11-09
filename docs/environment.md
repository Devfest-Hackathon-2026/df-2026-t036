# 開発環境の準備

日常の起動・停止・エラー対処は [起動方法](startup.md)、変更内容は [変更履歴](version/README.md) を参照してください。

## 必要なツール

| ツール | 基準 |
|---|---|
| Flutter | 3.47.9 stable（CIと同じ。Dartは同梱版） |
| Python | 3.11（API直接起動・pytest用） |
| Docker Desktop / Engine | Linuxコンテナー、Compose v2 |
| Google Cloud CLI | ローカルAPI用ADCの設定 |
| Git / Chrome | ソース管理・Flutter Web |
| Android SDK / Xcode | モバイル開発時のみ。iOSビルドにはmacOSが必要 |

リポジトリ直下で確認します。

```powershell
git --version
flutter --version
flutter doctor -v
python --version
docker version
docker compose version
gcloud --version
```

Docker Desktopを起動し、`docker version` にServer情報が表示されることを確認します。

## 設定ファイル

初回のみ、リポジトリ直下でコピーします。既存のlocalファイルは上書きしません。

```powershell
Copy-Item back/.env.example back/.local.env
Copy-Item flont/firebase-config.example.json flont/firebase-config.local.json
```

| ファイル | 設定内容 |
|---|---|
| `back/.local.env` | `GOOGLE_CLOUD_PROJECT`、`ARTWORK_BUCKET`、CORS等。APIだけが読む |
| `flont/firebase-config.local.json` | Firebase Web設定と `API_BASE_URL=http://localhost:8080`。Flutterだけが読む |
| ADCファイル | Google Cloud CLIがPCに保存する開発用認証。Dockerには別途読み取り専用で渡す |

APIとFlutterのプロジェクトIDを一致させます。ローカルでFlutterの可変ポートを使う場合は `back/.local.env` の `CORS_ALLOW_LOCALHOST=true` を設定します。固定ポート3000なら `CORS_ORIGINS=http://localhost:3000` を使用できます。

Firebase Web設定はアプリに同梱されます。ADCやサービスアカウント秘密鍵をFlutterのJSON、ソース、Dockerイメージへ入れないでください。localファイルと `.tmp/` はGit管理対象外です。実環境ではCORSに公開先のオリジンを明示します。

## Firebase・Google Cloudの初回設定

[Firebase認証の設定](back/firebase-auth.md) に従い、Googleログイン、承認済みドメイン、Firestore、IAMを準備します。画像送信には非公開Storageバケットと画像審査の設定も必要です。

```powershell
gcloud auth application-default login
gcloud auth application-default set-quota-project YOUR_PROJECT_ID
```

`gcloud auth login` とADCのログインは別です。APIはADCを使います。Dockerへの渡し方は [起動方法](startup.md#dockerでapiを起動) にまとめています。

## 依存関係

```powershell
python -m venv back/.venv
./back/.venv/Scripts/python.exe -m pip install -r back/requirements-dev.txt
cd flont
flutter pub get --enforce-lockfile
```

macOS/LinuxではPythonのパスを `back/.venv/bin/python` に読み替えます。Flutter依存を変更したブランチへ切り替えた場合も `flutter pub get --enforce-lockfile` を実行してください。

## 検証

リポジトリ直下から実行します。

```powershell
./back/.venv/Scripts/python.exe -m pip check
./back/.venv/Scripts/python.exe -m pytest back/tests -q
cd flont
flutter analyze
flutter test
flutter build web
```

Dockerイメージだけの検証は認証情報なしで実行できます。

```powershell
# リポジトリ直下で実行し、実行用依存関係の整合性も確認する。
docker build --platform linux/amd64 -t illustration-exchange-api:local ./back
docker run --rm illustration-exchange-api:local python -m pip check
```

2026-11-10のプロフィール機能検証では、pytest 198件成功、Flutter 173件成功・13件スキップ、静的解析成功を確認しました。件数は以降の変更で増減します。CIの最新結果を優先してください。

## デプロイ・関連資料

- [CI/CDとCloud Run](ci-cd.md)
- [Firebase Hosting](firebase-hosting.md)
- [ブランチ運用](branch-workflow.md)
- [API共通基盤](back/backend-foundation.md)
- [期限切れ作品の整理](back/artwork-expiry-cleanup.md)
- [Flutter詳細手順](../flont/README.md)

環境構築や通常の起動だけで本番へデプロイされることはありません。
