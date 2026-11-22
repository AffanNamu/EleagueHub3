# eSportlyic — Apple compliance matrix

Audit date **2026-11-22**, against the App Review Guidelines **last updated
2026-10-16** (`app-review-guidelines/app-review-guidelines.md`, official URL
<https://developer.apple.com/app-store/review/guidelines/>) and the other
documents in this library. Code references are to this repository after the
2026-11-22 changes.

**Status:** Pass · Fixed (was failing, corrected 2026-11-22) · Partial · Fail ·
Unknown (needs App Store Connect, a Mac/device, or information not available)
· N/A.
**Class:** CV = confirmed violation · LV = likely violation · PR = potential
risk · NA = not applicable · CBV = cannot be verified here.
**Risk** is the risk of rejection *if the required action is not taken*.

"ASC" = App Store Connect. "Source" paths are relative to `docs/apple-compliance/`.

---

## 1. Safety

| Guideline | Requirement | Source | Application area | Status / Class | Evidence | Risk | Required action | Verification |
|---|---|---|---|---|---|---|---|---|
| 1.1 Objectionable content | No offensive, insensitive or upsetting first-party content | app-review-guidelines.md §1.1 | Whole app | Pass / NA | Sports league content only; no first-party objectionable content found | Low | — | Reviewer walkthrough |
| 1.2 UGC — filtering | "A method for filtering objectionable material from being posted" | §1.2; news-2026-10-16-ncii-and-bait-and-switch.md | Feed posts, edits, comments, all 4 chats, discussions (iOS + web) | **Fixed** / was CV | `lib/core/moderation/objectionable_content_filter.dart` applied in every publishing repository method + chat screens; web mirror `web_client/lib/moderation/objectionableContentFilter.ts`; tests `test/objectionable_content_filter_test.dart` (31), `objectionableContentFilter.test.ts` | High → Low | Keep list current; review reports | Unit tests; manual: post a blocked word on iOS → blocked with message |
| 1.2 UGC — reporting | Mechanism to report offensive content, timely responses | §1.2 | Profiles, messages, posts, comments | Pass (mechanism) / Unknown (response time) | `lib/features/moderation/presentation/report_sheet.dart`; admin queue in `esportlyic-admin` (commit `3c742885`) | Medium | Commit to a response time (e.g. 24 h) and state it in review notes and Terms | Report a post on TestFlight → appears in admin queue |
| 1.2 UGC — blocking | Ability to block abusive users | §1.2 | Profiles; blocked users hidden in chats/feed | Pass | `TeamProfileRepository.fetchBlockedEitherWayUserIds` wired into chats/feed (`3c742885`) | Low | — | Block a user → their content disappears |
| 1.2 UGC — contact info | Published contact information | §1.2 | Profile → Contact | Pass | `lib/features/legal/contact_screen.dart` (support e-mail), linked from `profile_screen.dart`; public route `/contact_screen` | Low | Ensure Support URL in ASC also works | Open Contact screen |
| 1.2 UGC — terms | Users must be bound by terms with no tolerance for objectionable content (App Review's standard request) | §1.2 | Sign-in screen, Terms | **Fixed** / was PR | Sign-in screen now shows "By continuing, you agree to our Terms of Service and Privacy Policy. There is no tolerance for objectionable content or abusive users." with links; Terms §4 gained the zero-tolerance clause (`terms_s4_b7`) | Medium → Low | Translate new strings (English fallback today) | Visual check on login |
| 1.2 NCII / image moderation | Prevent and remove nonconsensual intimate imagery | §1.2; news-2026-10-16-ncii-and-bait-and-switch.md | Image/video uploads (feed, chats, highlights) | Partial / PR | Text filter does not inspect images; images rely on report + admin removal | Medium | Decide on image moderation (e.g. Cloudinary moderation or manual review of reported media within a stated time) | Policy decision |
| 1.2 random/anonymous chat | Random/anonymous chat not allowed | §1.2; news-2026-02-06 | Global chat | Pass / NA | Chats are between identified accounts with profiles; no random pairing | Low | — | — |
| 1.2.1(a) Creator content age gating | Creator apps need age-based restriction for content above the rating | §1.2.1; news-2025-11-13 | Highlights/feed | Likely N/A / PR | App is not a creator-monetization platform | Low | Re-assess if creator payouts are added | — |
| 1.4–1.7 | Physical harm, developer info, data security, criminal activity | §1.4–1.7 | — | 1.5 Unknown (ASC); 1.6 Partial | 1.6: `users/{uid}/leagueCharges/*` can be written by the user directly (see §3 row "Entitlement integrity") | Low | Fix entitlement integrity server-side (not an App Review blocker) | Security review |

## 2. Performance

| Guideline | Requirement | Source | Application area | Status / Class | Evidence | Risk | Required action | Verification |
|---|---|---|---|---|---|---|---|---|
| 2.1(a) Completeness — demo account | Working demo account or demo mode for review | §2.1; app-review-submission/complete-review.md | ASC App Review Information | Unknown / CV in round 1 | Cited in round 1 (`c6b41e1f`); ASC-only | **High** | Provide a working demo account with Pro/Elite **not** pre-purchased, plus organizer data, in ASC | Sign in with it on a clean device |
| 2.1(a) Completeness — placeholders | No placeholder or "coming soon" content | §2.1 | Community screen | **Fixed** / was LV | Removed "Guides — Soon" row that only showed "coming soon" (`community_screen.dart`) | Medium → Low | — | Visual check |
| 2.1(a) Completeness — broken flows | Features must work | §2.1 | Paid league access on iOS | **Fixed** / was CV | "Pay to unlock" always failed on iOS. Owner decision (2026-11-22): paid league access is not sold in the store apps. `PaymentPlatformConfig.offerPaidLeagueAccess` is false on iOS/Android, so no unlock/pay sheet is shown and those leagues open free; web unchanged | Low | None (no `league_access_unlock` product needed) | Join a Champions-League-format league by code on device: no payment sheet |
| 2.1(a) Completeness — crashes | No crashes or obvious bugs | §2.1 | Call room, images, Football Hub | Partial | Crashlytics fixes 2026-11-14 (`d0bb5a17`); Messages inbox needs Firestore index created manually (`92ebcc2c`) | Medium | **Create the `private_threads` composite index in Firebase console**; run full device test | Open Messages on fresh account |
| 2.1(b) IAP completeness | IAPs must be complete, visible to reviewer, functional | §2.1(b); app-review-submission/configure-in-app-purchases-for-review.md | All products | **Fixed** (code) / Unknown (ASC) / was CV | StoreKit 2 activation failure fixed in worker (`apple_jws_transaction.js`); unreachable products identified | **High** | Submit only purchasable products (see AUDIT_REPORT §5); do **not** attach `premium_subscription` or `league_addons_pack` | Sandbox purchase of each submitted product; worker log shows activation |
| 2.2 Beta testing | No beta/trial/demo labelling in production | §2.2 | Strings | Pass | No "beta" UI strings found | Low | — | — |
| 2.3.1 / 2.5.19 Accurate metadata, no hidden features | Metadata matches the app; no hidden/dormant/undocumented features | §2.3.1, §2.5.19 (new 2026-10-16) | Metadata; payment code | Partial / PR | Flutterwave code is present but unreachable on iOS (routing is compile-time, not remote); Flutterwave keys now excluded from the iOS build | Low | Keep metadata limited to shipped features | Compare screenshots/description to build |
| 2.3.3 Screenshots | Show the app in use; accurate | guideline-ref-2-3-3-screenshots.md | ASC | Unknown / CBV | ASC-only | Medium | Re-check screenshots match the current UI (no Android UI, no removed "Guides") | Visual review in ASC |
| 2.3.7 / 2.3.8 Name, keywords, age-appropriate metadata | Accurate name/subtitle/keywords | §2.3.7–2.3.8 | ASC | Unknown / CBV | ASC-only | Low | Review | — |
| 2.3.10 Other platforms | No names/imagery of other mobile platforms in the app | §2.3.10 | Call room, purchase errors | **Fixed** / was LV | "Android Settings" (call room) and "Play Store" (purchase error) made neutral; remaining Google Play strings are Android-gated (verified call sites) | Medium → Low | Keep Android copy behind platform checks | Manual pass of iOS screens |
| 2.3.12 What's New | Describe changes | §2.3.12 | ASC | Unknown | — | Low | Write release notes | — |
| 2.4.1 iPad | iPhone apps should run on iPad | §2.4.1; app-review-submission/test-compatible-devices.md | Whole app | Unknown / CBV | `flutter create` default device family (iPhone + iPad); plist declares iPad orientations; no iPad testing done | Medium | Test on an iPad simulator/device, or restrict to iPhone (`TARGETED_DEVICE_FAMILY=1`) | iPad walkthrough |
| 2.5.1 Public APIs | Only public APIs | §2.5.1 | Native code | Pass / CBV | No private API usage found in Swift sources; binary not scanned | Low | — | Xcode archive validation |
| 2.5.2 Self-contained bundle | No downloaded executable code | §2.5.2 | Whole app | Pass | No code-push or interpreters | Low | — | — |
| **2.5.4 Background modes** | Background services only for intended purposes | §2.5.4; permissions-and-background-modes/uibackgroundmodes.md | `UIBackgroundModes` | **Fixed** / was CV (rejected ×3) | `audio` removed from the CI-generated Info.plist (the shipped one); CI guard step fails the build on any mode other than `remote-notification` | **Critical → Low** | Confirm on the uploaded build's Info.plist | `ios.yml` guard output; inspect IPA `Info.plist` |
| 2.5.4 `remote-notification` | Justified use | uibackgroundmodes.md; pushing-background-updates-to-your-app.md | FCM push (chat, league notifications) | Pass | `firebase_messaging` + `registerForRemoteNotifications()` in AppDelegate | Low | — | Receive a push with app backgrounded |
| 2.5.5 IPv6 | Works on IPv6-only networks | §2.5.5 | Networking | Pass / CBV | All endpoints are hostnames (Firebase, Cloudflare, LiveKit, Cloudinary); the only IPv4 literal is LAN broadcast in unreachable legacy code | Low | — | NAT64 test on a Mac |
| 2.5.6 WebKit | Web browsing via WebKit | §2.5.6 | WebViews | Pass | `webview_flutter_wkwebview` | Low | — | — |
| 2.5.14 Recording consent | Explicit consent and indication when recording | §2.5.14 | Voice messages, voice rooms | Pass | Recording only on explicit user action, visible recording UI; mic permission requested at use | Low | — | — |
| 2.5.18 Ads | Ads in main binary, age-appropriate, closable | §2.5.18 | AdMob rewarded (iOS); banner not requested on iOS | Pass / PR | `ad_config.dart`; iOS requests now explicitly non-personalized | Low | Ensure ad content rating ≤ app age rating in AdMob | — |

## 3. Business

| Guideline | Requirement | Source | Application area | Status / Class | Evidence | Risk | Required action | Verification |
|---|---|---|---|---|---|---|---|---|
| **3.0 Preamble** | Business model and IAPs obvious; explain in metadata and review notes; no irrationally high prices | §3 preamble; app-store-connect/business-models.md | All paid features | **Partial** / was LV (rejected 2026-11-20) | Price/charge mismatches fixed (Organizer Verification, league creation/coupon checkout, league access guard); steering text removed; StoreKit 2 activation fixed | **High** | Paste reviewer text; add business-model explanation to review notes (template provided); confirm prices in ASC are reasonable | Reviewer text vs. fixes; sandbox walkthrough |
| 3.1.1 IAP for digital goods | Unlocking features/content must use IAP | §3.1.1; in-app-purchases/* | Subscriptions, Organizer Verification, league creation | **Fixed / Pass** | All iOS purchase paths route to StoreKit (`PaymentPlatformConfig.routeIOSPaymentsToStoreKit` is compile-time, unconditional); paid league access is not offered in the store apps | Medium (until ASC products exist) | Create/submit products in ASC | Sandbox purchase each |
| 3.1.1 Restore | Restore mechanism for restorable purchases | §3.1.1 | Upgrade plan screen | Pass | "Restore Purchases" button → `GooglePlayBillingService.restorePurchases()` + app-level reconcile listener | Low | — | Sandbox: buy, reinstall, restore |
| 3.1.1 Codes / own unlock mechanisms | No license keys/QR codes/own mechanisms to unlock content; vouchers sold in app must use IAP | §3.1.1 | League coupons | Partial / PR | Coupons are purchased by organizers (StoreKit on iOS) and redeemed by participants; web-purchased coupons redeemed on iOS rely on 3.1.3(b) since access is now also sold via IAP; partial-balance coupons blocked on iOS | Medium | Explain coupons in review notes; consider Apple Offer Codes long-term | Reviewer walkthrough |
| 3.1.1 Coupon pack pricing | Price must match what is delivered | §3.0 / §3.1.1 | Coupon purchase checkout | Partial / PR (business) | iOS charges the fixed `league_creation_unlock` price regardless of coupon count (same on Android Play builds); screen now shows that App Store price | Medium | **Business decision:** fixed-size coupon packs as distinct products, or hide coupon quantity on native stores | — |
| 3.1.2 Subscriptions — value & terms | Ongoing value; clear title, length, price, auto-renew terms, Terms/Privacy links on purchase screen | §3.1.2; subscriptions/auto-renewable-subscriptions-guide.md; hig-in-app-purchase.md | Upgrade plan screen | Pass / Unknown (ASC) | Disclosures added `a073ae0d` (title, duration, price from StoreKit, auto-renew text, Terms/Privacy links) | Medium | Ensure ASC subscription names, durations, localizations and the EULA/Terms URL in the app description match | Visual + ASC review |
| 3.1.2 Cancellation | Users told how to cancel / manage | §3.1.2; 5-1-1-account-deletion.md | Deletion flow | Partial | "Manage subscriptions" link added to account deletion; not yet on the upgrade screen | Low | Add a Manage Subscriptions link to the upgrade screen | — |
| 3.1.2 Organizer Verification product type | Time-limited access should match IAP type | in-app-purchases/in-app-purchase-types.md | `organizer_verification(_renewal)` consumables | Partial / PR | Sold as consumables although verification lasts a period | Low–Medium | Consider Non-Renewing Subscription type (requires ASC + code change) | — |
| 3.1.3(b) Multiplatform | Content bought elsewhere may be accessed if also available via IAP | §3.1.3(b) | Web (Flutterwave) purchases used on iOS | Pass | Web-only paid league access is not required on iOS (those leagues open free there); other web-purchasable items are also sold via StoreKit | Low | — | — |
| 3.1.3 Anti-steering | No buttons/links/calls to action to other purchase methods (outside permitted entitlements) | §3.1.1(a), §3.1.3 | Payment errors | **Fixed** / was LV | Removed "Web continues to use Flutterwave" messages (`payment_platform_config.dart`); no external purchase links found | Medium → Low | — | grep check in checklist |
| 3.1.3(e) Physical goods | Physical goods may use other payment | §3.1.3(e) | Marketplace | Pass | Marketplace opens third-party store affiliate links for physical goods (`product_details_screen.dart`) | Low | Ensure no digital goods are sold via affiliate links | — |
| 3.2.2(x) Incentives | Don't force store actions; may incentivize watching ads | §3.2.2 | Rewarded ad gate (league creation) | Pass | Current text explicitly allows incentivizing watching an ad | Low | — | — |
| Entitlement integrity (DPLA/security, not a guideline) | Paid features only with valid entitlement | — | `users/{uid}/leagueCharges/*` | **Fail** / security | `firestore.rules` lets a signed-in user create their own leagueCharges receipt doc | Medium (revenue) | Move receipt writes to the worker after verification, then tighten the rule | Rules test |

## 4. Design

| Guideline | Requirement | Source | Application area | Status / Class | Evidence | Risk | Required action | Verification |
|---|---|---|---|---|---|---|---|---|
| 4.1 Copycats | Original app; no other developers' brands | guideline-ref-4-1-prevent-copycat-rejection.md | Football Hub (real club/league names) | Pass / PR | Uses real-world data via API; no other app's branding | Low | Ensure icon/name don't imitate others | — |
| 4.2 Minimum functionality | More than a repackaged website | §4.2 | Whole app | Pass | Native leagues, chats, calls, StoreKit | Low | — | — |
| 4.8 Login services | If third-party login, offer an equivalent privacy login | §4.8; hig-sign-in-with-apple.md | Login screen | Pass | Google + Sign in with Apple on iOS (`login_screen.dart`) | Low | — | Sign in with Apple on device |
| 4.5.4 Push | Push not required; no marketing push without consent | §4.5.4 | FCM | Pass / Unknown | Notifications are functional (chat, leagues) | Low | Keep marketing push opt-in | — |

## 5. Legal

| Guideline | Requirement | Source | Application area | Status / Class | Evidence | Risk | Required action | Verification |
|---|---|---|---|---|---|---|---|---|
| 5.1.1(i) Privacy policy | Policy linked in ASC and in app | §5.1.1(i) | Settings, sign-in, upgrade screen | Pass / Unknown (ASC URL) | `privacy_policy_screen.dart`; linked from sign-in and purchase screen | Low | Confirm ASC Privacy Policy URL resolves | — |
| 5.1.1(ii) Purpose strings | Clear purpose strings; **localized** if the app is localized | guideline-ref-5-1-1-purpose-strings.md | Info.plist | Partial / PR | Strings are specific, but English-only while the app ships 12 locales | Medium | Add `InfoPlist.strings` per locale (needs Xcode variant-group wiring in `ios.yml`) | Change device language; trigger each prompt |
| 5.1.1(iii) Data minimization | Request only necessary access | §5.1.1(iii) | Voice room | **Fixed** / was PR | Voice room no longer requests camera (`call_room_screen.dart`) | Low | — | Create voice room → only mic prompt |
| 5.1.1(iv) Access / pre-permission wording | Don't manipulate consent; neutral wording | §5.1.1(iv) | QR scanner (fixed Oct), voice room | **Fixed** / was LV | Voice-room pre-permission button "Allow" → "Continue" | Low | — | Visual |
| 5.1.1(v) Account deletion — in app | Initiate deletion in app | 5-1-1-account-deletion.md | Settings → Delete account | Pass | `delete_account_flow.dart` | Low | — | — |
| 5.1.1(v) Account deletion — works for old sessions | Not unnecessarily difficult | 5-1-1-account-deletion.md | Deletion flow | **Fixed** / was LV | Re-authentication now happens first (Apple/Google/password) — previously destructive steps ran then failed with "sign in again" and no way to do so | High → Low | — | Delete an account signed in >5 min ago (each provider) |
| 5.1.1(v) Revoke Sign in with Apple tokens | Use SIWA REST API to revoke tokens | 5-1-1-account-deletion.md; siwa-rest-revoke-tokens.md | Deletion flow | **Fixed** (code) / Unknown (config) | `revokeTokenWithAuthorizationCode` after Apple re-auth | Medium | **Confirm Firebase → Auth → Apple provider has Services ID, Team ID, Key ID and private key configured** (required for revocation) | Delete an Apple account; check Apple ID → Sign in with Apple no longer lists the app |
| 5.1.1(v) Subscribers notice | Tell subscribers billing continues; link to manage | 5-1-1-account-deletion.md | Deletion warning (iOS) | **Fixed** / was LV | Notice + "Manage subscriptions" → `apps.apple.com/account/subscriptions` | Low | — | Visual |
| 5.1.1(v) Delete associated data incl. shared UGC | Delete account and its data, including posts/photos shared with others | 5-1-1-account-deletion.md | Supabase `delete-user-data` | **Unknown** / CBV | Client calls `delete-user-data`, but the function is **not in this repository**; client continues even if it fails | **High** | Confirm the function is deployed; commit its source; make it delete posts, comments, messages, media; tell users what is retained (e.g. league results) | Delete test account → verify Firestore/Storage |
| 5.1.2 Data use / ATT | No tracking without ATT; labels accurate | §5.1.2; user-privacy-and-data-use.md; app-privacy-details.md | AdMob, Firebase | Partial / PR | No ATT prompt; `NSPrivacyTracking=false`; iOS ad requests now explicitly non-personalized. App-level manifest does not list AdMob data (AdMob ships its own manifest) | Medium | **ASC App Privacy must include AdMob-collected data (e.g. Device ID, Product Interaction, Advertising Data, Coarse Location) for "Third-Party Advertising", not used for tracking** | Compare ASC answers to Google's AdMob disclosure guide |
| 5.1.2(i) Third-party AI sharing | Disclose and get consent before sharing personal data with third-party AI | news-2025-11-13 | — | N/A | No third-party AI providers found in app, worker or web | Low | Re-assess if AI is added | — |
| Privacy manifest / required-reason APIs | App + SDK manifests; reasons declared | privacy-manifest-files.md; describing-use-of-required-reason-api.md; third-party-sdk-requirements.md | `PrivacyInfo.xcprivacy` (CI-written) | Pass / CBV | UserDefaults `CA92.1`, FileTimestamp `C617.1`; SDKs ship their own manifests | Low | Run Xcode "Generate Privacy Report" on an archive | Privacy report |
| 5.1.4 Kids | N/A unless Kids category | §5.1.4 | — | N/A | Not in Kids category | Low | Don't choose Kids category | — |
| 5.2 IP | Rights to content | §5.2 | Football Hub data, logos | Pass / PR | Third-party football data via licensed API; club badges displayed | Low | Confirm API licence covers logo display | — |
| 5.3 Gaming/contests | Official rules if sweepstakes/contests with prizes | §5.3 | Tournaments | N/A | No prize, cash, winnings or payout features found in app strings or code | Low | Re-assess if prizes are ever added (official rules; Apple not a sponsor) | — |

## Age rating and territory (App Store Connect — not code)

| Item | Requirement | Source | Answer for eSportlyic (based on code audit) | Status |
|---|---|---|---|---|
| Social media capabilities | Required since Sept 2026 | news-2026-07-09-age-rating-social-media-questions.md | **Yes** — public feed, follows, comments, discovery | Unknown (ASC) |
| Messaging / user-generated content | Age-rating capabilities questions | age-ratings-values-and-definitions.md | **Yes** — private, league, organizer and global chat; voice rooms; UGC | Unknown (ASC) |
| Shared Location | Required on updates since 2026-11-16 (ASC banner on this app, 2026-11-22: not required until 2027-01-15 unless other answers in the section change) | news-2026-11-02-new-age-rating-content-descriptors.md; ASC banner | **No** — no location features or location plugins. Answer now. | Unknown (ASC) |
| Dating and Relationships | Required on updates since 2026-11-16 | same | **No** | Unknown (ASC) |
| In-app controls (blocking, reporting, filtering) | Questionnaire | news-2025-07-24-updated-age-ratings.md | Blocking/reporting: Yes; content filtering: Yes (from this release) | Unknown (ASC) |
| Digital Goods and Services questionnaire | Indicate payment methods per region | digital-goods-and-services-questionnaire.md | iOS uses **Apple In-App Purchase exclusively** for digital goods | Unknown (ASC) |
| Australia under-16 social media law | Law, not a guideline | news-2025-12-08-australia-social-media-apps.md | Legal determination required | Unknown |
| EU trader status | Required for EU distribution | eu-dsa-trader-requirements.md | — | Unknown (ASC) |
| China mainland: AI-Generated or Synthetic Content declaration | Existing apps by 2027-01-31 (ASC banner seen 2026-11-22) | china-mainland-compliance-information.md | **No** — no AI chat, image/video generation or voice/face alteration in the code | Unknown (ASC; only if distributed in China mainland) |
| China mainland: Security Assessment declaration | Existing apps by 2027-01-31 (ASC banner seen 2026-11-22) | china-mainland-compliance-information.md | **No** — no AI-generated content distribution and no end-to-end encrypted instant messaging (chats are stored in Firestore). Consider whether to distribute in China mainland at all: Firebase, Google Sign-In and AdMob are generally not reachable there | Unknown (ASC; only if distributed in China mainland) |
| iPhone Duo screenshots | Required for all submissions from April 2027 | developer-news-index.md | Not yet required | Future |
