# EleagueHub – Coupons Permissions + Build Errors Fix (Documented)

This document describes the fixes applied to stop:
1) Firestore `permission-denied` for coupon config / coupon code generation
2) Flutter build errors caused by broken Dart syntax (multi-line strings + widget tree issues)
3) Common sync edge cases that trigger `permission-denied` (join/membership updates)

---

## A) Target Rule Behavior (Required)

### Pricing Admin (Super Admin)
- Can manage ONLY:
  - `/app/pricing`
  - `/app/admins`
  - analytics read (if allowed)

### League Organizer (Creator of that league)
- Can manage ONLY their own league:
  - create/update/delete league
  - coupon config initialization
  - generate coupon codes
  - manage matches/teams/knockout/memberships etc (as per rules)

**Important:** Coupons are NOT globally manageable by pricing-admin. Pricing-admin has no special rights inside other people’s leagues.

---

## B) Root Cause of `permission-denied` (Coupons)

### 1) Wrong Identity Field
Firestore rules authorize by comparing:

- `request.auth.uid`  (FirebaseAuth UID)
with league fields:

- `organizerUid`
- `ownerUid`
(and only optionally legacy `ownerId` / `organizerUserId` if they contain a *Firebase UID*)

If your league doc has `organizerUid` set to a UID different from the account currently signed in, then:
- coupon config create/update = DENIED
- coupon code generation = DENIED

### 2) Coupon Config “Initialize” Create Validation Failed
Rules require on create:
- `unitPrice > 0`
- `effectiveUnit > 0`

If initializer created config with `0.0`, Firestore denies create even if user is the owner.

---

## C) Firestore Rules Fix (Owner-Only Coupons + Correct Syntax)

### What was changed
1) `isCouponManager(leagueId)` is **owner-only**:
   - `return isOwner(leagueId);`
   - pricing-admin does NOT bypass coupons

2) `isOwner(leagueId)` legacy fallback is safe:
   - legacy `organizerUserId` / `ownerId` count ONLY if they *look like* Firebase UID (length > 20)

3) The rules file was made syntactically complete (closing braces)
   - avoids deployment failures

### Result
- Only league creator/organizer can initialize config and generate codes
- Pricing-admin can only manage `/app/pricing` and `/app/admins`

---

## D) Sync Fixes (Prevent Permission Errors During Background Sync)

### 1) `league_join` queue items
Problem:
- Your rule allows append-only join (memberIds must grow by +1).
- If the user is already in `memberIds`, `arrayUnion` does not change size -> update may be DENIED.

Fix (in `sync_service.dart`):
- Before writing join, fetch league doc and check if the user is already a member.
- If already a member, skip the write (don’t spam permission-denied).
- Ensure `updatedAtMs` strictly increases.

### 2) `membership` upload
Problem:
- Rules allow non-owner membership writes only when `userId == request.auth.uid`.
- Legacy payloads or wrong IDs cause DENIED.

Fix:
- Force membership `userId` to real Firebase UID when payload is missing or looks like a short/share id.
- If trying to write membership for another UID, only allow it if current auth is league owner; otherwise downgrade to self.


## E) Flutter Build Fixes (Dart Syntax)

### 1) Multi-line string error in `league_admin_screen.dart`
Problem:
- A Text() widget used a single-quoted string spanning multiple lines without `\n` or string concatenation.
- This causes compile errors like:
  - `String starting with ' must end with '`.

Fix:
- Replace multi-line literal with:
  - `'Line 1\n' 'Line 2\n' 'Line 3'`

### 2) `league_creation_payment_screen.dart` widget tree issues
Problem:
- Missing closing brackets/parentheses caused parse errors:
  - `Expected ')' before this`
  - `Expected an identifier, but got 'if'`
  - `Too many positional arguments` for Slider (because the parser got confused by missing brackets)

Fix:
- Restore a valid widget tree.
- Ensure `Slider(...)` widgets are properly closed.
- Keep optional coupon code preview UI valid.



## F) Admin UI Fix (Avoid showing admin tools for non-UID / short IDs)

### `AppAdminsService`
Fix:
- Only accept Firebase UID strings as pricing admins.
- Reject shareId/short IDs in the dynamic list.

Result:
- UI won’t show admin pricing screens to non-admin accounts.
- Firestore rules remain the final enforcement.



## G) Required Data Fields in Firestore (League Doc)

To avoid permission issues, each `leagues/{leagueId}` should contain:
- `organizerUid = <creator Firebase UID>`
- `ownerUid = <creator Firebase UID>`
- `ownerId = <creator Firebase UID>` (legacy, optional)
- `memberIds` contains `<creator Firebase UID>`

Your cloud writer (`LeaguesRepositoryFirebase.saveLeague` and `SyncService._uploadLeague`) already enforces these.

---

## H) Deployment / Verification Checklist

### 1) Deploy rules
Run:
```bash
firebase deploy --only firestore:rules
```

### 2) Verify current logged in UID
In app Profile screen, confirm the "internal uid debug" matches the league doc organizerUid/ownerUid.

### 3) Confirm couponConfig initializer writes valid values
When creating `couponConfig/config`, ensure:
- `unitPrice > 0`
- `effectiveUnit > 0`
(or the create will be denied by rules)

### 4) Confirm only league owner can manage coupon codes
Sign in with another user and try to initialize/generate -> must be DENIED (expected).



## I) About `tools/*.py` Scripts (Safe)

Python scripts in `tools/` DO NOT affect Flutter builds unless your CI explicitly runs them.

To confirm nothing runs them:

grep -R "patch_league_admin_screen.py" -n .
grep -R "python tools/" -n .


If no matches, the tools scripts are harmless.



## Files Involved (High Level)

- `firestore.rules`
- `lib/core/services/sync_service.dart`
- `lib/features/leagues/presentation/league_admin_screen.dart`
- `lib/features/leagues/presentation/league_creation_payment_screen.dart`
- `lib/core/services/app_admins_service.dart`
- `lib/features/profile/presentation/profile_screen.dart`
- (and coupon init/write paths in `lib/features/leagues/logic/coupon_config_service.dart`)

