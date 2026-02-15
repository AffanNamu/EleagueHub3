# Production Cloudinary Image System Guide (Flutter + Firebase Auth + Firestore)

This document explains **from zero** what was implemented/changed in the app to support:
- Cloudinary as the **only** image storage provider (no Firebase Storage)
- Firestore storing **URLs only**
- Profile image becoming the **same image shown everywhere** (fixtures/standings/admin/knockout/etc)
- League + Sponsor images continuing to work (do NOT remove them)

It also includes a production debugging guide so another engineer can quickly diagnose failures.

---

## 0) What This App Uses (Image-Related)

### Authentication
- **Firebase Auth** (user identity)

### Database
- **Cloud Firestore** (stores metadata + image URLs)

### File Storage (Images)
- **Cloudinary** (stores the image bytes)
- Firestore stores only `secure_url` strings returned from Cloudinary

### Important: No Firebase Storage
All image uploads use Cloudinary HTTP APIs.

---

## 1) Firestore Structure (Where URLs Live)

### A) User Profile Image
Document:
- `users/{uid}`

Fields written (for compatibility):
- `photoUrl: string`
- `profileImageUrl: string`
- `teamImageUrl: string`
- `updatedAt: int` (milliseconds)

✅ When a user uploads an avatar, we set all 3 URL fields to the same Cloudinary URL.

---

### B) League Main Image + Sponsor Image (DO NOT REMOVE)
Document:
- `leagues/{leagueId}`

Fields:
- `leagueImageUrl: string`
- `sponsorImageUrl: string`

✅ LeagueDetail hero renders both:
- `leagueImageUrl` as main banner background
- `sponsorImageUrl` as small bottom-right badge

---

### C) Team Image (League Team Logo)
Document:
- `leagues/{leagueId}/teams/{teamId}`

Field:
- `teamImageUrl: string`

✅ However, our current policy is:
- For UID-based teams (teamId looks like Firebase UID), the **user profile image** is authoritative.
- This means even if team doc has a logo, user avatar can override (depending on the resolver logic in repository/screen).

---

## 2) Cloudinary Configuration (Required for Production)

The Flutter app reads Cloudinary config using **compile-time** values:

- `CLOUDINARY_CLOUD_NAME`
- `CLOUDINARY_UNSIGNED_UPLOAD_PRESET`

Because these are compile-time (`String.fromEnvironment`), they must be passed during the CI build step.

Your values:
- Cloud name: `dbw9zpkxi`
- Unsigned preset: `eSportlyic_unsigned` (case-sensitive)

---

## 3) Cloudinary Console Setup (Unsigned Preset)

In Cloudinary Console:
1. Settings → Upload
2. Upload presets → Add upload preset
3. Must be:
   - Signing Mode: **Unsigned**
   - Preset name: `eSportlyic_unsigned`
   - Allowed formats: `jpg,jpeg,png,webp` (and gif if needed)
   - Max file size: >= 5MB (app enforces 5MB)
4. Save

---

## 4) CI/CD: GitHub Actions Build Must Inject dart-defines

### File updated
- `.github/workflows/android.yml`

### What we changed
We modified the `flutter build apk` command to include:

- `--dart-define=CLOUDINARY_CLOUD_NAME=...`
- `--dart-define=CLOUDINARY_UNSIGNED_UPLOAD_PRESET=...`

So the produced APK contains Cloudinary config and uploads work in production installs.

If this step is missing, the app will throw:
- `StateError('Cloudinary is not configured.')`

---

## 5) Upload Flow (Profile Avatar Upload)

### File
- `lib/features/profile/presentation/profile_screen.dart`

### Flow
1. User picks an image via `FilePicker`
2. App uploads the file to Cloudinary using multipart HTTP POST:
   - `https://api.cloudinary.com/v1_1/<cloudName>/image/upload`
   - includes `upload_preset` (unsigned preset)
3. Cloudinary returns JSON, we read `secure_url`
4. We save `secure_url` into Firestore:
   - `users/{uid}` fields: `photoUrl`, `profileImageUrl`, `teamImageUrl`, `updatedAt`
5. UI updates immediately

### Constraints + safety
- Maximum file size: **5MB**
- Network timeout guarded
- Failures show snack messages; app does not crash

---

## 6) Global Policy: “Profile Image == Team Image Everywhere”

### Goal
When a user updates profile avatar, it should show everywhere:
- Fixtures
- Standings
- Admin score management
- Knockout bracket
- Match detail
- Participants
- Space screens

### How we implemented this (core logic)
**We hydrate team images from `users/{uid}`** when teamId looks like a Firebase UID.

#### File (core)
- `lib/features/leagues/data/leagues_repository_local.dart`

#### `getTeams(leagueId)` behavior
1. Load `leagues/{leagueId}/teams`
2. For each team:
   - build `Team` objects
3. Identify team IDs that “look like” Firebase UID:
   - `id.trim().length > 20`
4. Fetch users in chunks of 10 using `whereIn`:
   - `users` collection
   - `FieldPath.documentId whereIn [chunk]`
5. Extract best image URL priority from user doc:
   1. `teamImageUrl`
   2. `profileImageUrl`
   3. `photoUrl`
6. Overwrite `Team.teamImageUrl` for those UID teams

✅ Result: UI can keep using `team.teamImageUrl` normally, and it will contain the correct avatar for UID-based teams.

---

## 7) UI Display Rules (No Redesign + Fast + Safe)

Across screens we used the same safe behavior:
- If URL is empty or not http/https → show existing placeholder icon
- If URL exists:
  - render `Image.network(url)`
  - use loadingBuilder and errorBuilder
  - use Cloudinary transform injection when URL is Cloudinary:
    - `f_auto,q_auto` + width/height + crop
  - use cacheWidth/cacheHeight for better performance

