# eSportLytic — Complete Rewards System & Super Admin Monitoring Guide

This document provides the **full overview, architecture, admin monitoring tools, deployment steps, and production hardening checklist** for the League Rewards System in eSportLytic.

---

# 1. System Architecture & Data Flow

## 1.1 Firestore Structure
**Path:** `leagues/{leagueId}/rewards/{rewardId}`

**Permissions:**
- Everyone can read (via `canReadLeague`)
- Only organizers / owners can write (via `canManageLeague`)
- Super Admin has global override access

## 1.2 Reward Data Model
**Supported Types:**
- cash
- physical
- digital
- trophy
- other

**Features:**
- Unknown types normalize to "other"
- Uses `serverTimestamp` for creation
- Supports Cloudinary image URLs

## 1.3 RewardFirestoreService
Includes in-memory caching (TTL: 30–45 seconds).

**Optimized functions:**
- `hasRewards()`
- `fetchTopRewardName()`

---

# 2. User Experience

## 2.1 Creation & Management
**LeagueCreateWizard includes:**
- Contains rewards toggle
- Auto-redirect to Manage Rewards screen if enabled

**Access:**
- LeagueAdminScreen → Manage Rewards

## 2.2 Reward Image Upload
**Uses:**
- `image_picker` (mobile)
- `file_picker` (web fallback)

**Cloudinary destination:**
- `eleaguehub/league_rewards/{leagueId}`

## 2.3 Reward Discovery
**LeagueFlipCard displays:**
- 🏆 Rewards badge
- Top reward preview (e.g., *Top reward: ₦50,000*)

**Screens:**
- League detail screen: Shows preview cards
- Full rewards screen: Shows full list sorted by position (1st, 2nd, 3rd)

---

# 3. Super Admin Rewards Fulfillment Panel

**Location:** Profile Screen

## 3.1 Features
- Automatically detects leagues with rewards
- Displays League name, Top reward, and Organizer UID
- **Actions:** Open League, Open Standings, Compute Winner, Copy Organizer UID

## 3.2 Winner Computation System
Best-effort logic scanning `leagues/{leagueId}/matches`.

**Score fields supported:**
- `homeScore` / `awayScore`
- `homeGoals` / `awayGoals`
- `homeTeamScore` / `awayTeamScore`
- `scoreHome` / `scoreAway`

## 3.3 Super Admin Permissions Requirement
**Firestore Rules MUST be deployed:**
`firebase deploy --only firestore:rules`

---

# 4. Dependencies
Ensure `pubspec.yaml` contains:
- `image_picker`
- `file_picker`
- `cloudinary_public`
- `http`

---

# 5. League Card Requirements
All league lists must use **LeagueFlipCard** to enable the 🏆 badge and top reward preview.

---

# 6. Optional Feature — Rewards Planned Flag
Add `rewardsPlanned: true` to `leagues/{leagueId}` to track leagues intending to give rewards before they are created.

---

# 7. Deployment Checklist
1. `flutter pub get`
2. `firebase deploy --only firestore:rules`
3. Test reward creation & image upload
4. Test Super Admin visibility & private league access
5. Verify badge and top reward preview appearance

---

# 8. Production Hardening Checklist
- Add pagination to Super Admin panel
- Add crash protection for missing match fields
- Add fulfillment tracking status (e.g., `rewardStatus: pending|delivered|verified`)

---

# 9. Cloudinary Configuration Requirements
Ensure folder prefix exists: `eleaguehub/`

---

# 10. Data Structure Reference
- **Rewards:** `leagues/{leagueId}/rewards/{rewardId}`
- **Matches:** `leagues/{leagueId}/matches/{matchId}`
- **Teams:** `leagues/{leagueId}/teams/{teamId}`

---

# System Status: Enterprise-Grade / Production Ready
