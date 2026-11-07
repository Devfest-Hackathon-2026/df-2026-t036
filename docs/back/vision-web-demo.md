# Vision API Webデモ（ローカル）

Flutter Webで画像を選び、ローカルFastAPIが画像を正規化して一時的にGCSへ置き、Cloud Vision SafeSearchの5カテゴリを画面に表示する。作品投稿やFirestoreへの作品保存は行わない。

## GCP側の準備

1. 開発用プロジェクトでCloud Vision APIを有効化し、課金を設定する。
2. 非公開GCSバケットを用意する。公開アクセス防止とUniform bucket-level accessを有効にする。
3. ローカル実行ユーザーにバケット単位で`Storage Object User`を付与する。VisionへGCS URIを渡すには、同じ認証主体にオブジェクト読み取り権限も必要。
4. プロジェクトで`Service Usage Consumer`が必要な場合は、ローカル実行ユーザーに付与する。

## 起動

1. `back/.env.example`を`back/.local.env`へコピーし、`GOOGLE_CLOUD_PROJECT`をGCPプロジェクトID、`VISION_DEMO_BUCKET`をバケット名に設定する。`back/.local.env`は共有・commitしない。
2. Google Cloud CLIでローカルADCを用意し、同じプロジェクトをquota projectに設定する。

   ```powershell
   gcloud init
   gcloud auth application-default login
   gcloud auth application-default set-quota-project YOUR_PROJECT_ID
   ```

3. `back`でPython環境を有効化し、依存関係を入れてAPIを起動する。

   ```powershell
   pip install -r requirements.txt
   uvicorn app.main:app --reload --port 8080
   ```

4. 別のPowerShellで`flont`へ移動し、依存関係を取得してChromeで起動する。ポート3000はFastAPIの既定CORS許可に合わせる。

   ```powershell
   flutter pub get
   flutter run -d chrome --web-port=3000
   ```

5. Googleログインし、**マイページ → 設定 → Vision API デモ**を開く。JPEG/PNG/HEIC/HEIFを選び、「判定する」を押す。

FastAPIは画像を一時prefixへアップロードし、Vision結果を返した後に削除する。削除失敗に備えてGCSのLifecycleルールで`vision-demo/`配下を短期間後に回収する設定を推奨する。Soft Deleteが有効な場合、削除済みデータは設定期間中保持される。

## 確認する結果

adult / spoof / medical / violence / racyのLikelihoodが画面に表示される。このデモは接続・UI確認用で、投稿の許可・拒否判定や作品保存には接続しない。

ローカルアプリの認証にはADCを使う。サービスアカウント鍵を作成したり、鍵をソース管理へ追加したりしない。

## アップロードの容量検査

画像本体は20 MiBまでとし、Cloud Storageへ送る前に実データの容量・形式・画素数・デコード可否と変換後容量を検査する。受信中もmultipartの付帯情報を含む本文全体を20 MiB + 64 KiBに制限し、超過時は413を返す。Content-Lengthの省略や偽装があっても実際の受信量で判定する。