✅ This preserves existing design and avoids crashes.

---

## 8) Screens Updated (What Changed)

### A) Standings
- `lib/features/leagues/presentation/league_standings_screen.dart`
Best-effort resolves team avatars and shows them in small strip using safe placeholder.

---

### B) Fixtures
- `lib/features/leagues/presentation/fixtures_screen.dart`
Uses hydrated team images and ensures missing UID avatars are fetched from user docs.

---

### C) Admin Score Management
- `lib/features/leagues/presentation/admin_score_mgmt_screen.dart`
Same as fixtures but inside admin scoring UI.

---

### D) Knockout Bracket
- `lib/features/leagues/presentation/knockout_bracket_screen.dart`
Added:
- small team icons in match rows and final showcase tiles
- best-effort fetch from users for UID teams
- safe placeholders

#### “3rd Place” stability fix
The bracket screen selects the best 3rd-place match by preferring:
- match where both teams are assigned (not TBD)
- otherwise fallback to first

This prevents confusing UI when multiple docs exist or incomplete placeholder match exists.

---

### E) Admin Knockout Score Management
- `lib/features/leagues/presentation/admin_knockout_score_mgmt_screen.dart`
Added small team thumbs next to home/away names.
Also supports UID-based hydration by loading images map and fetching from `users` when needed.

---

### F) Match Detail
- `lib/features/leagues/presentation/match_detail_screen.dart`
Added small team icons in header, using hydrated `Team.teamImageUrl`.

---

### G) League Detail (League image + sponsor image must remain)
- `lib/features/leagues/presentation/league_detail_screen.dart`
Preserved:
- League hero with main image + sponsor badge

Fixed/improved:
- Cloudinary delivery optimization for league/sponsor images
- Safe image loading + placeholder
- Upcoming fixtures list now shows team avatars as small icons

---

### H) League Space Room (voice room)
- `lib/features/leagues/presentation/league_space_room_screen.dart`
Added:
- small avatar icons next to users in requests/speakers/host header
- avatars resolved from user profiles

---

### I) Participants
- `lib/features/leagues/presentation/league_participants_screen.dart`
Added:
- user avatar rendering using profile URLs
- keeps existing organizer/person placeholder icons

---

## 9) Firestore Rules Requirements (Most Common Production Failure)

Even if Cloudinary upload succeeds, Firestore save can fail with:
- `permission-denied`

### Required rules support
Ensure your Firestore rules allow:
- `users/{uid}` update of:
  - `photoUrl`, `profileImageUrl`, `teamImageUrl`, `updatedAt`
- `leagues/{leagueId}` update of:
  - `leagueImageUrl`, `sponsorImageUrl` (for league organizer/admin)

If rules are not updated/deployed, you will see:
- Cloudinary upload success
- then Firestore save fails → image never appears in the app

---

## 10) Troubleshooting Guide (Production)

### Problem A: “Cloudinary is not configured”
**Cause**
- APK built without dart-defines

**Fix**
- Ensure GitHub Actions build step includes:
  - `--dart-define=CLOUDINARY_CLOUD_NAME=dbw9zpkxi`
  - `--dart-define=CLOUDINARY_UNSIGNED_UPLOAD_PRESET=eSportlyic_unsigned`
- Rebuild + reinstall APK

---

### Problem B: Cloudinary upload HTTP 400/401
**Cause**
- preset name wrong OR not unsigned OR blocked format/size

**Fix**
- verify preset `eSportlyic_unsigned` is unsigned
- allowed formats include your chosen image type
- max file size >= 5MB

---

### Problem C: Upload works but image does not show anywhere
**Cause**
- Firestore write blocked by rules OR save failed

**Debug**
- Open Firestore:
  - `users/{uid}` should contain `photoUrl/profileImageUrl/teamImageUrl`
- If not present → check Firestore logs and rules

---

### Problem D: Some teams show avatar, others show placeholder
**Cause candidates**
1. Team ids are not Firebase UIDs (policy assumes UID-based teams for profile-image)
2. User doc missing URL fields
3. Network failures in chunked user lookups

**Fix**
- verify `FixtureMatch.homeTeamId/awayTeamId` matches `users/{uid}` ids
- ensure user profile doc has avatar fields

---

### Problem E: Cloudinary URL not optimized / slow
**Cause**
- URL is not Cloudinary OR is already transformed

**Fix**
- ensure stored URL is `secure_url` from Cloudinary
- optimization only applies when URL contains:
  - `res.cloudinary.com` and `/image/upload/`

---

## 11) Testing Checklist (End-to-End)

1. Install APK from GitHub Actions artifact
2. Sign in
3. Upload avatar in Profile
4. Verify Firestore `users/{uid}` updated with Cloudinary URL
5. Verify UI:
   - Fixtures: both teams show correct avatar
   - Standings: avatars show
   - Admin score mgmt: avatars show
   - Knockout bracket: avatars show
   - Match detail: header shows avatars
   - Participants: avatars show
   - Space: host/speakers/requesters show avatars

---

## 12) Security Note (Unsigned Upload Risk)

Unsigned preset means anyone who knows preset name can upload to your Cloudinary account.
This is convenient but less secure.

Recommended future upgrade:
- implement signed uploads using a backend/worker endpoint that generates Cloudinary signatures
- then remove unsigned preset from client usage

---

## 13) Summary (What Was Achieved)

✅ Cloudinary used for uploads (secure_url saved)  
✅ Firestore stores URLs only  
✅ Profile avatar shows everywhere without rewriting team docs  
✅ League main image + sponsor image preserved and improved (safe loading + optimization)  
✅ No UI redesign, only logic + safe image rendering

