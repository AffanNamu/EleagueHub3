# Realtime Chatrooms + League Access Unlock (Pay or Coupon) — Production Implementation

This document explains everything implemented end-to-end:
- League private chatroom
- Global public chatroom (request/approval)
- Cloudinary image upload (NO Firebase Storage)
- Firestore structure + security rules
- LeagueAccessGuard “Pay to unlock” + “Redeem coupon” flow

The goal was to add production-grade functionality WITHOUT breaking existing app structure.

---

## 0) Overview (What Was Added)

### A) League Private Chatroom
- Location: inside League Details (button “League Chatroom”)
- Firestore: `leagues/{leagueId}/chatroom/{messageId}`
- Access:
  - Organizer/Owner OR Participant (memberIds or memberships doc)
  - Everyone else is denied by Firestore rules

### B) Global Public Chatroom
- Location: Home → Explore → “Global Chat”
- User must request access first:
  - Firestore: `globalChatRequests/{uid}` with status `pending|approved|rejected`
- Only Super Admin can approve/reject
- Only `approved` users can read/send messages:
  - Firestore: `globalChatroom/{messageId}`

### C) Images
- Upload destination: Cloudinary
- Firestore stores ONLY: `imageUrl` = Cloudinary `secure_url`

### D) Access Unlock (when blocked by LeagueAccessGuard)
When a user tries to open guarded league screens and is not a participant:
- They can choose:
  1) Pay to unlock (Flutterwave, receipt stored under user)
  2) Redeem coupon code (couponCodes + couponRedemptions + membership)

---

## 1) Firestore Structure

### League chat messages
Path:
- `leagues/{leagueId}/chatroom/{messageId}`

Fields (message model):
- `messageId`
- `senderId`
- `senderName`
- `senderPhoto`
- `text`
- `imageUrl`
- `type` (`text|image|code`)
- `createdAt` (server timestamp)
- `createdAtMs` (client ms for stable ordering)

### Global chat messages
Path:
- `globalChatroom/{messageId}`

Same message model fields.

### Global chat access requests
Path:
- `globalChatRequests/{uid}`

Fields:
- `userId`
- `userName`
- `userPhoto`
- `status`: `pending|approved|rejected`
- (best-effort timestamps) `createdAtMs`, `updatedAtMs`

### League access payment receipts
Path:
- `users/{uid}/leagueCharges/{leagueId}`

Stored via `LeagueChargesStore.storeReceipt()` after successful Flutterwave charge.

### League coupons (existing system, now wired into guard UI)
Paths:
- `leagues/{leagueId}/couponCodes/{code}`
- `leagues/{leagueId}/couponRedemptions/{uid}`
- `leagues/{leagueId}/couponConfig/{docId}` (existing)

---

## 2) Security / Firestore Rules

### League chatroom
Rules enforce:
- Read/list/create allowed only if:
  - Organizer/Owner OR memberIds contains uid OR membership doc exists
- Update/delete blocked
- Message validation enforced (senderId == auth uid, type is valid, createdAt is request.time, etc.)

### Global chat requests
Rules enforce:
- User can create request at `globalChatRequests/{uid}` with `status: pending`
- User cannot self-approve
- Super admin can list and set status to approved/rejected

### Global chatroom
Rules enforce:
- Only approved users (or super admin) can read/send

### Coupons
Rules already enforce:
- couponCodes update can only set `usedBy/usedAtMs/updatedAtMs`
- usedBy must be the current auth uid and coupon must be unused

---

## 3) Cloudinary Image Upload (Production-consistent)

Chat image uploads reuse your production Cloudinary stack:

- `lib/features/marketplace/data/cloudinary_upload_service.dart`
  - Uses `cloudinary_public`
  - Uses env defines:
    - `CLOUDINARY_CLOUD_NAME`
    - `CLOUDINARY_UNSIGNED_UPLOAD_PRESET`
  - Folder policy: must start with `eleaguehub/`

Chat folders used:
- League chat images:
  - `eleaguehub/chatrooms/leagues/{leagueId}`
