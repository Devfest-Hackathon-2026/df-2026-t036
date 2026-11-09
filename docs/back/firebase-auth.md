# Googleログインと初回登録

FlutterのGoogleログインでFirebase Authenticationのユーザーを作成し、取得したFirebase IDトークンをFastAPIへ送ります。APIは署名・期限・失効・Googleプロバイダーを検証し、同じUIDの `users` / `userSlots` / `userPins` をFirestoreトランザクションで初期化します。

Authへの登録とFirestore登録は別処理です。途中の通信断でAuthだけ作成されても、同じアカウントで登録を再試行できます。既存の表示名・累計・枠・ピンはリセットしません。初回201、再送200です。

## Firebase側の設定

1. Firebase Consoleで使用するプロジェクトを選択します。
2. Authenticationを開始し、ログイン方法のGoogleを有効にしてサポートメールを設定します。
3. Authenticationの承認済みドメインに `localhost` を追加します。本番では公開先ドメインも追加します。
4. Firestore Databaseを作成します。データ配置先のリージョンは作成前に確認してください。
5. プロジェクト設定からWebアプリを登録し、Firebase構成の `apiKey` / `appId` / `messagingSenderId` / `projectId` / `authDomain` を取得します。
6. Firebase CLIが使える環境で、リポジトリ直下からルールを反映します。

```powershell
firebase deploy --only firestore:rules --project YOUR_PROJECT_ID
```

お題TL・本人のお題履歴で使う複合インデックスも、次で反映します。

```powershell
firebase deploy --only firestore:indexes --project YOUR_PROJECT_ID
```

`firestore.rules` は全クライアントの直接読み書きを拒否します。Admin SDKの認可はFastAPIが担当します。この作業でCloud Storageの作成・画像機能はまだ必要ありません。

## ローカルAPI

ADCを設定します。ローカル開発ではFirestoreを操作できる開発用アカウントを使います。失効・無効化確認のためFirebase Authユーザーの取得権限も必要です（例：Firestoreの `roles/datastore.user` とAuthの `roles/firebaseauth.viewer`）。Cloud Runでは実行サービスアカウントへ必要な権限を付け、ADCを利用します。

```powershell
gcloud auth application-default login
gcloud auth application-default set-quota-project YOUR_PROJECT_ID
$env:GOOGLE_CLOUD_PROJECT = 'YOUR_PROJECT_ID'
$env:CORS_ALLOW_LOCALHOST = 'true'
./back/.venv/Scripts/python.exe -m pip install -r back/requirements-dev.txt
cd back
./.venv/Scripts/python.exe -m uvicorn app.main:app --reload --port 8080
```

ADC設定を変更したらAPIを再起動します。サービスアカウントの秘密鍵をFlutterへ渡したりGitへ追加したりしないでください。上記はPythonで直接起動する手順です。Dockerの具体的な起動コマンドは [起動方法](../startup.md) を参照してください。Dockerの場合は認証ファイルの読み取り専用マウントと `GOOGLE_APPLICATION_CREDENTIALS` / `GOOGLE_CLOUD_PROJECT` の受け渡しを別途設定する必要があります。

## Flutter Web

`flont/firebase-config.example.json` を `flont/firebase-config.local.json` へコピーし、取得したWebアプリの設定値へ置き換えます。Web設定はクライアント用の公開設定で、Admin SDKの秘密鍵とは異なります。プロジェクトIDはAPIと同一にします。

```powershell
cd flont
flutter pub get
flutter run -d chrome
```

Googleログイン後、登録完了でメイン画面へ進みます。マイページにはランダム表示名と初期値0の累計が表示されます。ページを再読み込みしても同じ名前が維持されます。ログイン後にAPI接続だけ失敗した場合は「ユーザー登録を再試行」を押します。

今回の実行・検証対象はWebです。Android/iOSでは各アプリをFirebaseに登録し、プラットフォームのFirebase設定を追加してください。GoogleプロバイダーのSHAフィンガープリントやURLスキームなども公式手順に従って設定する必要があります。

引数なしの自動読み込み、通常起動と開発プレビューの切り替え、APIの起動方法は [Flutter起動手順](../../flont/README.md) にまとめています。Web設定JSONはアプリへ同梱される公開設定です。起動引数を指定した項目はJSONより優先されます。

## 確認する内容

- AuthにGoogleユーザーが作成され、そのUIDでFirestoreの3文書が作成される。
- `users` はランダム表示名、active、3カウンター0、サーバー作成日時を保持する。
- `userSlots` は5枠のmap、`userPins` は上限5と空の配列を保持する。
- 再読み込み・再試行で名前や作成日時が変わらない。
- APIへ認証なしでアクセスすると401。停止状態なら403。
- `MAINTENANCE_MODE=true` で通常APIは503、`/health` は200。設定変更はAPIを再起動して反映する。

## 公式資料

- [FlutterのGoogleログイン](https://firebase.google.com/docs/auth/flutter/federated-auth)
- [Admin SDKのIDトークン検証](https://firebase.google.com/docs/auth/admin/verify-id-tokens)
- [Firestoreトランザクション](https://firebase.google.com/docs/firestore/manage-data/transactions)
