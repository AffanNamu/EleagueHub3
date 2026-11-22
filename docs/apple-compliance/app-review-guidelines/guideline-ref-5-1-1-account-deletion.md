<!--
Source: https://developer.apple.com/help/app-review/guideline-reference/5-1-1-account-deletion
Final URL: https://developer.apple.com/help/app-review/guideline-reference/5-1-1-account-deletion
Retrieved (UTC): 2026-11-22T04:11:57Z
Raw file: guideline-ref-5-1-1-account-deletion.html
SHA-256 of raw: 2e8b45a9aef317882cd19ece9f08a91734ceec3db985994393d34fedb29a5cc6
Extraction: automated text extraction for offline search; the raw file is authoritative.
-->

[](/help/app-review/)

### App Review Help

[App Review](/help/app-review/) / Guideline reference / 5.1.1(v) - Offering account deletion in your app

Filter ⌘K

Filter ⌘K

Guideline reference

# 5.1.1(v) - Offering account deletion in your app

Apps submitted to the App Store that support account creation must also let people initiate deletion of their account within the app.

Deleting an account removes the account from the developer's records, along with any data associated with the account that the developer isn't legally required to maintain. Providing this capability gives people more control of the personal data they've shared. If you're updating an app or submitting a new app with account creation, read the guidance below for a smoother submission process.

## Account deletion guidance

Deleting an account is a major decision, so the process to initiate and confirm it must be straightforward and transparent:

- **Make the account deletion option easy to find in your app.** Typically, it's included in the app's account settings.
- **Offer to delete the entire account record, along with associated personal data.** You may include additional options, but only offering to temporarily deactivate or disable an account is insufficient.
- **If people need to visit a website to finish deleting their account, include a link directly to the page on your website where they can complete the process.** On tvOS, you can present a static URL or QR code that links directly to the account deletion page.
- **Keep people informed.** If the deletion request will take additional time to complete, let them know. If your app supports in-app purchases, help people understand how billing and cancellations will be handled. If you're legally required to retain some user information, let people know what information will and won't be retained. For additional guidance, read the [Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/managing-accounts).

**Note:** Follow applicable legal requirements for storing and retaining user account information and for handling account deletion. This includes complying with local laws where your app is available. If you have questions regarding your legal obligations, check with your legal counsel.

## FAQs

### Can I direct people to a customer service flow to complete account deletion?

It depends. Apps in highly regulated industries, as described in [App Review Guideline 5.1.1(ix)](https://developer.apple.com/app-store/review/guidelines/#data-collection-and-storage), may use additional customer service flows to confirm and facilitate the account deletion process. Apps not operating in highly regulated industries should not require people to make a phone call, send an email, use a chat support flow, or go through other support flows.

### Can I require reauthentication or add confirmation steps to ensure the account isn't deleted by accident or by someone other than the account holder?

Yes. It's appropriate to confirm the user genuinely intends to delete their account. You may add steps to verify the identity of the person making the request, and to confirm that they want to delete the account, such as by entering a code from an email or phone number already associated with the account. However, apps that make it unnecessarily difficult for someone to delete their account will not pass review.

### My app uses Sign in with Apple to provide account creation and authentication. What changes are necessary to support people who delete their accounts?

Apps that support Sign in with Apple should use the [Sign in with Apple REST API](https://developer.apple.com/documentation/signinwithapplerestapi) to [revoke user tokens](https://developer.apple.com/documentation/signinwithapplerestapi/revoke-tokens). Use server-to-server notification endpoints to [process changes for Sign in with Apple accounts](https://developer.apple.com/documentation/signinwithapple/processing-changes-for-sign-in-with-apple-accounts). Note that developers based in the Republic of Korea must [provide a server‑to‑server notification endpoint when registering a new Services ID](https://developer.apple.com/news/?id=j9zukcr6).

### If my app links out to the default web browser for account creation, does it still need to offer account deletion within the app?

Yes. Additionally, linking out to the default web browser to sign in or register an account provides a poor user experience and isn't appropriate, per [App Review Guideline 4](https://developer.apple.com/app-store/review/guidelines/#design).

### My app automatically creates an account for the user. Do I need to include an option to initiate account deletion?

Yes. People should have the option to delete automatically generated accounts (sometimes called "guest" accounts) and the data associated with those accounts. Ensure any automatic account creation in your app complies with local laws where your app is available.

### I manually delete accounts and this takes time. Does account deletion need to be immediate and automatic?

No. If your process for account deletion is manual or otherwise takes a reasonable amount of time to complete, this is acceptable. Inform the person how long it will take to delete the account and provide a confirmation when the deletion is complete. Ensure the time it takes to delete accounts complies with local laws where your app is available.

### Does the content provided by a person need to be deleted in apps that display and share user-generated content?

Yes. People expect that all data associated with their account will be deleted when the account is deleted. This includes user-generated content that's shared with others, such as photos, videos, text posts, and reviews. If local laws or regulations require you to maintain some data, let people know.

### I allow account deletion in compliance with CCPA, GDPR, or other local laws in some of the locations where my app is available. Is this sufficient?

No. Everyone should be able to delete their accounts, regardless of where they're located. Existing account deletion flows you've created to comply with local legal requirements can be made available to everyone, as long as they meet the requirements of [App Review Guideline 5.1.1(v)](https://developer.apple.com/app-store/review/guidelines/#data-collection-and-storage).

### How do I handle people with auto-renewable subscriptions? I don't want to accidentally charge someone after they've deleted their account.

If a person has an auto-renewable subscription, notify them that billing will continue through Apple and ask them to cancel their subscription before continuing. If you use [App Store Server Notifications](https://developer.apple.com/documentation/appstoreservernotifications/) for auto-renewable subscriptions, you can verify the status of the person's subscription in real time, or use the [Subscription Status API](https://developer.apple.com/documentation/appstoreserverapi/get-all-subscription-statuses) to identify subscription status.

Use [showManageSubscriptions](https://developer.apple.com/documentation/storekit/appstore/showmanagesubscriptions(in:)) in iOS 15 and iPadOS 15, or later, or provide this link to let people manage their subscriptions: <https://apps.apple.com/account/subscriptions/>. For tvOS, provide onscreen instructions to change or cancel a subscription, as described in the [Apple TV User Guide](https://support.apple.com/guide/tv/manage-subscriptions-atvb0d233668/tvos).

You can also use [beginRefundRequest](https://developer.apple.com/documentation/storekit/transaction/beginrefundrequest(in:)-9k0pj) in iOS 15 and iPadOS 15, or later, or provide this Apple Support link to let customers submit refund requests: <https://support.apple.com/118223>.

Additionally, you can offer to schedule account deletion for a later date, aligned with the subscription's expiration, as long as there's also an option to delete the account immediately.

**Related** [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) [Manage Accounts](https://developer.apple.com/design/human-interface-guidelines/managing-accounts)
