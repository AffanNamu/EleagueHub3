# Draft "Notes for Review" for App Store Connect

Paste into **App Store Connect → your app → the version → App Review
Information → Notes** after filling in the bracketed parts. Guideline 3.0's
preamble says: *"If your business model isn't obvious, make sure to explain in
its metadata and App Review notes."* Keep the notes factual — every statement
below was checked against the code on 2026-11-22; re-check anything you change.

Also see `app-review-submission/complete-review.md` and
`app-review-submission/configure-in-app-purchases-for-review.md` in this library.

---

```
eSportlyic is a football/esports league management app: organizers create
leagues and tournaments, run fixtures and results, and players and fans
follow competitions, chat and talk in voice rooms.

DEMO ACCOUNT
Email: [demo email]      Password: [demo password]
This account is a regular organizer on the free Basic plan with sample
leagues so every purchase below can be tested. It has no active subscription.
It is already approved for Global Chat (which otherwise requires approval)
and has existing private messages, league chat and Global Chat messages, so
every chat screen shows content.

HOW PEOPLE PAY (all digital purchases on iOS use Apple In-App Purchase)
1. Organizer plans — auto-renewable subscriptions (one subscription group):
   Pro  (5 master leagues, up to 9 competitions each)
   Elite (unlimited master leagues and competitions)
   Each in 1-month, 3-month, 6-month and 12-month durations.
   Where: Leagues tab → "Upgrade plan" (or "View plans"). The screen shows the
   App Store price, duration, auto-renewal terms, Terms of Service and Privacy
   Policy links, and a "Restore Purchases" button.
   Free Basic plan: 1 master league, up to 3 competitions.
2. Organizer Verification — one-time purchase (consumable
   "organizer_verification_fee", $149.99 USD — this price is intended) that
   submits an organizer's verification application for manual review by our
   team; if approved, the organizer receives a verified badge. A renewal
   review is a separate one-time purchase ("organizer_verification_renewal_fee").
   It is not a subscription.
   Where: Settings → Organizer verification (also from an organizer
   profile) → complete the form → review step → Submit and pay.
These are the only purchases in the iOS app. All leagues are free to view
and join; there is no paid league access and there are no coupons.

Purchases made on our website are honoured in the app (multiplatform), and
every such item is also available in the app through In-App Purchase.
The app does not link to or mention any other way to pay.

ADS
Free-plan organizers watch a short rewarded video ad (AdMob) before creating
a league; paid plans skip it, and if no ad is available the league is created
anyway. On iOS ads are requested as non-personalized and the app does not
track users (no App Tracking Transparency prompt).

USER-GENERATED CONTENT (Guideline 1.2)
- Objectionable language is blocked before posts, comments, chat messages
  and discussions are published.
- Messages (select a message in any chat), comments, posts and profiles can
  be reported. Reports go to our moderation queue and are reviewed within
  [24] hours.
- Users can block other users; blocked users' content is hidden everywhere.
- Users agree to our Terms (zero tolerance for objectionable content and
  abusive users) when signing in.
- Contact: Profile → Contact (in-app support address
  NASSARACORETECHVENTURES@GMAIL.COM — must match the Support URL/email in
  App Store Connect).

BACKGROUND MODES (Guideline 2.5.4)
The app declares only "remote-notification" for push notifications (chat and
league updates). It does not declare background audio: voice rooms run only
while the app is open.

ACCOUNT DELETION (Guideline 5.1.1(v))
Settings → Delete Account. The user confirms their identity, then the account
and its data are deleted. Subscribers are told that Apple billing continues
until they cancel, with a link to manage subscriptions.

MARKETPLACE
The Marketplace lists physical football merchandise via affiliate links to
third-party stores (physical goods, Guideline 3.1.3(e)).
```

---

### Before pasting, confirm

- [ ] The demo account signs in on a clean device and is **not** already subscribed.
- [ ] The demo account is approved for Global Chat and has existing private, league and Global Chat messages (Apple asked for "pre-populated content … such as chats").
- [ ] Every product named above exists in App Store Connect, is "Ready to Submit", has a review screenshot and is attached to this version.
- [ ] Only the Pro/Elite subscriptions and the consumables `organizer_verification_fee` and `organizer_verification_renewal_fee` are attached. The yearly subscription `organizer_verification` (Organizer Verification subscription group) is **not** attached. `league_access_unlock`, `league_creation_unlock`, `league_addons_pack`, `premium_subscription` are **not** attached (no purchase path on iOS).
- [ ] The report-response time you state is one you can meet.
- [ ] Remove any product line you are not selling on iOS.
