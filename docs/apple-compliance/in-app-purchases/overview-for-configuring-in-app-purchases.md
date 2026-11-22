<!--
Source: https://developer.apple.com/help/app-store-connect/configure-in-app-purchase-settings/overview-for-configuring-in-app-purchases
Final URL: https://developer.apple.com/help/app-store-connect/configure-in-app-purchase-settings/overview-for-configuring-in-app-purchases
Retrieved (UTC): 2026-11-22T04:11:57Z
Raw file: overview-for-configuring-in-app-purchases.html
SHA-256 of raw: 6481d29888eee14752b503516c1b4963215ddc4dc05648ddf52eeb61b01c2fc9
Extraction: automated text extraction for offline search; the raw file is authoritative.
-->

[](/help/app-store-connect/)

### App Store Connect Help

[App Store Connect](/help/app-store-connect/) / Configure In-App Purchase settings / Overview for configuring In-App Purchases

Filter ⌘K

Filter ⌘K

Configure In-App Purchase settings

# Overview for configuring In-App Purchases

In-App Purchases let you offer extra content and features in your apps distributed on the App Store — including digital goods, subscriptions, and premium content — directly within your app on all Apple platforms. To make an In-App Purchase available in multiple platform versions of your app, create a single In-App Purchase under the Distribution tab in App Store Connect, then use [StoreKit](https://developer.apple.com/documentation/storekit/in-app_purchase/) to implement the In-App Purchase in the various platform versions of your app.

**Note:** It may take up to 1 hour for changes you make to product metadata to appear in the sandbox environment.

There are four types of In-App Purchases:

| Type                         | Description                                                                                                                                                                                                                  |
|------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Consumable                   | A product that is used once, after which it becomes depleted and must be purchased again. Example: fish food in a fishing app.                                                                                               |
| Non-consumable               | A product that is purchased once and does not expire or decrease with use. Example: race track for a game app.                                                                                                               |
| Auto-renewable subscriptions | A product that allows users to purchase dynamic content for a set period. This type of Subscription renews automatically unless canceled by the user. Example: Monthly subscriptions for an app offering streaming services. |
| Non-renewing subscriptions   | A product that allows users to access content for a limited duration of time. This type of Subscription does not renew automatically. Example: One year subscription to view live gaming content.                            |

You can create up to 10,000 In-App Purchase products per app. Every In-App Purchase must be associated with an app and can be shared across multiple platform versions (iOS, macOS, tvOS). In-App Purchases are not shareable between different apps.

Implementing In-App Purchases in your app requires configuration between your apps’ server and Apple’s servers, as well as set up and ongoing management in App Store Connect. The following workflow can be used:

1.  **Accept the Paid Apps Agreement**

    To offer In-App Purchases, the membership Account Holder must [accept the Paid Apps Agreement](/help/app-store-connect/manage-agreements/sign-and-update-agreements) in the Business section of App Store Connect and provide banking and tax information.

    **Note:** The agreement must be Active to test In-App Purchases in the sandbox environment.

2.  **Design your In-App Purchase**

    To ensure your In-App Purchase experience fits well with the rest of your app and effectively showcases your products, review the [Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/technologies/in-app-purchase) and [App Review Guidelines](/app-store/review/guidelines/).

3.  **Configure In-App Purchases in App Store Connect**

    [Create In-App Purchases](/help/app-store-connect/manage-consumable-and-non-consumable-in-app-purchases/create-in-app-purchases) and add metadata, such as product name, description, price, and availability. You’ll also need to [generate In-App Purchase keys](/help/app-store-connect/configure-in-app-purchase-settings/generate-keys-for-in-app-purchases) and [set a tax category](/help/app-store-connect/configure-in-app-purchase-settings/set-a-tax-category-for-in-app-purchases), which will allow Apple to calculate the appropriate tax on customer transactions.

4.  **Implement StoreKit**

    Sign your app with a provisioning profile that includes your app's bundle identifier and the In-App Purchase capability. Make sure the bundle identifier and product identifiers in Xcode match those configured for your app and In-App Purchases in App Store Connect.

5.  **Test your In-App Purchases**

    Apple provides a testing environment, called sandbox, which allows you to [test In-App Purchases](https://developer.apple.com/documentation/storekit/in-app_purchase/testing_at_all_stages_of_development_with_xcode_and_the_sandbox) without incurring charges using [test accounts](/help/app-store-connect/test-in-app-purchases/create-a-sandbox-apple-account). Test each part of your code to verify that you’ve implemented it correctly by using your app to make In-App Purchases.

    You can further test your app and In-App Purchases using either [TestFlight](/help/app-store-connect/test-a-beta-version/testflight-overview), or [Xcode](https://developer.apple.com/documentation/xcode/setting-up-storekit-testing-in-xcode).

6.  **Use App Store Server Notifications**

    [App Store Server Notifications](https://developer.apple.com/documentation/appstoreservernotifications) provide near real-time updates about transaction status and key events related to In-App Purchases, such as a refund or a change in subscription status or Family Sharing access. To leverage these notifications, you’ll need to [enter URLs for your production and sandbox server environments](/help/app-store-connect/configure-in-app-purchase-settings/enter-server-urls-for-app-store-server-notifications) in App Store Connect.

7.  **Submit your In-App Purchases for review**

    Before you publish your In-App Purchase on the App Store it must be [submitted for review](/help/app-store-connect/manage-submissions-to-app-review/overview-of-submitting-for-review). If you’re submitting your first In-App Purchase, you must submit it with a new version of your app. Ensure you aren't missing any [required information](/help/app-store-connect/reference/app-information/required-localizable-and-editable-properties) before submitting. Monitor [In-App Purchase statuses](/help/app-store-connect/reference/in-app-purchases-and-subscriptions/in-app-purchase-statuses) to understand if your In-App Purchase is available or if it needs your attention.

**Related** [Developer Videos](https://developer.apple.com/videos/app-store-distribution-marketing?q=in%20app%20purchases) [Marketing In-App Purchases](/in-app-purchase/) [Auto-renewable subscriptions](/app-store/subscriptions/) [In-App Purchase programming guide](https://developer.apple.com/documentation/storekit/in-app_purchase)
