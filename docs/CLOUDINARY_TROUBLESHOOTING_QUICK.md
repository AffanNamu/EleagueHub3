# Cloudinary Upload Troubleshooting (Quick)

## 1) Verify defines
If you see:
- "Cloudinary is not configured"

Run with:
```bash
flutter run \
  --dart-define=CLOUDINARY_CLOUD_NAME=... \
  --dart-define=CLOUDINARY_UNSIGNED_UPLOAD_PRESET=...
```

## 2) Verify Firestore rules deployed
If you see:
- permission-denied when saving photo URL

Deploy:
```bash
firebase deploy --only firestore:rules
```

## 3) Verify Firestore data
### League images:
- leagues/{leagueId}.leagueImageUrl
- leagues/{leagueId}.sponsorImageUrl

### Team images:
- leagues/{leagueId}/teams/{teamId}.teamImageUrl

### User avatar:
- users/{uid}.photoUrl (and/or profileImageUrl/teamImageUrl)

## 4) Cloudinary upload preset must be unsigned
Cloudinary Console → Settings → Upload → Upload presets

Must allow:
- unsigned upload
- file types: jpg/jpeg/png/webp/gif
- max 5MB or more

## 5) Typical error mapping
- HTTP 400 from Cloudinary: wrong preset / format / size
- HTTP 401 from Cloudinary: wrong cloud name / preset not unsigned
- Firestore permission-denied: rules not updated OR ownership not satisfied

