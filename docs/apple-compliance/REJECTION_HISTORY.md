# eSportlyic — App Review rejection history

Bundle ID `com.eleaguehub.app`. Builds are produced by `.github/workflows/ios.yml`,
which sets `CFBundleVersion` to the GitHub Actions run number (so App Store
Connect build numbers do not match the `+NN` in `pubspec.yaml`).

## What this file is based on

* **The exact reviewer messages are not stored anywhere in this repository**
  and were not available to the audit (2026-11-22). Rows below are
  reconstructed from (a) the rejection summary provided by the product owner
  and (b) commit messages written while each rejection was being fixed. Where
  the reviewer's wording is unknown it says so — nothing here is invented.
* **Action for the product owner:** paste the full text of every App Review
  message (Resolution Center), especially the **November 20, 2026** 3.0.0
  message and the 2.1.0 message from the 1.9.20 review, into the
  "Exact reviewer explanation" rows below. The 3.0.0 root cause in particular
  cannot be confirmed without it.

## Summary

| Version | Build | Guideline(s) cited | Status after this audit |
|---|---|---|---|
| 1.9.19 | (CI run #, unknown) | 2.5.4, 5.1.1(iv), 2.1(a) | 5.1.1(iv) fixed Oct 21. 2.1(a) needs App Store Connect action. **2.5.4 fix never shipped** (see below) — now fixed |
| 1.9.20 | (CI run #, unknown) | 2.1.0, 2.5.4 | 2.5.4 root cause found and fixed. 2.1.0: several candidate causes fixed; reviewer text needed to confirm |
| 1.9.21 | 222 | 2.5.4, 3.0.0 | 2.5.4 fixed. 3.0.0: likely causes fixed; reviewer text needed to confirm |

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
