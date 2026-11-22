# eSportlyic — App Store compliance audit report

| | |
|---|---|
| Date | 2026-11-22 |
| App | eSportlyic, bundle `com.eleaguehub.app` |
| Audited code | branch `claude/repo-exploration-szie8r` (= `main` + this audit's changes) |
| Last rejected build | 1.9.21 (222), rejected 2026-11-20 — 2.5.4, 3.0.0 |
| Guidelines version | App Review Guidelines last updated 2026-10-16 |
| Environment | Linux container. **No macOS, Xcode, iOS Simulator, device, App Store Connect or sandbox Apple ID was available.** Everything that needs those is listed in §9 and §10 as not verified. |

Contents: 1 Documentation library · 2 Compliance matrix · 3 Application audit
· 4 Rejection root causes · 5 Subscriptions and payments · 6 Privacy and
security · 7 iOS build · 8 Changes made · 9 Testing · 10 Outstanding items
(your actions) · 11 Release-readiness decision · 12 Prevention checklist.

---

## 1. Apple documentation library

156 official Apple pages were requested and stored under `docs/apple-compliance/`
on 2026-11-22: App Review Guidelines (version of 2026-10-16) and Apple's
per-guideline reference pages, App Review submission help, App Store Connect
help (in-app purchases, subscriptions, privacy, age ratings, export compliance,
Digital Goods and Services questionnaire, China/Korea/EU compliance pages),
StoreKit / App Store Server API / Server Notifications documentation, privacy
manifest and required-reason API documentation, third-party SDK requirements,
background-mode and permission-key references, Sign in with Apple, Declared Age
Range, Human Interface Guidelines (In-App Purchase, Sign in with Apple, managing
accounts, privacy, onboarding, launching), the Standard EULA and Apple Developer
news from late 2024 to 2026-11-18.

* 152 retrieved with content; 4 not (one HTTP 404, two pages that no longer
  exist at their URLs, one JavaScript-only redirect). Each is recorded with the
  reason, and the same requirement was captured from another official page.
* Raw files are preserved byte-for-byte with SHA-256 in `manifest.json`;
  `.md` files are text extractions for searching.
* The index (`README.md`) separates requirements **in force now**,
  **future-dated** ones (age-rating declarations for all apps by 2027-01-12;
  iOS 27 SDK from April 2027) and **territory-specific** ones (EU, Australia,
  Brazil, Texas/Utah/Louisiana, Korea, China mainland, US).
* `tools/` holds the script and URL lists to refresh the library.

## 2. Compliance matrix

`docs/apple-compliance/COMPLIANCE_MATRIX.md` covers sections 1–5 of the
guidelines plus age-rating and territory items, each with source, evidence,
status, risk, required action and how to verify. Summary after this audit:

| Status | Count | Examples |
|---|---|---|
| Fixed in this audit | 16 | 2.5.4 background audio; StoreKit 2 activation; price mismatches; UGC filter; account-deletion re-auth; Apple token revocation; placeholder "Guides"; camera request; other-platform wording |
| Pass | ~30 | Restore Purchases, Sign in with Apple (4.8), reporting/blocking, push background mode, marketplace physical goods, rewarded-ad incentive |
| Partial / potential risk | ~10 | 3.0 (needs reviewer text + review notes), coupons, localized purpose strings, NCII/image moderation, Organizer Verification product type, ATT/privacy labels |
| Unknown (needs ASC/device) | ~15 | Demo account, ASC products, App Privacy answers, age rating answers, iPad, deletion server function |
| Fail (not an App Review blocker) | 1 | Users can write their own paid-league receipt document (revenue integrity) |

## 3. Application audit

Method: static audit of every user flow's code path on iOS, the CI pipeline
that produces the shipped binary, the Cloudflare worker that verifies
purchases, Firestore rules, and `web_client` where it writes the same data. No
flow could be executed on iOS (see §9).

| Area | Finding | Result |
|---|---|---|
| Registration / login | Email/password, Google, Sign in with Apple (iOS). Terms were never presented. | Terms + zero-tolerance line added to sign-in. 4.8 passes. |
| Password recovery | `/forgot-password` route exists. | Not executed. |
| Guest access | Anonymous auth exists in code but is not auto-enabled; app requires an account — justified by account-based features (5.1.1(v)). | OK |
| Onboarding / profile | No compliance issue found. | — |
| Leagues, fixtures, results, standings | No compliance issue found; 100 existing logic tests pass. | — |
| League creation (free plan) | Rewarded ad shown before creating; **fails open** if no ad (no fill/failed show). Allowed by 3.2.2(x). | OK |
| Paid league access | "Pay to unlock" for UCL Group/Swiss leagues and full classic leagues could **never succeed on iOS** and its error mentioned paying on the web via Flutterwave. | Fixed: by owner decision, paid league access is not sold in the store apps — no pay sheet on iOS/Android, those leagues open free; web unchanged. |
| Coupons | Organizers bought participant coupons; coupons only discount paid league access. | Owner decision: not used. Hidden on iOS/Android (League admin tiles, Profile → Coupons); web unchanged. |
| Organizer Verification | Fee shown on iOS came from the web price list (e.g. NGN), not the App Store. | Fixed: App Store price or "Price shown by the App Store at checkout". |
| League creation / coupon checkout | Totals shown in web currency, computed from coupon count; StoreKit charges a fixed product price. | Fixed for iOS display. |
| Subscriptions (Pro/Elite) | Purchase succeeded but **activation failed** for StoreKit 2 transactions (worker accepted only StoreKit 1 receipts). | Fixed in worker. |
| Chats (private, league, organizer, global), voice notes | No content filter. Report/block present. | Filter added (client + repository layer, iOS and web). |
| Feed posts, edits, comments; discussions | No content filter. | Filter added. |
| Voice rooms (LiveKit) | Pre-permission dialog said "Allow"; requested camera for audio-only rooms; denial text said "Android Settings". Call ends when the screen is left on iOS (no background audio). | Fixed wording and camera request; foreground-only behaviour documented in review notes. |
| Live view / Android overlay | Android-only; all overlay calls no-op on iOS. | OK |
| Notifications | FCM, `remote-notification` background mode justified. | OK |
| Search, discovery | "Guides" row showed only "coming soon". | Removed (2.1 placeholder). |
| Marketplace | Affiliate links to external stores for physical goods. | OK (3.1.3(e)). |
| Account deletion | Destructive steps ran *before* Firebase's recent-login check, so long sessions ended half-deleted with no way to re-authenticate; no Apple token revocation; no subscriber billing notice; server function not in repo. | Re-auth first, Apple revocation, notice + Manage Subscriptions link added. Server function: §10. |
| Error / empty / offline states | Prior work (cache fallback, crash fixes Nov 14). Messages inbox depends on a Firestore index that must be created in the console. | §10 |
| Ads | Comments and privacy manifest claimed non-personalized AdMob on iOS; code used default requests. | iOS requests now explicitly non-personalized. |

## 4. Rejection root-cause report

Full detail: `docs/apple-compliance/REJECTION_HISTORY.md`.

**2.5.4 (rejected three times) — root cause confirmed.** `ios.yml` writes
`ios/Runner/Info.plist` from an inline heredoc on every build. The October fix
removed `audio` from the committed plist only; the heredoc kept it, so 1.9.20
and 1.9.21 shipped `UIBackgroundModes = [audio, remote-notification]` with no
iOS feature playing background audio. Evidence: parsing the old heredoc gives
`['audio', 'remote-notification']`; the new one gives `['remote-notification']`.
A CI guard now fails any build that declares another background mode.

**3.0.0 (rejected 2026-11-20) — probable causes fixed; exact text needed.**
The reviewer message was not available. Findings that fall under 3.0's
"business model must be obvious / IAPs immediately obvious / no irrationally
high prices": prices shown on iOS that differed from what StoreKit charged
(three screens), a purchase that could never complete and pointed to paying on
the web, subscriptions that charged but didn't unlock (StoreKit 2), and two
catalog products with no purchase path. All code-side causes are fixed; the
App Store Connect side (review notes, products attached, questionnaire) is in §10.

**2.1.0 (1.9.20) — candidates fixed; exact text needed.** Most likely one of:
Messages inbox load error (index), StoreKit 2 activation failure, paid-league
dead end, Android UI on iOS (fixed Nov 1).

## 5. Subscription and payment audit

All iOS purchases go through `in_app_purchase` 3.3.1 / `in_app_purchase_storekit`
0.4.17 (**StoreKit 2** by default). Routing is decided at compile time by
`PaymentPlatformConfig.routeIOSPaymentsToStoreKit` (no remote switch).

| Product ID (code) | Expected ASC type | Where bought on iOS | Unlocks | Verification / entitlement | Status |
|---|---|---|---|---|---|
| `pro_1mo`, `pro_3mo`, `pro_6mo`, `pro_yearly` | Auto-renewable subscription (1/3/6/12 months), one group with Elite | Upgrade plan screen | Pro: 5 master leagues, 9 competitions each | Worker `/activate` verifies the App Store transaction (now JWS), sets custom claims + `users/{uid}` + `entitlements/master_league`; App Store Server Notifications V2 handle renewal, grace, expiry, refund, revoke | Fixed (activation); restore OK |
| `elite_1mo`, `elite_3mo`, `elite_6mo`, `elite_yearly` | Same group | Upgrade plan screen | Elite: unlimited | Same | Same |
| `organizer_verification_fee` (iOS) / `organizer_verification` (Play) | **Consumable**, $149.99 | Settings / organizer profile → verification | Submits application for manual review; badge if approved | Purchase recorded in `payments/` (product type `organizer_verification`); entitlement = admin approval | **New iOS product — create in ASC.** `organizer_verification` exists in ASC as a yearly subscription (owner decision 2026-11-22: one-time fee) — do not attach it |
| `organizer_verification_renewal_fee` (iOS) / `organizer_verification_renewal` (Play) | Consumable | Organizer profile → renew | Renewal review | Same | **New iOS product — create in ASC** |
| `league_creation_unlock` | — | **Not reachable on iOS.** Android only: one-time unlock when a Basic user reaches 3 leagues (iOS shows "Upgrade plan" → subscriptions instead) | — | — | Do not submit for iOS |
| `league_access_unlock` | — | **Not offered in the store apps** (owner decision 2026-11-22) | — | — | Do not create / do not submit |
| `league_addons_pack` | — | Was bought by the coupon checkout; coupons are now hidden in the store apps | — | — | Do not submit |
| `premium_subscription` | — | **No purchase path** | — | — | Do not submit |

Other checks:

* **Restore:** button on the upgrade screen; restored and redelivered
  transactions are recorded by an app-level listener. Works for subscriptions;
  consumables are not restorable (correct).
* **Disclosures (3.1.2):** title, duration, App Store price, auto-renew text,
  Terms and Privacy links are on the purchase screen (commit `a073ae0d`).
  A "Manage subscriptions" link is now in account deletion; add one to the
  upgrade screen (recommended).
* **Pending / failed / cancelled:** pending transactions wait; errors and
  cancellations return clear messages; 5-minute timeout.
* **Refunds / revocations / expiry:** handled server-side by Server Notifications
  V2 (`EXPIRED`, `GRACE_PERIOD_EXPIRED`, `REFUND`, `REVOKE` revoke the entitlement).
* **Other devices / account switching:** the subscription is linked to the
  eSportlyic account that first activated it (`apple_transactions/{originalTransactionId}`);
  restore on another device re-activates through the worker.
* **Organizer Verification and payment rules:** it is a digital service
  delivered in the app (a badge and verified status), so it **must** use In-App
  Purchase — it does. No exemption in 3.1.3 applies to it.
* **Issues not changed (need decisions, §10):** transaction is finished before
  the receipt is written (rare lost-record risk); verification sold as
  consumable rather than non-renewing subscription; paid-league receipts are client-writable (revenue integrity);
  web-bought subscriptions can be used on iOS (allowed by 3.1.3(b)).

## 6. Privacy and security audit

**Permissions (iOS)**

| Permission | Purpose string present | Used for | Requested when | Finding |
|---|---|---|---|---|
| Camera | Yes | QR scanner, profile/media capture | At use | QR pre-prompt "Continue" (Oct). Voice room no longer asks for it. |
| Microphone | Yes | Voice rooms, voice notes | At use | Pre-prompt now neutral "Continue"; denial text platform-neutral |
| Photo library (read / add) | Yes | Upload / save media | At use | OK |
| Local network | Yes | WebRTC/LiveKit connectivity | System-triggered | OK |
| Notifications | (system prompt) | Chat and league push | App start / registration | OK |
| Location, contacts, Bluetooth, tracking | Not declared | Not used | — | OK — no ATT key, no location plugin |

Purpose strings are English-only while the app is localized (Apple says they
must be localized) — §10.

**SDKs:** Firebase (Auth, Firestore, Messaging, Crashlytics, Storage),
Supabase, Cloudinary, LiveKit/WebRTC, AdMob, Google Sign-In, Sign in with
Apple, just_audio, record, image_picker, mobile_scanner, webview. These ship
their own privacy manifests; the app manifest declares email, name, user ID,
photos/videos, audio, other user content, crash data, purchase history, not
used for tracking, plus UserDefaults (CA92.1) and file timestamp (C617.1)
reasons. No third-party AI services were found (5.1.2(i) not triggered).

**Tracking/ATT:** no ATT prompt; `NSPrivacyTracking=false`; iOS ad requests now
explicitly non-personalized. App Privacy answers in ASC must still list the
data AdMob collects for third-party advertising (§10).

**Account deletion:** in-app; re-authentication first (Apple / Google /
password); deletes Storage files, local data, server data via Supabase
function `delete-user-data`, revokes Apple tokens, deletes the Firebase Auth
user; subscribers see the billing notice. The server function is not in this
repository — whether it deletes shared posts/comments/messages could not be
verified (§10).

**Security:** no secrets were added or exposed; no Firestore rule was weakened.
One pre-existing weakness was found and not changed:
`users/{uid}/leagueCharges/{leagueId}` can be created by the user themselves.

## 7. iOS build audit

| Item | Value | Status |
|---|---|---|
| Build system | GitHub Actions `ios.yml` on `macos-26` (Xcode 26.x); `flutter create --platforms=ios` each run; Info.plist, entitlements, Podfile, AppDelegate, privacy manifest written from heredocs | Working, but means **`ios/Runner/*` in the repo is not what ships** |
| Flutter / Dart (CI) | Flutter 3.47.1 pinned | OK |
| SDK requirement | iOS 26 SDK required since 2026-04-28 — met by Xcode 26 | OK (iOS 27 SDK from April 2027) |
| Deployment target | iOS 15.0 (Podfile + post_install) | OK; StoreKit 2 available |
| Device family | iPhone + iPad (flutter create default) | iPad not tested — §10 |
| Background modes | `remote-notification` only (was also `audio`) | Fixed + guarded |
| Entitlements | `aps-environment=production`, Sign in with Apple, associated domains `esportlyic.com` | OK |
| Encryption | `ITSAppUsesNonExemptEncryption=false` | OK (uses only standard OS encryption) |
| Privacy manifest | **Was never shipped (found 2026-11-22 by inspecting build 239's IPA):** the CI registered it with xcodeproj's `add_file_references`, which puts it in Compile Sources, where Xcode does not copy `.xcprivacy`; the file was also invalid XML (`--` inside a comment). Fixed: `add_resources` (verified on a freshly generated project), comment repaired (parses with plistlib; CI runs `plutil -lint`), and the Verify IPA step now fails the build if `Runner.app/PrivacyInfo.xcprivacy` is missing/invalid or a background mode other than `remote-notification` ships. SDK manifests (50) were always present | Fixed; confirm on the next IPA |
| Signing | Manual distribution certificate + provisioning profile from secrets | Not inspected (secrets) |
| Build number | `github.run_number` | OK |
| `pubspec.lock` | **Not committed** — each build resolves the newest compatible plugins (this is how StoreKit 2 arrived unnoticed) | Recommendation: commit `pubspec.lock` |
| Flutterwave | SDK compiled in; keys now excluded from iOS build | Defence in depth |
| Key plugin versions (resolved 2026-11-22) | livekit_client 2.13.2, flutter_webrtc 1.6.3, firebase_auth 5.7.0, firebase_messaging 15.2.10, google_mobile_ads 9.0.0, in_app_purchase 3.3.1 / storekit 0.4.17, sign_in_with_apple 6.1.4, google_sign_in 6.3.0, permission_handler 11.4.0, mobile_scanner 7.5.0 | No known App Review blockers |

## 8. Changes implemented (2026-11-22)

| File(s) | Change | Why |
|---|---|---|
| `.github/workflows/ios.yml` | Removed `audio` background mode; new "Validate generated Info.plist against App Store requirements" step; Flutterwave keys removed from the iOS build | 2.5.4 root cause; prevent recurrence; 3.1.1 defence in depth |
| `ios/Runner/Info.plist` | Header comment: not the shipped file | Prevents repeating the October mistake |
| `worker/src/index.js`, `worker/src/apple_jws_transaction.js` (+ test) | Verify StoreKit 2 JWS transactions with the existing pinned-root verifier; StoreKit 1 receipts unchanged | Subscriptions bought on iOS could not activate |
| `lib/core/services/payments/google_play_billing_service.dart` | `fetchProductPrice()` | Show real App Store prices |
| `lib/features/leagues/logic/league_charges_payment_service.dart` | Neutral "not available" wording; `PaymentPlatformConfig.offerPaidLeagueAccess` (false in store apps) used by the QR-join flow, leagues list, live leagues and access guard so no paid-access sheet is shown on iOS/Android | 2.1 dead end; 3.1.1 steering text; owner decision |
| `lib/core/config/payment_platform_config.dart` | Removed messages saying "Web continues to use Flutterwave" | Steering |
| `lib/features/master_leagues/presentation/organizer_verification_application_screen.dart` | App Store price on iOS; never the web price | Price shown ≠ price charged |
| `lib/features/leagues/presentation/league_creation_payment_screen.dart`, `league_access_guard.dart` | App Store price on iOS | Same |
| `lib/features/master_leagues/logic/master_league_payment_service.dart` | "Play Store" → "store" in a shared error | 2.3.10 |
| `lib/core/services/account_deletion_service.dart`, `lib/features/profile/presentation/delete_account_flow.dart` | Re-authenticate before deleting; Apple token revocation; subscriber billing notice + Manage subscriptions; password prompt | 5.1.1(v) |
| `lib/features/call/presentation/call_room_screen.dart` | Mic only (no camera); "Continue" instead of "Allow"; device-neutral settings text | 5.1.1(iii)/(iv), 2.3.10 |
| `lib/core/config/ad_config.dart`, ad widgets | iOS ad requests non-personalized | Match privacy declarations (5.1.2) |
| `lib/core/moderation/objectionable_content_filter.dart` (+ test); chat, feed, discussion repositories and chat screens | Objectionable-language filter before publishing | 1.2 |
| `web_client/lib/moderation/objectionableContentFilter.ts` (+ test); web chat/feed/discussion writers | Same filter on web (parity per CLAUDE.md) | Web content appears in the iOS app |
| `lib/features/auth/presentation/login_screen.dart`, `terms_of_service_screen.dart` | Terms/Privacy agreement + zero-tolerance line; Terms clause | 1.2 |
| `lib/features/discovery/presentation/community_screen.dart` | Removed "Guides — Soon" placeholder | 2.1 |
| `lib/core/locale/app_localizations_14.dart` | New English strings (other locales fall back to English) | UI text for the above |
| `docs/apple-compliance/**` | Library, matrix, history, report, checklist, review notes | Deliverables |

No database data, Firestore rules, product identifiers, secrets or signing
settings were changed.

## 9. Testing report

**Executed (all passed):**

| Check | Result |
|---|---|
| `flutter analyze` (whole app) | 0 errors; 2284 issues in total (2285 before the changes — all pre-existing info/warning level); the only note on changed lines is an existing-style `withOpacity` info |
| `flutter test` | 131/131 (100 existing + 31 new content-filter tests) |
| `node worker/src/apple_jws_transaction.test.js` | 14/14 |
| `node --check worker/src/index.js` | Syntax OK |
| `npx tsx web_client/lib/moderation/objectionableContentFilter.test.ts` | All pass (mirrors Dart cases) |
| `npx tsc --noEmit` (web_client) | Clean |
| `ios.yml` YAML parse; generated Info.plist parse | OK; background modes `['remote-notification']` (was `['audio','remote-notification']`) |

Local toolchain: Flutter 3.50.0 / Dart 3.14.0 (CI uses 3.47.1), Node 22.

**Not executed — could not be verified here:** iOS release build/archive,
Xcode validation and privacy report, the new CI guard step itself (needs
macOS `PlistBuddy`), simulator or device runs, iPad, TestFlight, sandbox
purchases and restores, worker JWS verification against a real Apple-signed
transaction (only the field mapping is unit-tested; the signature verifier is
the existing one used for Server Notifications), Sign in with Apple token
revocation, account deletion end-to-end, push notifications, IPv6/NAT64,
web UI flows. These are in `PRE_SUBMISSION_CHECKLIST.md` §C–§D.

## 10. Outstanding items — your actions

**Before the next submission (blocking):**

1. **Reply to App Review** (done when sent): confirm Organizer Verification
   is $149.99 USD and explain it is now a one-time purchase
   (`organizer_verification_fee`), not a yearly subscription. Messages are
   transcribed in `REJECTION_HISTORY.md`.
2. **App Store Connect → In-App Purchases:** create the consumables
   `organizer_verification_fee` ($149.99) and `organizer_verification_renewal_fee`
   (renewal price); attach them and the plan subscriptions to the version,
   each with a review screenshot and description. **Do not attach** the
   yearly subscription `organizer_verification`. **Do not create or
   attach** `league_access_unlock` (paid league access is not sold in the
   app), `premium_subscription` or `league_addons_pack`.
   Also **do not attach** `league_creation_unlock` (not reachable on iOS).
   Coupons are not used and are hidden in the store apps (owner decision
   2026-11-22). The iOS app sells only Pro/Elite plans and Organizer
   Verification.
3. **Demo account** that signs in, is on the free plan, and has sample leagues.
4. **Review notes:** fill in `APP_REVIEW_NOTES_TEMPLATE.md` and paste it.
5. **Age rating questionnaire** (also answer the new Shared Location and Dating questions now, even though App Store Connect says they can wait until 2027-01-15): social media capabilities Yes; messaging/UGC
   Yes; Shared Location No; Dating No; in-app controls (blocking, reporting, filtering) Yes.
6. **Digital Goods and Services questionnaire** (if shown): Apple In-App Purchase only.
7. **App Privacy:** confirm AdMob's data types are listed for third-party
   advertising, not used for tracking, alongside Firebase/Crashlytics data.
8. **Firebase console:** create the `private_threads` composite index
   (`participantIds` array-contains + `lastMessageAtMs` desc); confirm the Apple
   sign-in provider has Services ID, Team ID, Key ID and private key (needed for
   token revocation).
9. **Supabase:** confirm `delete-user-data` is deployed; send me its source (or
   commit it) so it can be checked/extended to delete posts, comments, messages
   and media.
10. **Version number:** App Store Connect shows version 1.9.21; the new build is **1.9.22** (`pubspec.yaml`). Change the version number on the rejected version to 1.9.22 (or create a 1.9.22 version), attach the new build, and do not resubmit build 222 — it still declares background audio.
11. **China mainland** (only if selected in Pricing and Availability): either complete App Information → App Compliance (AI-Generated or Synthetic Content: No; Security Assessment: No — the app has neither feature) by 2027-01-31, or remove China mainland from availability. The app relies on Firebase, Google Sign-In and AdMob, which are generally not reachable there.
12. After the merge to `main`, confirm the **Deploy Worker** and **iOS CI**
    workflows succeed, then run `PRE_SUBMISSION_CHECKLIST.md` §C–§E on the TestFlight build.

**Recommended (not blocking, decisions needed):**

* Organizer Verification as a Non-Renewing Subscription.
* Localized `InfoPlist.strings` for purpose strings.
* Translations for the new English strings.
* Image moderation policy (NCII) and a stated report-response time.
* Server-side writing of paid-league receipts and tightening that rule.
* Finish transactions only after the receipt is saved.
* Commit `pubspec.lock` so plugin upgrades are deliberate.
* Manage Subscriptions link on the upgrade screen; decide iPad support.
* Legal review for Australia (under-16 social media), Texas/Utah/Louisiana age
  assurance, EU trader status.

## 11. Release-readiness decision

**Not ready to submit yet — ready after items 1–12 in §10 are done and the
checklist passes on a TestFlight build.**

Evidence for: the confirmed 2.5.4 root cause is fixed in the file that ships
and guarded in CI; every code-side cause found for 3.0/3.1/2.1 is fixed;
account deletion, UGC moderation and permission wording now meet the
downloaded guideline text; all automated checks pass.

Evidence against submitting today: none of the changes has run on an iOS
device or in the sandbox; the 3.0.0 reviewer text has not been compared;
App Store Connect metadata, questionnaires, demo account and privacy answers are
unverified; the account-deletion server function is unverified.

No approval can be guaranteed; this removes the problems that could be found.

## 12. Future prevention

`compliance-audit/PRE_SUBMISSION_CHECKLIST.md` — refresh the rules, run the
automated checks, **inspect the uploaded build**, test on device with sandbox
purchases, verify App Store Connect, and record every rejection the same day.
