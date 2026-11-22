# eSportlyic iOS — pre-submission checklist

Run this for **every** App Store submission, top to bottom. Do not submit
until every box is ticked or the exception is written down with a reason.
Record who ran it, the date, the version and the build number at the bottom.

Background: three consecutive rejections (Oct–Nov 2026) happened partly
because a fix was made in a file the build pipeline overwrites. The rule
behind several items below: **check the uploaded build, not the repository.**

## A. Refresh the rules (15 min)

- [ ] Check <https://developer.apple.com/news/> for items since the last
      submission; add relevant URLs to `docs/apple-compliance/tools/manifest-news.tsv`.
- [ ] Re-run the fetch script (see `docs/apple-compliance/README.md`) and
      `git diff --stat docs/apple-compliance` — if `app-review-guidelines.md`
      changed, read the diff and update `COMPLIANCE_MATRIX.md`.
- [ ] Check the "Future effective dates" table in `README.md` for anything now due
      (next: **2027-01-12** age-rating declarations for all apps; **April 2027**
      iOS 27 SDK minimum).
- [ ] Account Holder has accepted the latest Developer Program License Agreement
      and paid-apps agreements (App Store Connect → Business).

## B. Code and automated checks (repository)

- [ ] `flutter analyze` → 0 errors.
- [ ] `flutter test` → all pass.
- [ ] `node worker/src/apple_jws_transaction.test.js` → all pass.
- [ ] `cd web_client && npx tsc --noEmit` → clean; `npx tsx lib/moderation/objectionableContentFilter.test.ts` → pass.
- [ ] No other-platform wording reachable on iOS:
      `grep -rn "Android Settings\|Play Store\|Google Play" lib --include=*.dart`
      — every hit is behind an Android check or in a comment/debug log.
- [ ] No other ways to pay mentioned on iOS:
      `grep -rni "flutterwave\|on the web\|pay on our website" lib --include=*.dart`
      — every hit is in a web/Flutterwave-only branch, never iOS UI.
- [ ] No placeholder content: `grep -rni "coming soon\|_badge_soon" lib --include=*.dart` → none in UI.
- [ ] Any new background mode, entitlement or permission was added to
      **`.github/workflows/ios.yml`** (the shipped config), not only to `ios/Runner/*`,
      and to the guard allowlist with a reviewer-testable reason.

## C. The uploaded build (GitHub Actions → iOS CI run for this version)

- [ ] The run's "Validate generated Info.plist against App Store requirements"
      step passed and printed `background modes: remote-notification`.
- [ ] Download the IPA artifact, unzip, and confirm in `Payload/Runner.app/Info.plist`:
      `UIBackgroundModes` = `remote-notification` only; `ITSAppUsesNonExemptEncryption` = false;
      no `NSUserTrackingUsageDescription`; `CFBundleShortVersionString` = the version you are submitting.
- [ ] `PrivacyInfo.xcprivacy` is inside `Runner.app`.
- [ ] Build was made with the required SDK (iOS 26 SDK now; iOS 27 SDK from April 2027).
- [ ] The build installs from TestFlight on a real iPhone **and** an iPad (or the app is iPhone-only).

## D. Manual test pass on the TestFlight build (real device, sandbox Apple ID)

Use a fresh install. Tick each on iPhone; repeat starred items on iPad.

