# Cloudinary Image Upload + Firestore URL Persistence (Implementation Notes)

This document explains what was implemented, why it was implemented that way, where data is stored, and how to debug typical failures in production.

The app uses:
- Firebase Auth (authentication)
- Cloud Firestore (database + access control)
- Cloudinary (image file storage)
- Flutter (client)

There is **NO Firebase Storage** usage for images in the updated implementation.

---

## 0) High-Level Architecture (What Happens When a User Uploads an Image)

For any image type (league image, sponsor image, profile image, team image), the flow is:

1) User picks image (FilePicker)
2) App uploads image to Cloudinary over HTTPS multipart/form-data
3) Cloudinary returns JSON containing `secure_url`
4) App saves that `secure_url` into Firestore in the correct document/field
5) UI re-renders and displays image from the URL
6) If URL is empty/null -> UI shows existing placeholder (cup/trophy icon)

Important:
- Cloudinary is a file store; Firestore stores the **URL** only.
- Firestore rules determine whether the URL write is allowed.
- Cloudinary preset determines whether the upload is allowed.

---

## 1) Cloudinary Configuration (Client)

### Required runtime defines
The Flutter code reads Cloudinary config using `--dart-define`:

- `CLOUDINARY_CLOUD_NAME`
- `CLOUDINARY_UNSIGNED_UPLOAD_PRESET`

Run example:
```bash
flutter run \
  --dart-define=CLOUDINARY_CLOUD_NAME=YOUR_CLOUD_NAME \
  --dart-define=CLOUDINARY_UNSIGNED_UPLOAD_PRESET=YOUR_PRESET
```

If these are missing:
- You will see a `StateError('Cloudinary is not configured...')`

### Security note
Unsigned presets are convenient but less secure (anyone with preset name can upload).
For best production security, implement signed uploads using a backend/worker (we added a worker route `POST /cloudinary/sign` in `worker/src/index.js`).

---

## 2) Firestore Storage Locations (Where URLs Are Saved)

### A) League Image + Sponsor Image
Document:
- `leagues/{leagueId}`

Fields:
- `leagueImageUrl: string`
- `sponsorImageUrl: string`

Updated by:
- `lib/features/leagues/logic/league_media_service.dart`

### B) Profile Image / User Avatar
Document:
- `users/{uid}`

Fields (we write multiple keys for compatibility across app versions):
- `photoUrl: string`
- `profileImageUrl: string`
- `teamImageUrl: string`
- `updatedAt: int`  ✅ (must match your current user rules schema)

Updated by:
- `lib/features/profile/presentation/profile_screen.dart`

### C) Team Image
Document:
- `leagues/{leagueId}/teams/{teamId}`

Field:
- `teamImageUrl: string`

Updated by:
- `lib/features/leagues/logic/team_media_service.dart`
- UI integration in `lib/features/leagues/presentation/add_teams_screen.dart`

---

## 3) Files Modified / Added (For Quick Review)

### Upload logic
- **UPDATED** `lib/features/leagues/logic/league_media_service.dart`
  - Replaced Firebase Storage upload with Cloudinary upload
  - Ensures draft league doc exists and passes Firestore create rules by including `organizerUid`
  - Saves `secure_url` to Firestore (`leagueImageUrl` / `sponsorImageUrl`)

- **ADDED** `lib/features/leagues/logic/team_media_service.dart`
  - Pick image
  - Upload to Cloudinary
  - Save to Firestore: `leagues/{leagueId}/teams/{teamId}.teamImageUrl`
  - Also supports clear image

- **UPDATED** `lib/features/profile/presentation/profile_screen.dart`
  - Adds pick+upload avatar
  - Writes to Firestore fields and updates `updatedAt`
  - Keeps existing UI layout; avatar is now tappable to upload

### Model
- **UPDATED** `lib/features/leagues/models/team.dart`
  - Added `teamImageUrl` field
  - Backward compatible reads from: `teamImageUrl`, `logoUrl`, `imageUrl`

### Display logic / thumbnails
Screens that were improved to safely load images and keep placeholders:
- `leagues_list_screen.dart`
- `league_detail_screen.dart`
- `admin_score_mgmt_screen.dart`
- `fixtures_screen.dart`
- `league_standings_screen.dart`
- `knockout_bracket_screen.dart`
- `admin_knockout_score_mgmt_screen.dart`

Common improvements:
- Cloudinary delivery optimization (inject `f_auto,q_auto` + sizing)
- Loading indicator on network images
- Error fallback icon (trophy/cup)
- Keep placeholder behavior when URL empty

### Firestore rules
- **UPDATED** `firestore.rules`
  - Allows user to update `photoUrl/profileImageUrl/teamImageUrl` + `updatedAt` on `/users/{uid}`
  - Keeps all other restrictions intact

---

## 4) Why Some Rules Changes Were Required

