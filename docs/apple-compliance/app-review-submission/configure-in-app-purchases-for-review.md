<!--
Source: https://developer.apple.com/help/app-review/before-submitting-for-review/configure-in-app-purchases
Final URL: https://developer.apple.com/help/app-review/before-submitting-for-review/configure-in-app-purchases
Retrieved (UTC): 2026-11-22T04:11:57Z
Raw file: configure-in-app-purchases-for-review.html
SHA-256 of raw: a20b70e6a4063aa0216790a39453caa49aca21d2aa0d45fc04649cdd8aa17ac3
Extraction: automated text extraction for offline search; the raw file is authoritative.
-->

[](/help/app-review/)

### App Review Help

[App Review](/help/app-review/) / Before submitting for review / Configure In-App Purchases for review in the sandbox

Filter ⌘K

Filter ⌘K

Before submitting for review

# Configure In-App Purchases for review in the sandbox

App Review evaluates your In-App Purchases in the same sandbox environment you use for testing. The sandbox lets App Review use real product data and server-to-server transactions without incurring any financial charges. Configure and test In-App Purchases in this environment before you submit them to ensure your products function as expected during review.

**Note:** In-App Purchases do not need prior approval from App Review to function in review.

1.  The Account Holder must [accept the Paid Apps Agreement](https://developer.apple.com/help/app-store-connect/manage-agreements/sign-and-update-agreements) in the Business section of App Store Connect, then [confirm the agreement is in effect](https://developer.apple.com/help/app-store-connect/manage-agreements/view-agreements-status/#view-the-status-of-an-agreement). Paid In-App Purchases won't function in review until this agreement is active.

2.  [Create a Sandbox Apple Account](https://developer.apple.com/help/app-store-connect/test-in-app-purchases/create-a-sandbox-apple-account) and [configure product information](https://developer.apple.com/help/app-store-connect/configure-in-app-purchase-settings/overview-for-configuring-in-app-purchases) in App Store Connect.

3.  Fetch product information using [StoreKit APIs](https://developer.apple.com/documentation/storekit) before presenting In-App Purchases in your app's UI to ensure the displayed details match your configuration in App Store Connect.

4.  [Test your In-App Purchases in the sandbox](https://developer.apple.com/documentation/storekit/testing-in-app-purchases-with-sandbox) before you submit. If one fails to display, follow [TN3186: Troubleshooting In-App Purchases availability in the sandbox](https://developer.apple.com/documentation/technotes/tn3186-troubleshooting-in-app-purchases-availability-in-the-sandbox).

5.  If you restrict In-App Purchases by storefront or device configuration, [specify this in the Notes field in the App Review Information section of App Store Connect](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/#app-review-information).

6.  [Submit the In-App Purchases](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase) in App Store Connect once they're in the [Ready for Review](https://developer.apple.com/help/app-store-connect/reference/in-app-purchases-and-subscriptions/in-app-purchase-statuses) state.

**Related** [Overview of testing in sandbox](https://developer.apple.com/help/app-store-connect/test-in-app-purchases/overview-of-testing-in-sandbox) [Testing In-App Purchases with sandbox](https://developer.apple.com/documentation/storekit/testing-in-app-purchases-with-sandbox) [Provide information for a complete review](https://developer.apple.com/help/app-review/before-submitting-for-review/complete-review) [Test your app on compatible devices](https://developer.apple.com/help/app-review/before-submitting-for-review/test-compatible-devices)