- Global chat images:
  - `eleaguehub/chatrooms/global`

Firestore stores ONLY:
- `imageUrl: <secure_url>`

NO Firebase Storage is used.

---

## 4) League Access Unlock (Pay or Coupon) — How It Works

### When does LeagueAccessGuard show?
Used for protected routes (fixtures/standings/matches and league chat route wrapper):
- If organizer/owner OR participant => child screen is shown
- Else => access restricted screen appears

### A) Pay to unlock
1) User taps “Pay to unlock”
2) App starts Flutterwave payment via:
   - `LeagueChargesPaymentService.payLeagueCharges(...)`
3) On success:
   - Store receipt in Firestore via `LeagueChargesStore.storeReceipt(...)`
     - `users/{uid}/leagueCharges/{leagueId}`
   - Create/merge membership doc:
     - `leagues/{leagueId}/memberships/{uid}`
   - Add uid into `leagues/{leagueId}.memberIds` (arrayUnion)
4) Guard re-checks access and unlocks

Important:
- If the receipt already exists, the guard will NOT charge again.
- It will just ensure membership + memberIds are created and unlock.

### B) Redeem coupon
1) User enters coupon code and taps “Redeem coupon”
2) Transaction:
   - Validate coupon exists and unused (`usedBy == ''`)
   - Update coupon doc:
     - set `usedBy = uid`
     - set `usedAtMs`, `updatedAtMs`
   - Write redemption doc:
     - `leagues/{leagueId}/couponRedemptions/{uid}`
   - Ensure membership doc + memberIds are updated
3) Guard re-checks access and unlocks

---

## 5) Realtime Chat (Streams)

Both chatrooms use Firestore streams:
- `snapshots()` + `StreamBuilder`
- Ordered by `createdAtMs desc` for consistent order even while `createdAt` is pending.

Message types supported:
- Text
- Code
- Image (Cloudinary)

---

## 6) UI Entry Points

### League private chatroom
- League Details screen adds “League Chatroom” button (only shown if organizer or membership exists).
- Route:
  - `/leagues/{id}/chat`

### Global chatroom
- Home → Explore includes “Global Chat”
- Route:
  - `/global-chat`

### Admin requests
- Super admin only:
  - `/admin/global-chat-requests`

---

## 7) Setup / Deployment Checklist

1) Deploy Firestore rules:
```bash
firebase deploy --only firestore:rules
```

2) Ensure Cloudinary defines exist in your run/build:
```bash
--dart-define=CLOUDINARY_CLOUD_NAME=...
--dart-define=CLOUDINARY_UNSIGNED_UPLOAD_PRESET=...
```

3) Create Firestore composite index (if prompted):
- `globalChatRequests`:
  - where `status == pending`
  - order by `createdAtMs desc`

4) Test flows:
- League chat:
  - organizer + member can send text/image/code
  - non-member gets permission-denied
- Global chat:
  - request access → pending
  - super admin approves
  - approved user can read + send
- Access guard:
  - pay success → receipt stored → membership created → access unlock
  - coupon redeem success → coupon marked used → redemption recorded → access unlock

---

## 8) Troubleshooting

### Permission denied when sending chat message
- Check Firestore rules deployment
- Verify:
  - league membership exists or memberIds contains uid
  - global chat request status is approved

### Cloudinary upload fails
- Check `CLOUDINARY_CLOUD_NAME` and `CLOUDINARY_UNSIGNED_UPLOAD_PRESET`
- Check preset allows image formats and file size
- Ensure folder starts with `eleaguehub/`

### Payment succeeded but still blocked
- Check Firestore doc exists:
  - `users/{uid}/leagueCharges/{leagueId}`
- Tap Retry (guard has a Retry button)
- Ensure membership exists:
  - `leagues/{leagueId}/memberships/{uid}`

### Coupon says invalid
- Confirm coupon doc ID matches the code (case-sensitive)
- Codes are normalized to uppercase and stripped of spaces/dashes.

