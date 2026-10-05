# EleagueHub3 / eSportlyic — Architecture Reference

This document describes the system as it exists in the repository today: the four
codebases, how they talk to each other, the shared Firestore data model, and how
everything gets built and deployed. It's a reference for orienting in the codebase,
not a tutorial or a changelog — for feature-specific implementation notes, see the
other files under `docs/`.

## 1. The four codebases

| Codebase | What it is | Stack |
|---|---|---|
| `lib/` (+ `android/`, `ios/`) | The main product: a Flutter app for iOS, Android, and Flutter Web | Flutter, Riverpod, go_router |
| `worker/` | The shared backend for anything that needs a secret key or server-side trust | Cloudflare Worker (JS), no framework |
| `web_client/` | A second, independent web front-end mirroring most of the Flutter app's features for browser users | Next.js (App Router), Tailwind |
| `esportlyic-admin/` | Internal admin/moderation panel | Next.js (App Router), Tailwind |

All four share one Firebase project (Firestore + Auth + Cloud Messaging + Hosting)
as the system of record. There's also a Supabase project, used narrowly for a few
Edge Functions (desktop-pairing QR login, some chat push notifications) — it is not
a second database; Firestore is still authoritative for all real data.

```
                        ┌─────────────────────┐
                        │   Firebase project   │
                        │  (Firestore, Auth,    │
                        │   FCM, Hosting)        │
                        └──────────┬────────────┘
                 ┌──────────────────┼──────────────────┐
                 │                  │                  │
         ┌───────┴──────┐   ┌───────┴──────┐   ┌───────┴──────┐
         │  Flutter app  │   │  web_client   │   │ esportlyic-   │
         │ (iOS/Android/ │   │  (Next.js)    │   │ admin         │
         │   Web)        │   │               │   │ (Next.js)     │
         └───────┬───────┘   └───────┬──────┘   └───────────────┘
                 │                   │            (talks to Firestore
                 │                   │             directly + its own
                 └─────────┬─────────┘             session cookie API)
                           │
                  ┌────────┴─────────┐
                  │ Cloudflare Worker │──── Flutterwave, Google Play Billing,
                  │ (livekit-token-   │     Apple StoreKit/App Store Server,
                  │   worker)         │     LiveKit, Cloudinary, API-Football,
                  └───────────────────┘     GNews, FCM
```

Why a Worker exists at all: every secret API key (Flutterwave, Cloudinary, LiveKit,
API-Football, GNews, Apple, the Firebase service account itself) has to live
somewhere that isn't a shipped client binary. The Worker is that place. It never
holds its own copy of user data — it reads/writes Firestore over the REST API using
a service-account OAuth token, the same documents the apps read directly.

## 2. Flutter app (`lib/`)

### Structure

- `lib/core/` — cross-cutting infrastructure (routing, theming, services, reactions,
  deep links, persistence, platform bridges).
- `lib/features/` — ~29 feature modules, each typically split into `data/`
  (Firestore repositories), `domain/`/`models/`, `logic/` (controllers), and
  `presentation/` (screens/widgets).
- `lib/widgets/` — a second, smaller shared-widget folder (mostly leagues/standings
  widgets that never migrated into `core/`).
- `lib/web_app/` — a Flutter-Web-only shell used specifically for the "desktop
  pairing" QR sign-in flow, separate from the main app shell.

### Feature inventory (`lib/features/*`)

