# eSportlyic — App Review rejection history

Bundle ID `com.eleaguehub.app`. Builds are produced by `.github/workflows/ios.yml`,
which sets `CFBundleVersion` to the GitHub Actions run number (so App Store
Connect build numbers do not match the `+NN` in `pubspec.yaml`).

## What this file is based on

* **Exact App Review messages** — supplied by the product owner on
  2026-11-22 as screenshots of App Store Connect → the version → Messages (3).
  They are transcribed in the next section. All three messages belong to the
  same submission (`26cb5729-0fe5-4f7f-9fb4-e8b9d86dc80f`); the version record
  was renamed 1.9.19 → 1.9.20 → 1.9.21 between rounds.
* Root-cause analysis below was written before the messages were available
  (from the owner's rejection summary and commit history); where the messages
  differ from that analysis, the messages win and the difference is stated.

## Summary

| Version | Build | Guideline(s) cited | Status after this audit |
|---|---|---|---|
| 1.9.19 | 186 | 5.1.1(iv), 2.1(a), 2.5.4 | 5.1.1(iv) fixed (camera pre-prompt button now "Continue"). 2.1(a): demo account. 2.5.4 fix never shipped — now fixed |
| 1.9.20 | 207 | 2.5.4, 2.1(a) | 2.5.4 fixed in build 237+. 2.1(a): demo account with pre-populated content "such as chats" (reviewer's screenshot: Messages "Couldn't load your chats" — Firestore index, created by owner 2026-11-22) |
| 1.9.21 | 222 | Guideline 3 automated price check (shown as 3.0.0), 2.5.4 | 2.5.4 fixed in build 237+. **3.0.0 = Apple asks the developer to confirm the Organizer Verification price ($149.99 USD per year) — reply required.** Not the price-display issues assumed earlier |

## Exact App Review messages

### 2026-10-21 — version 1.9.19 (186), reviewed on iPad Air 11-inch (M3)

**Guideline 5.1.1(iv) — Legal — Privacy — Data Collection and Storage**
> The app encourages or directs users to allow the app to access the camera.
> Specifically, the app directs the user to grant permission in the following
> way(s): A custom message appears before the permission request, and to
> proceed users press a "Grant permission" button. Use words like "Continue"
> or "Next" on the button instead.

Attachment `Screenshot-1021-33529p.m..png`: QR scanner pre-prompt
("Allow Camera Access … Open settings / **Grant permission** / ENTER CODE
INSTEAD"). **Status:** fixed — the button key `qr_scanner_grant_permission`
now reads "Continue" (checked 2026-11-22; no "Grant permission" text left in `lib/`).

**Guideline 2.1(a) — Information Needed**
> We are unable to successfully access all or part of the app. In order to
> continue the review, we need to have a way to verify all app features and
> functionality for all account types. Typically this is done by providing a
> demo account that has access to all features and functionality in the app.

Attachment `Screenshot-1021-33818p.m..png`: **Global Chat — "Access
required. Request access to join the global chat. Only approved members can
send messages."** The reviewer could not get into Global Chat with the demo
account. **Fixed 2026-11-22 (owner decision):** the approval step was
removed. Users tap **Join** and are in immediately (app, web and
`firestore.rules`); admins can still remove a user by setting `rejected`,
which the user cannot undo. Rules verified on the Firestore emulator (16 cases).

**Guideline 2.5.4 — Performance — Software Requirements**
> The app declares support for audio in the UIBackgroundModes key in the
> Info.plist but we are unable to locate any features that require persistent
> audio. … If the app does not have a feature that requires persistent audio,
> it would be appropriate to remove the "audio" setting from the
> UIBackgroundModes key.

### 2026-11-01 — version 1.9.20 (207), reviewed on iPhone 17 Pro Max

**Guideline 2.5.4** — same text as above.

**Guideline 2.1(a) — Information Needed** — same text as above, plus:
> Additionally, make sure the demo accounts you provide include pre-populated
> content so that we can verify all the features in the app, such as chats.

Attachment `Screenshot-1101-104711.png` (the owner's screenshot from 02:47
local time matches 10:47 UTC): **Messages — "Couldn't load your chats. Try
Again."** This is the missing `private_threads` Firestore index; the owner
created it on 2026-11-22. **Action:** the demo account must already have
private messages and league/organizer chat messages.

### 2026-11-20 — version 1.9.21 (222), reviewed 2026-11-19 on iPhone 17 Pro Max and iPad Air 11-inch (M3)

**App Review Guideline Issue (Guideline 3; App Store Connect lists it as "3.0.0 Business: Preamble")**
> This is an automated message. The review of this submission cannot proceed.
> Additional verification is needed before the review continues.
> Specifically, can you confirm the following In-App Purchase product(s) have
> the correct intended price(s): Organizer Verification ($149.99 USD per
> year)? Once we receive your confirmation, we will continue our review.

**What this means:** it is a price-confirmation hold, not a finding about
the app's behaviour. It is answered with **Reply to App Review** in App Store
Connect. Because the review "cannot proceed" until then, Apple did not test
the rest of the app in this round.

**Also found from the same screenshots:** App Store Connect lists
"Organizer Verification" in a **Subscription Group** at **$149.99 per year**
(an auto-renewable subscription), while the app code buys
`organizer_verification` as a one-time product and the iOS screen says
*"requires a one-time … verification fee"*. Apple's payment sheet would show
a yearly auto-renewing subscription. That mismatch must be resolved before
resubmitting (see AUDIT_REPORT §10).

**Guideline 2.5.4** — same text as above.

---

## Round 1 — version 1.9.19

| Field | Detail |
|---|---|
| Submission / rejection date | October 2026 (before Oct 21; exact dates not recorded) |
| Guidelines | **2.5.4** Software Requirements · **5.1.1(iv)** Access · **2.1(a)** App Completeness (demo account access) |
| Exact reviewer explanation | Not available. From commit `c6b41e1f` (2026-10-21): 2.5.4 concerned `UIBackgroundModes` declaring `audio`; 5.1.1(iv) concerned the QR scanner's pre-permission button reading "Grant permission"; 2.1(a) concerned access to a demo account. |
| Root cause | 2.5.4: the app declared the `audio` background mode, but no iOS feature plays audio in the background (the floating voice overlay that keeps calls alive is Android-only). 5.1.1(iv): action-oriented wording on a custom screen shown before the system permission prompt. 2.1(a): App Review Information lacked a working demo account. |
| Fix implemented then | `c6b41e1f`: QR button text changed to "Continue" in all locales; `audio` removed from **`ios/Runner/Info.plist`**. |
| Was it effective? | 5.1.1(iv): yes (not cited again). **2.5.4: no** — see Round 3. 2.1(a): depends on App Store Connect (not a code change). |

## Round 2 — version 1.9.20

| Field | Detail |
|---|---|
| Submission date | After 2026-10-21 (`3ab95b96` bumped to 1.9.20) |
| Rejection date | Before 2026-11-01 |
| Guidelines | **2.1.0** Performance: App Completeness · **2.5.4** Software Requirements |
| Exact reviewer explanation | Not available. |
| Root cause — 2.5.4 | **The Round 1 fix never reached the binary.** `.github/workflows/ios.yml` regenerates `ios/Runner/Info.plist` from an inline heredoc on every build, and that heredoc still contained `<string>audio</string>` (last changed `77174d02`, 2026-10-09). Commit `c6b41e1f` edited only the committed copy, which CI overwrites. |
| Root cause — 2.1.0 (candidates; unconfirmed without reviewer text) | (1) Messages inbox stuck on an error because a required Firestore composite index was missing (fixed in `92ebcc2c` on Nov 1, but the index must be **created in the Firebase console** — the CI index deploy is a no-op due to an IAM gap). (2) Found in this audit: iOS subscription purchases could not activate (worker rejected StoreKit 2 transactions — see Round 3). (3) Found in this audit: paid-league "Pay to unlock" could never succeed on iOS. (4) Android-only UI visible on iOS (fixed Nov 1). |
| Fix implemented | 2.5.4 and candidates (2)–(3): this audit (2026-11-22). (1): `92ebcc2c` + manual index creation. (4): Nov 1. |

## Round 3 — version 1.9.21, build 222

| Field | Detail |
|---|---|
| Submission date | After 2026-11-01 (`ee27ef75` bumped to 1.9.21) |
| Rejection date | **2026-11-20** |
| Guidelines | **2.5.4** Performance: Software Requirements · **3.0.0** Business: Preamble |
| Exact reviewer explanation | **Not available — please provide.** The App Store Connect version page (screenshot supplied 2026-11-22) shows only the guideline titles — "2.5.4 Performance: Software Requirements" and "3.0.0 Business: Preamble" — and status **Rejected**. The reviewer's full message is on the submission details page (**View Submission** link in the red banner). |
| Root cause — 2.5.4 | Same as Round 2: CI-generated `Info.plist` still declared `audio` background mode. Verified on 2026-11-22 by parsing the heredoc: old output `UIBackgroundModes = ['audio', 'remote-notification']`. |
| Root cause — 3.0.0 (most likely causes found; confirm against reviewer text) | 3.0's preamble covers business models that are "not obvious", in-app purchases that "aren't immediately obvious", and "irrationally high prices". The audit found several ways the iOS build presented prices and purchases that did not match what StoreKit actually charges or delivers: **(a)** Organizer Verification showed the web (Flutterwave/NGN) fee from Firestore, while StoreKit charges the App Store price; **(b)** the league-creation / coupon checkout showed a web-currency total computed from coupon count, while StoreKit charges a fixed product price; **(c)** the league access guard showed a web "Entry fee"; **(d)** "Pay to unlock" for paid leagues could never complete on iOS and its error told users "Web continues to use Flutterwave" (pointing to another way to pay); **(e)** subscriptions bought through StoreKit 2 failed to activate because the server only accepted StoreKit 1 receipts, so a paid purchase unlocked nothing; **(f)** two products in the code catalog (`premium_subscription`, `league_addons_pack`) have no way to be purchased in the app — if either was submitted with the build, the reviewer could not find it. App Store Connect may also be involved (Digital Goods and Services questionnaire answers, App Review notes not explaining who pays for what). |
| Fix implemented | 2026-11-22 (this audit) — see table below. |
| Test evidence | `flutter analyze` 0 errors; `flutter test` 131/131 pass (31 new); worker JWS tests 14/14; web filter tests pass; `tsc --noEmit` clean; `ios.yml` parses and the regenerated plist no longer contains `audio`. **No iOS build, simulator, device or sandbox purchase test was possible in this Linux environment** — see AUDIT_REPORT §9. |
| Resolved? | 2.5.4: **fixed and guarded in CI**; confirm on the next uploaded build (see checklist). 3.0.0: **likely causes fixed; not confirmed** until the reviewer text is compared and the App Store Connect items are done. |

### Fixes made on 2026-11-22 that relate to these rejections

| Finding | Guideline | Change |
|---|---|---|
| CI-generated Info.plist declared `audio` background mode | 2.5.4 | Removed from `ios.yml`; new CI step fails the build if any background mode other than `remote-notification` appears, if a purpose string is missing, if an ATT key appears without ATT, or if the privacy manifest is missing. Committed `Info.plist` now states it is not the shipped file. |
| StoreKit 2 purchases rejected by the server (subscriptions never activated) | 2.1 / 3.1.1 | `worker/src/index.js` now verifies StoreKit 2 JWS transactions with the existing pinned-Apple-root verifier; new `worker/src/apple_jws_transaction.js` (+ tests). StoreKit 1 receipts still work for older installs. |
| Organizer Verification showed the web fee on iOS | 3.0 / 3.1.1 | Shows the App Store price; never falls back to the web price on iOS. |
| League creation / coupon checkout showed a web total on iOS | 3.0 / 3.1.1 | Owner decision: coupons are not used, so the coupon checkout is hidden in the store apps. (The price display added earlier showed the wrong product's price for the coupon checkout; corrected.) |
| League access guard showed a web "Entry fee" on iOS | 3.0 / 3.1.1 | Paid league access is not offered in the store apps (owner decision 2026-11-22); the guard passes straight through there. |
| "Pay to unlock" could never succeed on iOS; error mentioned web/Flutterwave | 2.1 / 3.1.1 / 3.1.3 | First fixed with a StoreKit consumable, then replaced the same day by the owner's decision not to sell league access in the store apps: on iOS/Android no unlock/pay sheet is shown and those leagues open free (`PaymentPlatformConfig.offerPaidLeagueAccess`). No message mentions other ways to pay. |
| Flutterwave keys compiled into the iOS binary | 3.1.1 (defence in depth) | Removed from the iOS build; any stray Flutterwave call on iOS fails closed. |

## Related risks that may remain

See `COMPLIANCE_MATRIX.md` for the full list. The ones most likely to cause
the next rejection if not handled:

1. **App Store Connect items** (cannot be done from the code): submit only
   purchasable IAPs with the build, fix the
   demo account, update review notes, answer the Digital Goods questionnaire
   and the new age-rating questions, check App Privacy answers include AdMob.
2. **Account deletion server function** (`delete-user-data`) is not in this
   repository; confirm it is deployed and deletes the user's posts, comments
   and messages (Apple requires shared UGC to be deleted).
3. **Purpose strings are English-only** although the app ships 12+
   languages (Apple says localized apps must localize them).
