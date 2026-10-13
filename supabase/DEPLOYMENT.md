# Supabase Edge Function deployment

The app authenticates users with Firebase Authentication. The `documents-api`
function verifies the Firebase ID token before reading or changing Supabase.
Do not put a Firebase service-account key or a Supabase service-role key in
Flutter.

## Required secrets

Set these secrets from the Supabase project directory:

```powershell
supabase secrets set `
  FIREBASE_PROJECT_ID=quanlytailieuhoctap-cbe2e `
  FIREBASE_STORAGE_BUCKET=quanlytailieuhoctap-cbe2e.appspot.com `
  FIREBASE_SERVICE_ACCOUNT_EMAIL=your-service-account@quanlytailieuhoctap-cbe2e.iam.gserviceaccount.com `
  FIREBASE_SERVICE_ACCOUNT_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----" `
  SUPABASE_SERVICE_ROLE_KEY=your-service-role-key
```

Supabase Storage is used for document files, so Firebase Storage and Firebase
service-account secrets are not required for file storage. The service-role key
is used only inside the Edge Function.

## Deploy

```powershell
supabase link --project-ref lxskxncjdshkmkscyztc
supabase db push
supabase functions deploy documents-api --no-verify-jwt
```

Run Flutter with the publishable key as a compile-time value:

```powershell
flutter run --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
```

The `publishableKey` value is intentionally not a secret. Never use a
`service_role` key with Flutter.

## API behavior

The function accepts the Firebase ID token in `x-firebase-token`. It provides:

- `GET /documents`: owned and shared documents, with search/filter support.
- `POST /documents`: create or update, restricted to owner/editor.
- `DELETE /documents/:id`: owner/editor.
- `POST /share`: owner/editor viewer/editor sharing by the recipient's email.
  The email must belong to a user who has already signed in to the app; the
  resolved Firebase UID is stored in `document_permissions`.
- `DELETE /share/:documentId/:userId`: owner-only revoke.
- `GET /documents/:id/file-url`: a 15-minute signed Supabase Storage URL.

The file URL is issued from the private Supabase Storage
`documents` bucket.