| Feature | What it does |
|---|---|
| `auth` | Sign-up/login/onboarding, email verification, password reset, account suspension & force-update gating |
| `call` | In-app voice "call room" for league voice chat (LiveKit) |
| `chat` | Global chat, per-league chat, organizer chat, and 1:1 private chat |
| `discovery` | Landing hub routing to organizer discovery, team search, competitions, community discussions |
| `feed` | Public social feed of posts |
| `football_hub` | Real-world football fixtures/standings/news, proxied through the Worker |
| `highlights` | Match highlight clip recording/compression + a community-wide highlights feed |
| `home` | Home dashboard/shell |
| `leagues` | Core league/tournament management: creation, fixtures, standings, knockout brackets, admin score entry, QR join |
| `legal` | Static privacy/terms/contact/affiliate-disclosure screens |
| `live` | Local/peer-to-peer live match streaming (host/viewer WebRTC) — distinct from `call`'s voice feature |
| `marketplace` | In-app affiliate product marketplace |
| `master_leagues` | "Organizer workspaces" grouping multiple leagues under one organizer, with staff roles, discipline/moderation, and a followed-organizer feed |
| `moderation` | Shared user-report model/reasons used across chat/feed/profile |
| `organizer` | Gate screen wrapping a master-league workspace for the public `/org/:id` link |
| `profile` | Profile viewing/editing, settings, squad roster, public team profile |
| `search` | User/team search |
| `social` | Standalone post-detail screen for the `/post/:id` share link |
| `status` | Ephemeral "stories"-style status updates |
| `team` | Gate screen mapping `/team/:teamId` onto the user-profile screen (there's no separate `teams` collection) |
| `team_claim` | Lets a real-world team claim an externally/manually-created team record via a token link/QR |
| `verification` | Paid/earned "verified badge" feature |

### Core infrastructure (`lib/core/`)

- **Routing** (`core/routing/app_router.dart`): a single `GoRouter` with ~71
  routes. `route_resolver.dart` centralizes the "Universal Sharing" entity paths
  (`/u/:username`, `/competition/:id`, `/team/:teamId`, `/post/:id`, `/org/:id`,
  `/claim/:token`, `/join`); `deep_link_gate.dart` + `deep_links/deep_link_service.dart`
  handle incoming links before routing.
- **Deep links**: two layers — a custom URL scheme (`esportlyic://`, used for
  Firebase auth-action links) and Universal/App Links (`https://esportlyic.com`,
  `android:autoVerify="true"` on Android, `applinks:` associated domains on iOS)
  for the Universal Sharing entity paths above.
- **Theming**: `core/theme/app_theme.dart` (design tokens for a dark "glass"
  aesthetic) + `theme_controller.dart` (Riverpod).
- **Shared widgets**: `core/widgets/glass.dart`/`glass_scaffold.dart` are the
  app's signature translucent-card UI system, used everywhere.
- **Native platform bridges** (`core/platform/`): a `MethodChannel('local_live')`
  into Android native code. Backing Kotlin services in
  `android/app/src/main/kotlin/com/eleaguehub/app/`: `LocalLiveForegroundService`,
  `LiveOverlayBubbleService` + `OverlayVoiceForegroundService` (the floating
  "bubble" overlay for live streaming/calls while backgrounded),
  `HighlightCompressionEngine.kt` (Media3-based clip compression, mirrored by
  `ios/Runner/HighlightCompressionEngine.swift` on iOS), `OverlayPositionStore`,
  `FlutterEngineHolder`.

### State management

Primarily **Riverpod** (no `provider` package in use at all) for shared/cross-screen
state (`StateNotifierProvider`, `NotifierProvider`, `StreamProvider` wrapping
Firestore streams), mixed with plain `StatefulWidget`/`setState` for local screen
state. Example: `leagueAccessControllerProvider`
(`StateNotifierProvider.autoDispose.family`), `themeControllerProvider`
(`NotifierProvider`), `leagueStandingsProvider` (`StreamProvider.family` over
Firestore).

### Backend communication

- **Firestore directly** for the large majority of reads/writes — one repository
  class per feature (`LeaguesRepositoryFirebase`, `UserProfileRepository`,
  `MasterLeaguesRepositoryFirebase`, `ChatRepository`/`PrivateChatRepository`,
  `PaymentsService`, etc.).
- **The Cloudflare Worker**, base URL from `--dart-define EH_WORKER_BASE_URL`
  (`lib/core/config/backend_config.dart`): `/flutterwave/verify`,
  `/premium/activate`, `/organizer-pro/activate`, `/cloudinary/sign-highlight`,
  the `/football/*` proxy routes, and `/teams/claim/*`. A second, separately
  hardcoded Worker URL (`livekit-token-worker.esportlyic.workers.dev`, which is
  the *same* deployed Worker under `worker/wrangler.toml`'s `name`) is used by
  `lib/features/leagues/services/livekit_service.dart` for LiveKit room tokens.
- **Supabase**, narrowly: `lib/core/services/supabase_edge_notifications_service.dart`
  posts to Supabase Edge Functions (e.g. `league-chat-notify`) for data-only FCM
  fan-out, authenticated with the Supabase anon key plus the user's Firebase ID
  token.

### Payments (client side)

- **Flutterwave** (card/mobile money, NGN+USD) — `core/config/flutterwave_config.dart`,
  verified server-side by the Worker.
- **Google Play Billing** — `core/services/payments/google_play_billing_service.dart`
  + `google_play_billing_catalog.dart`.
- **Apple In-App Purchase** — via the same cross-platform `in_app_purchase`
  package; a shared `purchase_stream_listener_service.dart` listens for both
  platforms.
- Shared orchestration: `core/services/payments/payments_service.dart` creates
  the `payment_attempts`/`payments` Firestore records every provider path writes
  into (see §4).

### Push notifications

`core/services/push_messaging_service.dart` listens to FCM and dispatches to
`core/services/notification_service.dart` for local rendering. Distinct
notification types: league announcements, organizer feed, football hub events
(goal/kickoff/full-time), team claims, new followers, and per-surface chat
messages (league/organizer/global/private).

### Localization

A hand-rolled `AppLocalizations` (not Flutter's generated gen-l10n) in
`core/locale/app_localizations.dart`, backed by ~15 per-language files
(`app_localizations_1.dart` … `_14.dart`), including RTL languages (Arabic,
Hebrew). Falls back to English for any missing key/locale.

## 3. Cloudflare Worker backend (`worker/`)

A single file, `worker/src/index.js` (~4,400 lines), deployed as a Worker named
**`livekit-token-worker`** (`worker/wrangler.toml`). Despite the name (a holdover
from when it only minted LiveKit tokens), it is now the backend for everything
that needs a secret key: payments, highlight uploads, team claims, and a cached
proxy for two third-party data APIs.

### Deployment basics

- `compatibility_date = "2024-01-01"`, `workers_dev = true`.
- Cron trigger: `0 * * * *` (hourly) — intentionally throttled to stay inside
  API-Football's free 100 req/day tier; the comment in `wrangler.toml` notes
  this should be tightened once on a paid plan.
- Plain vars: `LIVEKIT_URL`, `FIREBASE_PROJECT_ID`, `ANDROID_PACKAGE_NAME`,
  `CLOUDINARY_CLOUD_NAME`.
- Secrets (set via `wrangler secret`, not in the repo): `LIVEKIT_API_KEY`,
  `LIVEKIT_API_SECRET`, `FIREBASE_PRIVATE_KEY`, `FIREBASE_CLIENT_EMAIL`,
  `FLUTTERWAVE_SECRET_KEY`, `APPLE_SHARED_SECRET`, `CLOUDINARY_API_KEY`,
  `CLOUDINARY_API_SECRET`, `API_FOOTBALL_KEY`, `GNEWS_API_KEY` (the last two can
  also be overridden live from a Firestore config doc without a redeploy).
- No KV/D1/R2 bindings — the only platform feature used besides Firestore/HTTP
  is the built-in Cache API (`caches.default`).

### Route inventory

Everything is one big `fetch` handler matching on `url.pathname`/method
(`index.js:3969` on). Firebase-auth means the route calls `_verifyFirebaseIdToken`
and requires a valid ID token; everything is Firebase-authenticated **except**
the two explicitly noted.

**LiveKit / voice & video**
- `POST /` — mints a LiveKit room-join token. Identity is always the verified
  uid; `role:"host"` is only honored for league rooms when the caller is
  independently verified as that league's organizer (match/call rooms don't
  have an equivalent check yet — see §9).
- `POST /admin` — mutes/unmutes a participant via LiveKit's server API; same
  organizer check for league rooms.

**Payments**
- `POST /flutterwave/verify` — verifies a Master League one-time payment against
  a `payment_attempts/{id}` doc and a live Flutterwave lookup; idempotent.
- `POST /organizer-pro/activate` — activates an Organizer Pro/Elite plan;
  dispatches to Flutterwave, Google Play, or App Store verification based on
  `provider`.
- `POST /premium/activate` — activates "Premium" via Flutterwave only.
- `POST /appstore/notifications` — **no Firebase auth**; Apple's App Store
  Server Notifications V2 webhook, authenticated by verifying the notification's
  own signed JWS certificate chain in-Worker.

**Highlights**
- `POST /cloudinary/sign-highlight` — signs a Cloudinary upload after verifying
  the caller is a member/organizer of the claimed team and the match is
  finished.

**Team claims**
- `POST /teams/claim/generate` — organizer creates a claim token/link for an
  externally-created team.
- `GET /teams/claim/preview` — **no Firebase auth** (deliberately public, so an
  unauthenticated claimant can preview before signing in).
- `POST /teams/claim/confirm` — claimant consumes the token; one atomic
  Firestore commit, guarded against double-claims.
- `POST /teams/claim/revoke` — organizer revokes an outstanding link.

**Football Hub proxy (API-Football)** — all cached (see below):
`/football/fixtures`, `/football/fixture-events`, `/football/standings`,
`/football/squad`, `/football/player`, `/football/leagues`, `/football/teams`.

**Football news (GNews)**
- `GET /football/news`.

### Auth helper

`_verifyFirebaseIdToken` (`index.js:352`) is a from-scratch Firebase ID token
verifier — no Admin SDK. It checks JWT shape, `alg=RS256`, `aud`/`iss`/`exp`/`iat`,
fetches Google's public certs (cached), and verifies the RS256 signature via
`crypto.subtle.verify`.

### Firestore access

All via the **REST API**, authenticated with a Google service-account OAuth
token (`_serviceAccountAccessToken`) — never the Admin SDK. Key helpers:
`_firestoreGetDocSA` / `_firestoreCreateDocSA` / `_firestorePatchDoc` (single-doc
read/create/merge-update), `_firestoreQueryCollectionGroupEquals`
(collection-group equality query — e.g. "who follows this football team, across
every user"), `_firestoreCommitSA` (atomic multi-document commit, used by team
claims). FCM sends ride the same service-account token (`_sendFcmToUid`, which
self-heals by deleting tokens FCM reports as unregistered).

### External integrations

Flutterwave (payment verification), Google Play Developer API
(subscription verification), Apple's classic `verifyReceipt` (not the newer App
Store Server API — the Flutter plugin sends the full StoreKit1 receipt, not a
signed JWS), Apple App Store Server Notifications V2 (inbound webhook), LiveKit,
Cloudinary (signing only), API-Football, GNews, and FCM HTTP v1.

### Scheduled job

The cron trigger runs `_pollLiveFixturesAndNotify` hourly: one consolidated
`/fixtures?live=all` call covers every live match worldwide (fixed cost
regardless of user count). For each live fixture it diffs against a stored
`football_live_state/{fixtureId}` doc to detect goal/kickoff/full-time, looks up
followers via a collection-group query, and pushes FCM notifications — only
making an extra API call (to fetch the scorer's name) when a goal notification
is actually about to be sent to someone.

### Caching

Two Cache-API layers, no KV binding: the football proxy (per-route TTLs from 60s
for live fixture events up to 86400s/1 day for squads/teams/leagues) and the
news proxy (30 min). Firestore itself also holds a couple of "cache-like" config
docs (`app_config/pricing`, `football_config/settings`) that are read-through,
not time-bounded.

## 4. Firestore data model

The canonical schema is `firestore.rules` (~3,100 lines) — every collection that
exists has a `match` block there (a collection with no `match` block, like
`moderation_cases`/`audit_logs`, is server/Admin-SDK-only with no client access
path at all).

### Identity & social graph

- **`users/{userId}`** — the central profile doc. Public read; `create` requires
  the uid-matching doc plus `teamName/authProvider/createdAt`; `update` is a long
  list of *disjoint* field groups (a single write may only touch one group:
  teamName, username, profile images, subscription-plan fields, self-badge
  verification, etc.) — this is the pattern used throughout the schema to keep
  each write request narrowly scoped. Many subcollections: `fcmTokens`,
  `entitlements` (server-only), `team_profile` (doc id `"profile"`), `squads`,
  `recent_matches`/`trophies` (written by whoever manages the referenced league,
  not necessarily the profile owner), `stats` (doc id `"summary"` — counters
  like `followersCount`/`wins`, deliberately writable by non-owners since
  followers/organizers are the ones incrementing them), `followers`/`following`,
  `notifications`, `blocked_users`/`blocked_by`, `football_followed_teams`/
  `football_followed_players`, `rateLimits`, `statuses` (Pro/Elite-only,
  auto-expiring), `private` (self-only app-state cursors).
- **`usernames/{username}`** / **`organizer_usernames/{username}`** — global
  handle-reservation docs.
- **`user_search/{userId}`** — denormalized search index (lowercased name/handle,
  avatar, country).

### Leagues & master leagues

- **`leagues/{leagueId}`** — a single competition. `create` sets
  `organizerUid==auth.uid`; format/settings validated against the app's known
  league formats. Subcollections: `competitionRules`, `rewards`, `teams`,
  `matches`/`knockout`, `memberships/{membershipId}` (doc id = uid;
  self-registration only ever grants the member role, never organizer),
  `announcements`, `chatroom` (+ `reactions`), `space` (live audio/video room, +
  `reactions`/`requests`/`speakers`), `couponConfig`/`couponCodes`/
  `couponRedemptions`, `pointAdjustments` (manager-only immutable ledger).
- **`master_leagues/{masterLeagueId}`** — an organizer's "workspace" that can
  group multiple leagues. `create` ties the owner to a paid plan tier
  (basic/pro/elite). Subcollections: `followers`, `competition_templates`,
  `chatroom` (+ `reactions`), `disciplineActions` (moderator warning/points/
  mute/ban log), `staffAuditLog`, `announcements`, `memberModeration`.
- **`master_league_verification_requests/{requestId}`** — the "Get Verified"
  application flow (pending/approved/rejected/info_requested), tied to a
  payment/receipt.
- **`league_spaces/{spaceId}`** / **`call_rooms/{callId}`** (+ `quick_messages`)
  — live-room metadata for the Space and call features.

### Payments

- **`payment_attempts/{attemptId}`** — pre-payment intent:
  `provider/currency/amount/status(initiated→client_success/verified/fulfilled)/
  items[]`. Owner-create, server/owner-update of a narrow status/receipt field
  set only.
- **`payments/{paymentId}`** — the confirmed-payment ledger record (superset of
  the attempt, plus raw provider verification data).
- **`apple_transactions`** / **`apple_notifications`** /
  **`apple_notifications_unlinked`** — Apple Server Notification plumbing,
  Worker-only (`if false` for every client operation).

### Content & chat

- **`public_posts/{postId}`** (+ `likes`, `reactions`, `comments` with one level
  of threaded replies) — the main social feed; free-tier posting is rate-limited.
- **`discussion_threads/{threadId}`** (+ `replies`) — forum-style threads.
- **`private_threads/{threadId}`** (+ `messages`, `reactions`) — 1:1 DMs;
  requires a Pro/Elite plan to start a new thread; read/list restricted to the
  two participants.
- **`globalChatroom`**, plus each league's/master league's own `chatroom` — all
  share the same `reactions/{uid}` subcollection pattern (one emoji reaction per
  user, from a fixed emoji set).
- **`matches/{matchId}/highlights/{highlightId}`** — uploaded clip docs; the
  actual video upload is signed by the Worker (§3), not written directly.

### Platform / admin

- **`app/{docId}`** / **`app_config/{docId}`** — global config singletons
  (`pricing`, `app_update`, `admins`).
- **`marketplace_products`** — admin-curated affiliate catalog.
- **`reports`**, **`globalChatRequests`**, **`organizer_feed`** — moderation
  queues and per-master-league activity feeds.
- **`analytics_events`**, **`analytics_link_events`** / **`analytics_link_rollups`**
  — client telemetry and sharing/deep-link click tracking (write-only from the
  client's perspective).

### Composite indexes (`firestore.indexes.json`)

11 total: single-collection indexes on `home_content`, `leagues`
(`isPrivate`+`updatedAtMs`), `reports` (×2, status+createdAt asc/desc),
`moderation_cases`, `globalChatRequests` (×2),
`master_league_verification_requests` (×2), `audit_logs`; plus two
**collection-group** indexes on `highlights` (`leagueId`+`createdAt`, and
`createdAt` alone) — the second one is what lets the app query "the latest
highlights across every league" in a single query.

## 5. `web_client/` (public web app)

Next.js App Router. Mirrors a large fraction of the Flutter app's functionality
for browser users, talking to the **same** Firestore project directly from the
client, plus the same Cloudflare Worker for anything that needs a secret.

### Pages (`app/`)

Dashboard-group pages (all under `(dashboard)/`, gated by `middleware.ts`):
leagues (list/detail/create), master-leagues (list/detail/create/discovery),
organizer-feed, team/post detail (the Universal Sharing link targets), profile
(+ public `/u/[username]` lookup), status, feed, discovery
(+ community/competitions), search, marketplace, messages (private chat),
global-chat, call/live (LiveKit), football (fixtures/standings/match/player),
notifications, premium, settings, legal pages. Separately: `(auth)/pairing`
(desktop QR pairing), `(auth)/onboarding`, and `login/page.tsx` (switches
between desktop-pairing and mobile email/Google sign-in views).

### API routes (`app/api/`)

Only two: a match-poster image generator, and `/api/crossmint/checkout`
(mints an NFT via Crossmint for a "Premium Upgrade", gated by Firebase ID-token
verification since a recent fix — see §9).

### `lib/` structure

Firestore repository classes mirroring the Flutter app's, one per feature area
(`masterLeagues/`, `chat/`, `leagues/`, `marketplace/`, `payments/`,
`verification/`, `status/`, `reactions/`, `search/`, `social/`, `highlights/`,
`feed/`, `discovery/`, `footballHub/`), plus `firebase.ts`/`firebase-admin.ts`
(client/admin SDK init), `desktopPairing.ts` (Supabase Edge Functions for QR
login), `plans/rateLimitService.ts`, `algorithms/*` (tournament
scheduling/standings math, shared logic with league creation), and
`cloudinary/cloudinaryUpload.ts`.

### Auth

Client-side Firebase Auth. On sign-in, the app currently writes the **raw
Firebase ID token itself** into a plain (non-HttpOnly) `session` cookie
(`app/login/page.tsx`, `components/auth/MobileSignInView.tsx`) — there is no
server-side session-cookie exchange here, unlike the admin app (§6). Edge
`middleware.ts` only checks the cookie's *presence* (firebase-admin isn't
Edge-compatible) to gate a handful of route prefixes; deeper role/plan checks
happen client-side (`components/guards/RoleGuard.tsx`,
`components/guards/PremiumGuard.tsx`) and, in the one route that needs real
server-side trust, via `adminAuth.verifyIdToken` on a Bearer header
(`api/crossmint/checkout`). **This non-HttpOnly raw-ID-token cookie pattern is a
known gap, flagged but not fixed in this pass — see §9.**

### Styling & integrations

Tailwind CSS, no component library; shared primitives in `components/ui/`
(`Glass.tsx`/`GlassScaffold.tsx`, mirroring the Flutter app's "glass" motif).
Integrations: Cloudinary (unsigned uploads), Crossmint (NFT minting),
Supabase (desktop pairing + some notification fan-out), LiveKit
(`hooks/useLiveKitToken.ts` talks to the same Worker as the Flutter app),
Flutterwave (`checkout.flutterwave.com/v3.js`).

## 6. `esportlyic-admin/` (internal admin panel)

A separate Next.js App Router app for platform staff — user/league/payment
moderation, pricing config, verification review, and role management.

### Sections (`app/(admin)/`)

`dashboard` (overview + system-health alerts), `users` (+ detail/ban/edit),
`leagues` (+ detail), `organizers` (+ detail), `payments` (+ detail + refund),
`marketplace` (+ new/detail), `moderation/cases`, `moderation/reports`,
`moderation/global-chat-requests`, `verification` (+ detail), `content/posts`,
`content/discussions`, `content/home`, `notifications`, `settings` (+
`pricing`, `app-updates`, `system-health`, `football-hub`, `football-news`),
`roles-permissions` (super-admin only), `audit-logs`, `admins`, `analytics`.

### Auth & admin model

- `middleware.ts` only checks for the presence of a `nomad_admin_session`
  cookie (explicitly documented as *not* the authorization source of truth,
  since firebase-admin can't run on Edge).
- `app/api/admin/auth/session/route.ts` is the real gate: verifies the posted
  Firebase ID token with `adminAuth.verifyIdToken`, resolves the caller's admin
  identity, and — only if they have any admin permission at all — mints an
  **HttpOnly, secure, `sameSite: lax`** session cookie via
  `adminAuth.createSessionCookie`. This is the pattern `web_client` (§5) should
  eventually move to.
- `lib/auth/adminAuthService.ts` resolves identity in three tiers: (1) a single
  hardcoded super-admin Firebase UID, always full access; (2) a legacy
  "pricingAdmins" allowlist on `app/admins` (full access); (3) granular
  role-based access via `admin_users/{uid}.roleIds[]` resolved against
  `admin_roles` docs. `lib/auth/requirePermission.ts` checks a specific
  permission string against the resolved identity; pages call this to gate
  their own rendering.

### Capabilities

Each admin section is backed by its own `lib/repositories/*AdminRepository.ts`:
user moderation, league/match/competition-rules/master-league/staff oversight,
organizer management, payment viewing + refunds, pricing config (the same
`app_config/pricing` doc `web_client` and the Flutter app read), coupons,
entitlement overrides, moderation cases/reports/global-chat-requests,
marketplace moderation, content moderation (posts/discussions/home), 
verification review, admin-authored notifications, role/permission management,
audit logging, system-health + build/version visibility, and football hub/news
config.

## 7. CI/CD & deployment

Eight GitHub Actions workflows under `.github/workflows/`:

| Workflow | Trigger | What it does |
|---|---|---|
| `android.yml` | push to `main`, manual | Builds release APK + AAB (Flutter 3.47.1 pinned), checks native-lib 16KB page alignment, uploads as artifacts (no store upload step) |
| `ios.yml` | push to `main` (paths: `lib/**`, `ios/**`, `assets/**`, pubspec), manual | Runs on `macos-26`. Regenerates the Xcode project from scratch every run (`flutter create`), then heredocs `Info.plist`/`Podfile`/`AppDelegate.swift`/a native Swift file into the checkout and registers them into the generated project via the `xcodeproj` Ruby gem. Builds + signs the IPA, uploads to TestFlight if API-key secrets are present |
| `web.yml` | push to `main`, manual | Builds Flutter Web (Flutter 3.24.5 — not kept in sync with the mobile pin) and deploys to Firebase Hosting, with a hand-rolled OAuth token mint to work around a Node 22 issue in the Firebase CLI's own auth library |
| `deploy_worker.yml` | push to `main` (path: `worker/**`), manual | Deploys the Cloudflare Worker via `wrangler-action`, pushes all Worker secrets, then self-tests two endpoints for an expected 401 |
| `deploy_firestore_rules.yml` | push to `main` (paths: `firestore.rules`, `firestore.indexes.json`, `firebase.json`), manual | Deploys rules + indexes via `firebase-tools`, using the same service-account secrets the Worker uses |
| `deploy_supabase_functions.yml` | push to `main` (path: `supabase/functions/**`), manual | Deploys every subdirectory under `supabase/functions/` — no hardcoded function list |
| `backfill.yml` | manual only | One-off Firestore data-migration script runner |
| `bootstrap-android-wrapper.yml` | manual only | Recovery utility: regenerates and commits the Gradle wrapper files back to `main` if they're missing |

Note: `web_client/` has **no dedicated CI workflow in this repo** — it's deployed
independently (almost certainly via Vercel's own git integration, which would
supply `FIREBASE_SERVICE_ACCOUNT_KEY` as its own environment variable). Same for
`esportlyic-admin/`.

Other top-level config: `codemagic.yaml` appears to be vestigial (a single
debug-build workflow with a placeholder email, superseded by `android.yml`).
`firebase.json` configures Firestore rules/indexes paths and a single Hosting
target serving `build/web` (the Flutter Web build). App version/build number is
tracked in `pubspec.yaml` (`version: 1.9.18+85`); iOS CI overrides the build
number per-run (`--build-number=$GITHUB_RUN_NUMBER`) since App Store Connect
rejects a re-used build number, while Android/Web builds carry the static one.

## 8. Security model (summary)

The two real enforcement boundaries in this system are **`firestore.rules`**
(for anything a client touches in Firestore directly) and **the Worker's
`_verifyFirebaseIdToken` check** (for anything that needs a secret or
server-side trust). Client-side checks in any of the four apps — a React guard
component, a Dart `if (isOwner)`, an admin panel's hidden menu item — are UX,
not security; they're trivially bypassed by anyone calling Firestore or the
Worker directly with their own auth token. The schema in §4 is designed around
that: self-registration is scoped to the member role only, badge self-writes
can't claim an admin-trust source, payment documents are keyed by an
idempotent provider-transaction ID rather than trusting client-reported
status, and so on.

As of this pass, a full security audit (Worker, Firestore rules, both Next.js
apps, the Flutter client, git history, and CI/CD) found and fixed several
issues now closed on `main`: two fully unauthenticated Worker endpoints, a
payment-replay/reattribution hole, five Firestore privilege-escalation/leak
bugs, a stored XSS in organizer social links, an open-auth NFT-minting
endpoint, an open redirect, and critical Next.js RCE CVEs in `web_client`'s
prior Next.js version. Items intentionally left for a follow-up pass (flagged,
not silently ignored):

- `web_client`'s non-HttpOnly raw-ID-token session cookie (§5) — fixing this
  properly means adopting `esportlyic-admin`'s session-cookie-exchange pattern,
  which touches every page that currently reads the cookie directly.
- Match/call-room "host" role in the Worker's LiveKit token endpoint is still
  client-declared (only league-room host status is independently verified) —
  closing this needs the client to also send a `leagueId` alongside a
  `matchId`, which is a small API-contract change but wasn't made in this pass.
- `users/{userId}/stats` write authorization is intentionally broad (any
  signed-in user can write specific counter fields on someone else's stats
  doc) because the real writers are followers/organizers acting on someone
  else's behalf by design — tightening this to true per-writer authorization
  would require moving those two flows (follow-count increment, match-result
  recording) server-side.
- No Content-Security-Policy on either Next.js app (basic headers were added;
  a CSP needs to be tested against every third-party integration — Firebase
  Auth popups, Google OAuth, Cloudinary — before it can be added safely).
- Full remediation of the Next.js DoS advisories still flagged by `npm audit`
  on `esportlyic-admin` requires a major-version migration to Next.js 15.x.
- Rate limiting on the Worker's payment-verification and football/news proxy
  endpoints doesn't exist yet.

For the full list of what was found and exactly what changed, see the git log
on `main` — every fix in this pass is its own commit with a detailed message
explaining the vulnerability and the fix.