- [ ] First launch → sign up with email; Sign in with Apple; Google sign-in; sign out; sign in again.*
- [ ] Sign-in screen shows Terms/Privacy links and the zero-tolerance line; both links open.
- [ ] Forgot password e-mail arrives.
- [ ] Onboarding, profile edit, photo upload (photo permission prompt text correct).*
- [ ] Leagues: discover, create (free plan — rewarded ad shows or creation proceeds if none), add teams, fixtures, enter a result, standings update.*
- [ ] Messages inbox loads without error on a brand-new account (needs the Firestore index).
- [ ] Each chat: send text, image, voice note; a blocked word is refused with a message; report a message; block a user and their content disappears.
- [ ] Feed: post, edit, comment; a blocked word is refused; report a post.
- [ ] Voice room: create → only a **microphone** prompt (no camera), pre-permission button says "Continue"; leave → mic indicator turns off. Background the app during a call → the app does **not** keep audio running (expected; no background audio mode).
- [ ] QR scanner pre-permission button says "Continue".
- [ ] Push notification arrives with the app in the background.
- [ ] **Purchases (sandbox):** for every product attached to the submission —
  - [ ] the price shown in the app equals the price on Apple's payment sheet;
  - [ ] purchase succeeds and the feature unlocks (plans: Active plan shows Pro/Elite within seconds — this exercises the worker's StoreKit 2 verification);
  - [ ] "Restore Purchases" on a second device / after reinstall restores the subscription;
  - [ ] cancelling the payment sheet leaves the app usable with a clear message.
- [ ] Paid league: "Unlock access" → "Pay to unlock" completes via the App Store.
- [ ] No screen shows a price in a currency/amount different from the App Store sheet.
- [ ] Account deletion with an account signed in **more than 10 minutes ago**, for each of: email/password, Apple, Google — identity prompt appears first, deletion completes, app returns to sign-in. Subscribed account shows the billing notice and "Manage subscriptions" link.
- [ ] Turn on Airplane Mode: screens show offline/error states, nothing crashes, recovery works when back online.
- [ ] Change the device language to one other non-English locale and spot-check the main screens.

## E. App Store Connect

- [ ] App Review Information: demo account signs in on a clean device; it is on the
      free plan; notes updated from `APP_REVIEW_NOTES_TEMPLATE.md`; contact details current.
- [ ] Only products that can be bought in this build are attached to the version;
      each has a review screenshot and description. Currently **not** purchasable:
      `premium_subscription`, `league_addons_pack`.
- [ ] Product names, durations and prices in ASC match what the app displays.
- [ ] Subscription group, localizations, and (if used) introductory offers match the app's wording.
- [ ] Multiseat (group/volume) purchasing for subscriptions: disabled unless deliberately supported.
- [ ] App Store Server Notifications V2 URL points to the worker's notifications route (production and sandbox).
- [ ] App Privacy answers match the app **and** its SDKs (Firebase, Crashlytics, AdMob, LiveKit, Cloudinary, Supabase); AdMob data listed for third-party advertising, "not used to track".
- [ ] Age rating questionnaire fully answered, including social media capabilities (Yes),
      messaging/UGC (Yes), Shared Location (No), Dating (No), in-app controls.
- [ ] Digital Goods and Services questionnaire (App Information), if shown: Apple In-App Purchase only.
- [ ] Age rating: Shared Location and Dating answered (No / No) even if the banner says they can wait.
- [ ] The version number in App Store Connect equals the build's `CFBundleShortVersionString` (the version can be edited while it is Rejected). Never press "Update Review" / resubmit with an old build — attach the new one first.
- [ ] If China mainland is selected in Pricing and Availability: App Compliance declarations (AI-Generated or Synthetic Content; Security Assessment) completed — due for existing apps by 2027-01-31.
- [ ] From April 2027: iPhone Duo screenshots uploaded.
- [ ] Export compliance answered consistently with `ITSAppUsesNonExemptEncryption = false`.
- [ ] Screenshots and previews show the current iOS UI only (no Android UI, no removed features).
- [ ] Description, subtitle, keywords describe only shipped features; Terms of Use (EULA) link included for subscriptions.
- [ ] Privacy Policy URL and Support URL open.
- [ ] Territory availability reviewed against `README.md` "Territory-specific requirements" (EU trader status, Australia, Texas/Utah/Louisiana, Brazil, China mainland).

## F. Backend and console prerequisites

- [ ] Worker deployed from `main` after the last change to `worker/**` (Deploy Worker workflow green).
- [ ] Firestore indexes (especially `private_threads` participantIds + lastMessageAtMs) exist in production.
- [ ] Supabase `delete-user-data` function deployed; its source is in the repository; it deletes posts, comments, messages and media.
- [ ] Firebase Auth → Apple provider configured with Services ID, Team ID, Key ID and private key (needed to revoke Sign in with Apple tokens on deletion).

## G. After a rejection

- [ ] Copy the full reviewer message into `docs/apple-compliance/REJECTION_HISTORY.md` the same day.
- [ ] Find the root cause in the **shipped build**, not only in the repository.
- [ ] Add a check to this list that would have caught it.

---

| Run by | Date | Version | Build | Exceptions |
|---|---|---|---|---|
| | | | | |