### A) League draft doc creation (before final league creation)
Your rules require:
```js
allow create: if signedIn() && request.resource.data.organizerUid == request.auth.uid
```

Previously `LeagueMediaService` draft creation did NOT include `organizerUid`, so:
- Cloudinary upload might succeed
- Firestore write fails with `permission-denied`

Fix:
`_ensureDraftLeagueDocExists()` now sets:
- `organizerUid`, `ownerUid`, `ownerId`, `organizerUserId` = current UID
- `isPrivate: true`
- `memberIds` includes current UID

### B) User doc updates for avatar URLs
Your user rules previously allowed updates only for:
- `teamName`, `updatedAt`, etc.

But profile avatar upload tries to write:
- `photoUrl/profileImageUrl/teamImageUrl`

So the update failed with permission denied.

Fix:
We added an extra update clause allowing exactly these keys + `updatedAt`.

---

## 5) Team Image Upload: How It Works in UI (AddTeamsScreen)

There are two categories on the add teams screen:

### A) Existing teams (already saved in Firestore)
- You can open a team details bottom sheet
- Tap Upload
- Upload is done using:
  `TeamMediaService.pickUploadAndSaveTeamImage(...)`
- It uploads to Cloudinary and saves URL directly to Firestore immediately.
- Local UI is updated with `copyWith(teamImageUrl: url)` so you see it immediately.

### B) New (temp) teams (not saved yet)
- These teams are in `_tempTeams` list only.
- We allow upload "preview" image:
  `TeamMediaService.pickAndUploadOnly(...)`
- The returned URL is stored in the temp map as `teamImageUrl`.
- When you press Save Teams:
  those new teams are written to Firestore with `teamImageUrl` included.

---

## 6) Common Failures and How to Debug

### Error: "Cloudinary is not configured"
Cause:
- `--dart-define` missing at runtime

Fix:
- Start app with:
  - `--dart-define=CLOUDINARY_CLOUD_NAME=...`
  - `--dart-define=CLOUDINARY_UNSIGNED_UPLOAD_PRESET=...`

---

### Error: Upload failed (HTTP 400/401) from Cloudinary
Causes:
- Wrong cloud name or preset name
- Upload preset is not unsigned
- File type blocked by preset
- Max file size exceeded by preset

Debug steps:
1) Check response error message (the code tries to parse `error.message`)
2) Validate preset in Cloudinary console:
   - Unsigned = ON
   - allowed formats include png/jpg/webp
   - max file size >= 5MB

---

### Error: Firestore permission-denied after upload success
Cause:
- Cloudinary upload succeeded but Firestore URL save is blocked by Firestore rules.

Debug:
1) Check Firestore logs / emulator / debug prints
2) Confirm user is signed in
3) Confirm league ownership logic is satisfied:
   - For `/leagues/{leagueId}` update: must be owner OR memberIds contains current UID
   - For `/leagues/{leagueId}/teams/{teamId}` write: must be owner (your rule)
4) Confirm required fields exist on create (especially `organizerUid` for league docs)

---

### Error: Team image not showing in fixtures/standings/admin screens
Causes:
- team doc missing `teamImageUrl`
- UI screen is reading team docs but they don't include that field yet (older data)
- screen is using local repo list but not refreshing remote team images

Fix:
1) Confirm Firestore doc:
   `leagues/{leagueId}/teams/{teamId}.teamImageUrl` is present
2) Re-open the screen (or refresh button)
3) Ensure your AddTeamsScreen saved teams with `teamImageUrl` OR existing team used Upload which saves immediately

---

### Build error: analyzer complaining about missing fields
Potential cause:
- If other parts of your code instantiate `Team(...)` directly without providing `teamImageUrl`, it should still compile because the constructor has a default `''`.
- If you have custom JSON decode logic elsewhere expecting only old keys, update it to accept `teamImageUrl`.

Search:
- `Team(` usage across project.
- any `fromRemoteMap` clones.

---

## 7) Performance Notes

### Why Cloudinary URL transform injection exists
We inject:
- `f_auto,q_auto` (automatic format + quality)
- plus small width/height for thumbnails

This improves:
- load speed
- bandwidth usage
- caching behavior

We do NOT redesign UI; we only optimize URLs and use `cacheWidth/cacheHeight` where safe.

---

## 8) Next Security Upgrade (Recommended)

Unsigned uploads are risky in public apps.

Recommended production upgrade:
- Use the Worker endpoint:
  `POST /cloudinary/sign` (already implemented in worker/src/index.js)
- Flutter requests a signature using Firebase ID token
- Flutter uploads to Cloudinary using signed params (no preset needed)

If you want this:
Paste the exact files you want migrated from unsigned -> signed:
- `LeagueMediaService`
- `TeamMediaService`
- `ProfileScreen`
and we will update them safely.

