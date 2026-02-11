# Identity + Coupons + Sync: Production Debug/Repair Guide (EleagueHub)

## 1) Goal
Make coupons (config/codes/redemptions) work reliably under Firestore security rules after introducing short/share IDs, while keeping offline-first behavior.

## 2) Core invariant
**Authorization identity = FirebaseAuth UID only.**
- Rules authorize using `request.auth.uid`
- Client/UI short IDs (shareId) are display/input only

## 3) Required Firestore schema
### 3.1 leagues/{leagueId}
Must contain:
- organizerUid (Firebase UID)
- optional ownerUid (Firebase UID)
- memberIds: array of Firebase UIDs

May contain (display only):
- organizerUserId (shareId / legacy)
- ownerId (legacy; should be Firebase UID if present)

### 3.2 Coupon paths
- leagues/{leagueId}/couponConfig/config
- leagues/{leagueId}/couponCodes/{codeId}
- leagues/{leagueId}/couponRedemptions/{uid}

## 4) Why coupons were blocked
Common causes:
1) request.auth == null (no auth session) → denied
2) league doc missing in cloud (offline queued) but couponConfig written immediately → denied
3) organizerUid/memberIds stored short IDs → rules can’t prove owner/member → denied
4) join wrote multiple IDs or non-auth IDs into memberIds → denied

## 5) Fixes applied (what changed)

### 5.1 Auth bootstrap
Files:
- lib/core/services/auth_bootstrap.dart
- lib/main.dart
Fix:
- ensure auth session exists early (optionally anonymous)
Ops:
- enable Anonymous auth in Firebase Console if used

### 5.2 CurrentUser source of truth
File:
- lib/features/leagues/utils/current_user.dart
Fix:
- returns FirebaseAuth uid only
- syncs prefs keys to auth uid

### 5.3 SyncService normalization (local→cloud)
File:
- lib/core/services/sync_service.dart
Fix:
- forces organizerUid/ownerUid/ownerId = auth uid
- ensures memberIds contains auth uid
- filters out non-uid memberIds values
- cloud pull requires auth uid (not stale prefs)

### 5.4 Join-by-code (private/local join)
File:
- lib/features/leagues/data/leagues_repository_local.dart
Fix:
- online join appends ONLY auth uid into memberIds (exactly +1)
- membership userId uses auth uid

### 5.5 Direct cloud league save
File:
- lib/features/leagues/data/leagues_repository_firebase.dart
Fix:
- writes organizerUid/ownerUid/ownerId = auth uid
- unions memberIds with auth uid

### 5.6 CouponConfig + CouponCodes services aligned
Files:
- coupon_config_service.dart uses doc('config') (get/watch)
- coupon_codes_service.dart generates codes via per-code transactions (qtyRemaining decrement rules)

### 5.7 UI admin gating aligned to rules
Files:
- league_admin_screen.dart uses remote organizerUid/ownerUid stored in state
- profile_screen.dart queries leagues by organizerUid == auth uid

### 5.8 League creation ordering
Files:
- league_create_wizard.dart
- league_creation_dashboard.dart
Fix:
- sync league to cloud before attempting couponConfig writes (league doc must exist)

### 5.9 Global public join FIX (critical)
File:
- lib/features/leagues/logic/global_public_league_join_service.dart
Fix:
- requires FirebaseAuth
- appends ONLY auth uid to memberIds (viewer + participant)
- creates membership doc id = auth uid and data.userId = auth uid
- derives registeredCount from remote doc so “+1 semantics” match rules

This prevents “joined but still denied on couponConfig/couponCodes”.

## 6) Verification checklist

### Auth
- App logs show FirebaseAuth uid is non-empty (anon ok)

### League doc
In Firestore Console, for league:
- organizerUid == organizer auth uid
- memberIds contains auth uid for organizer and joiners

### Global join
After joining global public league:
- memberIds contains auth uid
- participant join creates memberships/{authUid}

### Coupons
- organizer: can read/update couponConfig and list/generate codes
- member: can read couponConfig
- signed-in user: can get coupon code doc by id for redemption (list remains admin-only)

## 7) Failure triage
If permission-denied persists:
1) confirm request.auth is not null (auth bootstrap + anon enabled)
2) confirm league doc exists in cloud and organizerUid/memberIds correct
3) confirm no code path writes shareId into memberIds
4) if Space fails: ensure space request/speaker doc ids use auth uid
