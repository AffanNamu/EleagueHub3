# Feature Identity Matrix + Debug Guide

This document explains, feature-by-feature, **which identifier is used where**, what is allowed to remain short/shareId, and where mismatches cause permission errors.

---

## 1) Definitions

### 1.1 Firebase Auth UID (Authoritative)
- `FirebaseAuth.instance.currentUser.uid`
- Equals Firestore `request.auth.uid`
- **This is the ONLY ID that Firestore security rules can reliably authorize.**

### 1.2 ShareId / Short UID (Display/Input only)
- Stored as `users/{uid}.shareId` (or derived)
- Used for:
  - showing a short ID in UI
  - letting users paste/share a short code
- Must be resolved to Firebase UID before any security-sensitive write.

### 1.3 SharedPreferences `current_user_id`
- In this codebase it is now intended to store the **Firebase UID**.
- It is used by offline-first local storage + sync logic.
- **Risk:** if it ever contains a legacy short id, Firestore writes keyed by that value will fail.

---

## 2) Feature Matrix

| Feature | Internal ID used in data writes | Short/shareId allowed? | Where it breaks if wrong |
|--------|---------------------------------|-------------------------|--------------------------|
| Coupons (config + codes + redemptions) | Firebase UID (`organizerUid`, `memberIds`, `request.auth.uid`) | Display only | Firestore permission-denied if organizerUid/memberIds don’t contain auth uid or league doc missing |
| Join league by code | Firebase UID added to `memberIds` | Input join code only | Denied if join path tries to add more than one element or adds shortId |
| Add Teams | **Team.id = Firebase UID** | Yes (input/display) | Breaks “My Matches” and membership mapping if Team.id becomes shareId |
| Standings | No identity required | N/A | Not identity-related |
| Space / Voice Room | Should use Firebase UID for request/speaker doc ids | Display only | permission-denied if doc id != request.auth.uid or request.auth is null |

---

## 3) Screen-by-screen notes (from your pasted screens)

### 3.1 `LeagueStandingsScreen`
File: `lib/features/leagues/presentation/league_standings_screen.dart`

- Does NOT read/write identity fields.
- It only loads league + computed standings from local providers and matches.
- Safe with UID changes.

If standings fail:
- it is usually a sync/local data issue, not identity.

---

### 3.2 `AddTeamsScreen`
File: `lib/features/leagues/presentation/add_teams_screen.dart`

Key facts:
- Your code accepts **either** Firebase UID **or** shareId as input:
  - `_profiles.fetchByUserIdOrShareId(input)`
- It resolves to the canonical Firebase UID:
  - `resolvedUserId = profile.userId`
- It stores teams using that canonical uid:
  - `Team(id: resolvedUserId, ...)`

This is correct and should remain.

**Important invariant:**
- `Team.id` and `Membership.userId/teamId` should remain Firebase UID.
- Do NOT change Team.id to shareId unless you redesign “teamId != userId” everywhere.

If Add Teams ever breaks after identity changes:
- check `UserProfileRepository.fetchByUserIdOrShareId`
- check that `/users/{uid}` documents exist and contain `shareId`
- check that `CurrentUser` does not generate random ids

---

### 3.3 `LeagueSpaceRoomScreen` (Potential identity risk)
File: `lib/features/leagues/presentation/league_space_room_screen.dart`

Current behavior in pasted code:
- `_uid` is set from SharedPreferences:
  - `_uid = prefs.getCurrentUserId() ?? ''`
- Firestore writes use `_uid` as the doc id:
  - `/space/current/requests/{_uid}`
  - `/space/current/speakers/{_uid}`

Why this can fail:
- Firestore rules for these paths typically require:
  - `request.auth.uid == uid` (doc id)
  - and data.userId == request.auth.uid
- If `_uid` is stale/legacy shortId, or user is signed out (request.auth null), you get permission-denied.

✅ Why it may still work today:
- We now sync prefs `current_user_id` to Firebase UID at startup via AuthBootstrap/CurrentUser.
- But Space is still safer if it uses FirebaseAuth UID directly.

**If you see Space permission-denied:**
- print/log both values:
  - FirebaseAuth uid
  - prefs current_user_id
- they must match

Recommended fix (if needed):
- In `_init()` set:
  - `_uid = FirebaseAuth.instance.currentUser?.uid ?? prefs.getCurrentUserId() ?? ''`
- and optionally ignore prefs if it doesn’t “look like” a Firebase UID.

---

## 4) Identity-related Failure Signatures

### A) `permission-denied` everywhere (leagues/coupons/spaces)
Most likely:
- `request.auth == null` (not signed in)
Fix:
- ensure AuthBootstrap runs
- enable Anonymous auth in Firebase Console if you rely on auto anonymous sessions

### B) Coupons fail but other reads work
Most likely:
- league doc missing in cloud OR organizerUid/memberIds wrong
Fix:
- check `/leagues/{leagueId}` has organizerUid == auth uid
- memberIds contains auth uid

### C) Join-by-code fails
Most likely:
- join update attempted to add >1 element to memberIds
Fix:
- add ONLY `request.auth.uid`

### D) Space request/speaker writes fail
Most likely:
- Space screen using prefs uid that doesn’t match auth uid
Fix:
- use FirebaseAuth uid as the doc id

---

## 5) Quick Debug Checklist (copy/paste into issues)

1) Device log:
- `authUid = FirebaseAuth.instance.currentUser?.uid`
- `prefsUid = PreferencesService.getCurrentUserId()`

2) Firestore doc:
- `/leagues/{leagueId}.organizerUid`
- `/leagues/{leagueId}.memberIds`

3) Exact failing path + payload:
- e.g. `/leagues/X/space/current/requests/{uid}`

That is sufficient to locate the failing condition.

