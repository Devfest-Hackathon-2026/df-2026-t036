# Firebase Hostingへの公開

公開ディレクトリは `flont/build/web` です。Firestoreのルール・インデックスは既存設定を維持し、Hostingだけを明示して公開します。

リポジトリ直下から実行します。

```powershell
# APIの公開先をビルド時に指定し、ローカル設定は上書きしない。
Set-Location flont
flutter build web --dart-define=API_BASE_URL=https://illustration-exchange-api-c3ovewncia-an.a.run.app
Set-Location ..
# ビルド済みのWebアプリだけを公開する。
npx firebase-tools deploy --only hosting --project project-025f8d03-50f2-4a97-a05
```

Firebase CLIのログインと、正しいFirebaseプロジェクトのWeb公開設定を含む `flont/firebase-config.local.json` が必要です。このJSONはビルドに同梱されるため、サービスアカウントの秘密鍵などを入れないでください。DEV_PREVIEWは指定せず、通常の認証を使います。

公開先は https://ewocuru.web.app です。Cloud RunのCORS_ORIGINSにはこのURLと対応するfirebaseapp.comのURLを登録します。Firebase AuthenticationのGoogleプロバイダーと承認済みドメインも確認してください。

公開後はGoogleログイン、お題投稿、作品送受信を実際のアカウントで確認します。ヘルスチェックや未認証での401確認だけでは、Cloud Run実行用サービスアカウントのFirestore・Storage・Vision権限は検証できません。

Cloud Run実行用サービスアカウントは `illustration-api-runtime@project-025f8d03-50f2-4a97-a05.iam.gserviceaccount.com` です。プロジェクトにはDatastore User、Firebase Authentication Viewer、Service Usage Consumer、作品バケットにはStorage Object Userを付与しています。サービスアカウント秘密鍵は発行していません。

公開先サイトIDは `ewocuru` です。`firebase.json` の hosting.site で指定します。旧サイトは削除していません。新ドメインの `ewocuru.web.app` と `ewocuru.firebaseapp.com` をFirebase Authenticationの承認済みドメインにも登録します。
