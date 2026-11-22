<!--
Source: https://developer.apple.com/news/?id=j9zukcr6
Final URL: https://developer.apple.com/news/?id=j9zukcr6
Retrieved (UTC): 2026-11-22T04:12:29Z
Raw file: news-2025-10-09-siwa-account-creation-requirement.html
SHA-256 of raw: 1dae2dedc87d62f029d91ad45277b42b95741867255c52ff6da6933a7027d2f1
Extraction: automated text extraction for offline search; the raw file is authoritative.
-->

![New requirement for apps using Sign in with Apple for account creation](/assets/elements/icons/sign-in-with-apple-dark/sign-in-with-apple-dark-256x256_2x.png)

## New requirement for apps using Sign in with Apple for account creation

October 9, 2025

Starting January 1, 2026, developers based in the Republic of Korea must provide a [server‑to‑server notification endpoint](https://developer.apple.com/help/account/capabilities/enabling-server-to-server-notifications) when registering a new Services ID, or updating an existing Services ID, to [associate their website](https://developer.apple.com/help/account/capabilities/configure-sign-in-with-apple-for-the-web) with an app using [Sign in with Apple](https://developer.apple.com/design/human-interface-guidelines/sign-in-with-apple).

As a reminder, registering a notification endpoint allows Apple to send you important updates about the people who use your app and their account status, including:

- Changes in email forwarding preferences.
- Account deletions in your app.
- Permanent Apple Account deletions.

To learn more about server-to-server notifications, see [WWDC20 session 10173: Get the most out of Sign in with Apple](https://developer.apple.com/videos/play/wwdc2020/10173/).

When you receive these notifications, you should immediately update any data associated with the account change in the app, as well as any necessary server infrastructure, to give people more control of the personal data they’ve shared. For more information, see [Processing changes for Sign in with Apple accounts](https://developer.apple.com/documentation/signinwithapple/processing-changes-for-sign-in-with-apple-accounts).

Before submitting a new app to the App Store, or updating an existing app configuration to register a new Services ID or modify an existing Services ID, please read the guidance below.

### Account change guidance

Account changes are directly related to privacy and control for the user and their personal data, and confirming account changes should be straightforward and transparent.

**For account email forwarding changes:**

- Ensure any displayed user data affected by the account change matches the change event in the notification payload. Typically, this data is displayed in the app’s account settings or user profile.
- If people need to visit a website to finish changing or verifying their email address, include a link directly to the page on your website where they can complete the process.
- Keep users informed. If the email forwarding change affects other services you offer, let them know. If your app supports In-App Purchases, help people understand how billing, order tracking, and cancellations will be handled with the new email address.

**For account deletions:**

- See [TN3194: Handling account deletions and revoking tokens for Sign in with Apple](https://developer.apple.com/documentation/technotes/tn3194-handling-account-deletions-and-revoking-tokens-for-sign-in-with-apple).

**Note:** Always follow applicable legal requirements for storing and retaining user account information and for handling account changes and deletions. This includes complying with local laws where your apps are available. If you have questions regarding your legal obligations, check with your legal counsel.

### Resources

- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Human Interface Guidelines: Managing accounts](https://developer.apple.com/design/human-interface-guidelines/managing-accounts)

- 
- 
- 
- 
