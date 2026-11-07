# Vision API Webデモ（ローカル）

## 処理の順序

1. Flutterで形式・容量を確認し、表示可能な静止画を長辺2560px以下のPNGへ変換する。
2. 「判定する」で認証トークンと画像をFastAPIへ送信する。
3. FastAPIで受信容量・実形式・画素数・デコード可否を再検証し、向き補正・メタデータ除去・JPEG/PNG変換を行う。
4. 検証済みの画像バイト列をCloud Vision SafeSearchへ直接渡し、結果を返す。

Vision判定用のCloud Storage一時保存・削除・公開URLは不要。作品の閲覧権限は変更しない。これは判定デモであり、作品の正式保存・Firestoreへの投稿確定はまだ接続していない。

## 起動

1. Google CloudプロジェクトでVision APIと課金を有効化する。
2. `back/.env.example`を`back/.local.env`へコピーし、`GOOGLE_CLOUD_PROJECT`を設定する。バケット設定・Storage権限は不要。
3. `gcloud auth application-default login` と `gcloud auth application-default set-quota-project YOUR_PROJECT_ID` でADCを設定する。
4. `back`で依存をインストールし、`uvicorn app.main:app --reload --port 8080` を起動する。
5. `flont`で `flutter pub get` と `flutter run -d chrome --web-port=3000` を実行する。
6. ログイン後、マイページ → 設定 → Vision API デモを開く。

## 容量・形式

入力はJPEG/PNG/HEIC/HEIF、画像本体は20 MiBまで。HEIC/HEIFは端末のデコーダーが対応する場合のみFlutterで変換可能。非対応環境ではJPEG/PNGへの選び直しを案内する。アニメーション・4000万画素超過は拒否する。

FastAPIの受信本文はmultipart付帯情報を含め20 MiB + 64 KiBまで。Content-Lengthが省略・偽装されても実受信量で制限する。変換後の直接送信画像は7,000,000バイトまでとし、Base64化してもVisionの10MB JSON制限に余裕を持たせる。

公式の制限: https://docs.cloud.google.com/vision/quotas

## 判定基準

判定対象のadult・spoof・violenceがすべてPOSSIBLE以下ならapproved、1カテゴリでもLIKELY以上ならrejected。不明・欠損は、拒否カテゴリがない場合retry_requiredとする。応答のdecisionとpolicyVersionで確認できる。判定デモなので作品の正式保存は行わない。

medicalとracyは表示用に取得するが、判定から除外する。両カテゴリの高い値・不明・欠損で投稿を拒否または保留にしない。ポリシーはpossible-allowed-v2。
