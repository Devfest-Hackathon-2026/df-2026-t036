# ローカルの起動方法

初回は [環境構築](environment.md) を済ませてください。以下はWindows PowerShellでリポジトリ直下から実行します。

## デザインだけ確認する

APIやGoogleログインを使わずサンプルデータで表示します。保存・認証・実DB接続の確認には使えません。

```powershell
cd flont
flutter pub get --enforce-lockfile
flutter run -d chrome --dart-define=DEV_PREVIEW=true
```

## DockerでAPIを起動

Docker Desktopを起動し、`back/.local.env` を用意します。Googleログイン・DB接続には、PC側のADCをコンテナにも渡す必要があります。

初回のみ、認証ファイルのパスを設定したローカル専用Compose上書きファイルを作成します。このファイルには認証ファイルの内容をコピーしません。

```powershell
$adcFile = Join-Path $env:APPDATA 'gcloud/application_default_credentials.json'
if (-not (Test-Path -LiteralPath $adcFile)) {
    throw '先に gcloud auth application-default login を実行してください。'
}
New-Item -ItemType Directory -Force .tmp | Out-Null
# PCのADCを読み取り専用でマウントし、コンテナ内の参照先を指定する。
$overrideConfig = @{
    services = @{
        api = @{
            environment = @{ GOOGLE_APPLICATION_CREDENTIALS = '/run/google/adc.json' }
            volumes = @(@{
                type = 'bind'
                source = $adcFile
                target = '/run/google/adc.json'
                read_only = $true
            })
        }
    }
}
$overrideConfig | ConvertTo-Json -Depth 8 |
    Set-Content -Encoding UTF8 .tmp/compose-adc.local.json
```

macOS/LinuxではADCの標準パスは `~/.config/gcloud/application_default_credentials.json` です。上記JSONと同じ構造の上書きファイルを作り、`source` にその絶対パスを指定してください。

毎回の起動：

```powershell
docker compose -f compose.yaml -f .tmp/compose-adc.local.json up -d --build
docker compose -f compose.yaml -f .tmp/compose-adc.local.json ps
curl.exe http://localhost:8080/health
```

- API仕様画面： http://localhost:8080/docs
- 正常時のhealth： `{"status":"ok"}`
- `/health` は外部接続を行わないため、Firebase・DB権限までは検証しません。
- `docker compose up` だけで作り直すとADCのマウントが外れる場合があります。以降も同じ2つの `-f` を指定します。

## PythonでAPIを起動（Dockerの代替）

PC側にADCと仮想環境を用意してから実行します。Docker版と同時にポート8080を使わないでください。

```powershell
cd back
./.venv/Scripts/python.exe -m uvicorn app.main:app --reload --port 8080
```

macOS/Linuxでは `.venv/bin/python` を使用します。

## 通常のFlutter Webを起動

APIとは別のターミナルで実行します。

```powershell
cd flont
flutter pub get --enforce-lockfile
flutter run -d chrome --web-hostname localhost --web-port 3000
```

`firebase-config.local.json` のFirebase設定とAPI接続先を使用します。通常利用では `DEV_PREVIEW=true` を付けません。

AndroidエミュレーターではAPI接続先を `http://10.0.2.2:8080`、実機では同じネットワークのPCのLAN IP等に変更してください。詳細は [Flutter起動手順](../flont/README.md) を参照してください。

## 停止・ログ・設定変更

```powershell
# APIログを確認する。終了はCtrl+C。
docker compose -f compose.yaml -f .tmp/compose-adc.local.json logs -f api
# APIを停止する。
docker compose -f compose.yaml -f .tmp/compose-adc.local.json down
# .local.envや認証のマウント変更後に作り直す。
docker compose -f compose.yaml -f .tmp/compose-adc.local.json up -d --build --force-recreate
```

Flutterは起動したターミナルで `q`、Python APIは `Ctrl+C` で停止します。FlutterのJSONや起動引数の変更後はアプリを再起動します。

## よくある失敗

| 症状 | 対処 |
|---|---|
| Dockerのpipeが見つからない | Docker Desktopを起動し、Linuxエンジンの起動完了を待つ |
| 「時間をおいて再試行」、ログに `DefaultCredentialsError` | PCでADCを設定し、Dockerへ読み取り専用で渡して作り直す |
| 認証の期限切れ | ADCへ再ログインしAPIを作り直す |
| healthは成功するがログインできない | APIログ、FirebaseプロジェクトID、IAM、ADC、CORSを確認 |
| `url_launcher` 等のパッケージが見つからない | `flont` で `flutter pub get --enforce-lockfile` |
| ポート8080が使用中 | 以前のPython APIまたはコンテナを停止 |
| プレビューでは編集が保存されない | プレビューは表示確認用。通常ログインで確認 |
