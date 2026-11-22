<!--
Source: https://developer.apple.com/help/app-store-connect/manage-subscriptions/enable-billing-grace-period-for-auto-renewable-subscriptions
Final URL: https://developer.apple.com/help/app-store-connect/manage-subscriptions/enable-billing-grace-period-for-auto-renewable-subscriptions
Retrieved (UTC): 2026-11-22T04:11:57Z
Raw file: enable-billing-grace-period.html
SHA-256 of raw: 20e3add15919c2266ae717a5d455d9b86fc3f0f2174e18c426ba4ab327f99d61
Extraction: automated text extraction for offline search; the raw file is authoritative.
-->

[](/help/app-store-connect/)

### App Store Connect Help

[App Store Connect](/help/app-store-connect/) / Manage subscriptions / Enable billing grace period for auto-renewable subscriptions

Filter ⌘K

Filter ⌘K

Manage subscriptions

# Enable Billing Grace Period for auto-renewable subscriptions

Billing Grace Period lets subscribers whose auto-renewal failed due to a payment issue continue accessing your app’s paid content for a period of time while Apple continues to attempt to collect payment. There won’t be any interruption to the subscriber’s days of paid service or to your revenue if Apple recovers the subscription within the grace period. Without enabling Billing Grace Period, the subscriber’s days of paid service pause until Apple is able to collect payment.

**Note:** It may take up to 1 hour for changes you make to product metadata to appear in the sandbox environment. Billing Grace Period doesn't apply for monthly subscriptions with a 12 month commitment.

[You can configure grace periods in App Store Connect using the App Store Connect API.](https://developer.apple.com/documentation/appstoreconnectapi/app_store/auto-renewable_subscriptions/managing_auto-renewable_subscriptions)

## **Workflow for enabling Billing Grace Period**

Enabling Billing Grace Period requires you turn on and complete configurations in App Store Connect, and use StoreKit to verify subscribers’ renewal states so they retain access to subscription content while in the billing retry state.

The following workflow can be used to properly test and validate your server to app’s logic before fully rolling out the feature to your subscribers.

1.  **Turn on Billing Grace Period in sandbox.**

    Make sure to do this only before turning it on in production.

2.  **Test Billing Grace Period in sandbox.**

    Use the sandbox environment to validate your client and server logic to handle subscribers entering and exiting the grace period. [View implementation guidance.](https://developer.apple.com/documentation/storekit/in-app_purchase/original_api_for_in-app_purchase/subscriptions_and_offers/reducing_involuntary_subscriber_churn)

3.  **Turn on Billing Grace Period in production.**

    Once you validate your client and server logic, edit your Billing Grace Period configuration to support the production environment.

**Required role:** Account Holder, Admin or App Manager. [View role permissions.](/help/app-store-connect/reference/account-management/role-permissions)

### Turn on Billing Grace Period

You can turn on Billing Grace Period for each app in App Store Connect to provide a grace period for all auto-renewable subscriptions in the app. Configurability isn’t available for individual subscription products.

1.  From Apps, select your app.

2.  In the sidebar, click Subscriptions.

3.  In the Billing Grace Period section, click Set Up Billing Grace Period.

4.  From the menu, select a period of 3, 16, or 28 days to apply across all subscription products in your app.

    **Note:** If your app offers weekly subscriptions, even if you select a 16 or 28 day grace period, the actual grace period will only be 6 days to ensure it isn't longer than the subscription itself.

    Your selection will only apply to subscription products in production. [Learn about the Billing Grace Period renewal rates in sandbox.](/help/app-store-connect/test-in-app-purchases/manage-sandbox-apple-account-settings#edit-subscription-renewal-speed)

    |                                  | 3 day Billing Grace Period | 16 day Billing Grace Period | 28 day Billing Grace Period |
    |----------------------------------|----------------------------|-----------------------------|-----------------------------|
    | Weekly subscriptions             | 3 days                     | 6 days                      | 6 days                      |
    | Monthly and yearly subscriptions | 3 days                     | 16 days                     | 28 days                     |

5.  Select the renewal types for which you want to enable a grace period:

    - **All Renewals:** Billing Grace Period applies to all renewals, including free introductory offers and free subscription offers transitioning to paid subscriptions.

    - **Only Paid to Paid Renewals:** Billing Grace Period will only apply to subscriptions in a currently paid period, therefore subscriptions currently in a Free period won’t receive a billing grace period.

6.  Select the server environments for which you want to enable Billing Grace Period.

    - **Only Sandbox Environment:** Billing Grace Period is enabled in the sandbox environment only. Use Sandbox to test that your app provides service to subscriptions during a grace period.

    - **Production and Sandbox Environment:** Billing Grace Period is enabled in both sandbox and production environments.

7.  Click Confirm.

    Your app still needs to perform purchase validation and account for the subscriber’s renewal status to identify if a subscription is in a Billing Grace Period.

### Edit Billing Grace Period configuration

1.  From Apps, select your app.

2.  In the sidebar, click Subscriptions.

3.  In the Billing Grace Period section, click Edit. You can edit the duration of the grace period, the eligible renewal types, and the enabled environments. Changes can take up to 24 hours to take effect and will only apply to upcoming renewals. Subscribers currently in Billing Grace Period are still entitled to service during their grace period.

4.  Click Done.

### Turn off Billing Grace Period

You can turn off Billing Grace Period for each app.

1.  From Apps, select your app.

2.  In the sidebar, click Subscriptions.

3.  In the Billing Grace Period section, click Edit.

4.  Click Turn Off.

    Once you turn off Billing Grace Period, subscribers whose renewal fails due to a billing issue won’t accumulate days of paid service until Apple is able to collect payment and renew the subscription. Ensure that your app continues to provide service for subscriptions that are already in Billing Grace Period.

**Related** [Reducing Involuntary Subscriber Churn](https://developer.apple.com/documentation/storekit/in-app_purchase/reducing_involuntary_subscriber_churn) [Auto-renewable subscriptions](/app-store/subscriptions/) [App Store Receipts](https://developer.apple.com/documentation/appstorereceipts) [In-App Purchase](/documentation/storekit/in-app_purchase)
