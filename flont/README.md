# Flutterの起動方法

## 初回設定

リポジトリ直下で実行します。

```powershell
Copy-Item flont/firebase-config.example.json flont/firebase-config.local.json
cd flont
flutter pub get
```

既にlocalファイルがある場合はコピーせず、そのファイルを使用してください。`firebase-config.local.json` にFirebaseのWebアプリ設定と `API_BASE_URL` を入力します。Googleログイン・Firestore・開発用認証の初回設定は [Firebase認証の設定手順](../docs/back/firebase-auth.md) を参照してください。

このJSONはWeb公開設定としてアプリに同梱されます。Google CloudのADCやサービスアカウント秘密鍵は入れないでください。Gitでは除外されています。ビルドにも必要なので、別PC・CIでは事前に配置してください。プレビューだけの場合はexampleのコピーで構いません。

## 1. 通常起動：Googleログイン・DB接続

先に別のターミナルでAPIを起動します。Pythonの仮想環境・依存関係は [環境構築](../docs/environment.md) を参照してください。

リポジトリ直下から実行：

```powershell
cd back
./.venv/Scripts/python.exe -m uvicorn app.main:app --reload --port 8080
```

先に `back/.env.example` を `back/.local.env` へコピーし、`GOOGLE_CLOUD_PROJECT` をFirebaseと同じIDに、ローカル開発では `CORS_ALLOW_LOCALHOST=true` に設定してください。既存のlocalファイルは上書き不要です。直接起動時はこのファイルを自動で読み込みます。

`CORS_ALLOW_LOCALHOST=true` は開発時のlocalhost・127.0.0.1の可変ポートを許可します。本番では指定せず、`CORS_ORIGINS` に公開先を明示してください。

コンテナの場合はリポジトリ直下で docker compose up --build -d を実行します。Composeが同じlocalファイルを環境変数として渡します。Google Cloud認証のADCは別途読み取り専用マウントなどが必要です。Python版とコンテナ版は8080番を使うので、同時起動しないでください。

もう一方のターミナルで `flont` に移動し、実行：

```powershell
flutter run
```

デバイス選択が表示されたらChromeを選択します。現在の認証確認対象はWebです。Chromeを明示する場合は `flutter run -d chrome` でも同じ動作です。Android/iOSの認証には別途プラットフォーム設定が必要です。

FirebaseとAPI接続先は `firebase-config.local.json` から自動で読み込みます。`--dart-define` または `--dart-define-from-file` を渡した項目はそちらを優先します。

固定ポートで起動したい場合：

```powershell
flutter run -d chrome --web-hostname localhost --web-port 3000
```

Googleでログイン後、APIが初回登録または既存情報の取得を行います。既存アカウントで再ログインしても表示名・累計は初期化しません。

## 2. デザイン確認：認証なしプレビュー

`flont` で実行：

```powershell
flutter run -d chrome --dart-define=DEV_PREVIEW=true
```

API・Googleログインを使わず、サンプルのユーザー情報で画面を表示します。「プレビュー」のバナーが目印です。DB接続・登録・ログアウトの動作確認には通常起動を使用してください。プレビューはdebug時のみ有効です。

### 受信画像保存のローカル確認

1. 上記のプレビューコマンドでChromeを起動します。
2. 下部ナビゲーションの「受信箱」を開き、サンプル作品を選択して詳細画面を表示します。
3. 画像の読み込み後、「画像保存」を押します。長押しメニューからも選べます。
4. ブラウザーのダウンロード一覧またはダウンロード先に`artwork.png`が作成され、画像を開けることを確認します。認証なしプレビューはローカル生成PNGを使います。

本番相当のWebPファイル名・MIMEを確認する場合は、通常のGoogleログインでローカルAPIへ接続し、受信した作品を開いて同様に保存します。通常利用での画像保存は`artwork.webp`としてダウンロードされます。実作品の確認にはFirebase・Firestore・Cloud Storage・APIの開発環境設定が必要です。プレビューだけではサーバー認可や実WebP配信は検証できません。

## 停止・設定変更

Flutterは `q`、APIは `Ctrl+C` で停止します。通常起動とプレビューを切り替えるときや、JSON・起動引数を変更したときはFlutterを停止して起動し直してください。APIの環境変数・ADCを変更した場合はAPIも再起動します。

## エラーの確認

| 表示・症状 | 確認すること |
|---|---|
| local.jsonを読み込めない・設定を入力するよう表示される | `flont/firebase-config.local.json` の配置・JSON形式・5つのFirebase設定値 |
| 時間をおいて再試行 | APIログ。`DefaultCredentialsError` なら開発用ADCを設定 |
| quota projectの警告 | `gcloud auth application-default set-quota-project YOUR_PROJECT_ID` を実行後、APIを再起動 |
| Googleログイン後に進めない | APIの起動、JSON内のAPI_BASE_URL、CORS_ALLOW_LOCALHOST、Firebase・Firestore権限 |
| ポート使用中 | 以前のFlutter/APIを停止するか別ポートを使用 |
| Runtime.evaluate / Cannot find context | Flutterを停止して、生成されたChromeを開き直す |

共通デザインは [design.md](design.md)、実装は [lib/theme/app_theme.dart](lib/theme/app_theme.dart) を参照してください。

## APIとFlutterの設定の分離

APIは `back/.local.env` または環境変数から設定を取得します。環境変数が優先されます。`GOOGLE_CLOUD_PROJECT` には利用するFirebaseプロジェクトIDを明示してください。

Flutterは `flont/firebase-config.local.json` を使用します。APIはこのJSONを読み込まず、Composeでも共有しません。同じFirebaseプロジェクトを利用する場合は、両方に同じプロジェクトIDをそれぞれ設定してください。APIのenv自動読み込みとComposeの `env_file` は引き続き利用できます。
