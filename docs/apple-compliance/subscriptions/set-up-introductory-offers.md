<!--
Source: https://developer.apple.com/help/app-store-connect/manage-subscriptions/set-up-introductory-offers-for-auto-renewable-subscriptions
Final URL: https://developer.apple.com/help/app-store-connect/manage-subscriptions/set-up-introductory-offers-for-auto-renewable-subscriptions
Retrieved (UTC): 2026-11-22T04:11:57Z
Raw file: set-up-introductory-offers.html
SHA-256 of raw: bedb76b8e3d91471aed064becab6a3e5be0994e702a4204b879ecf5dadc6c62c
Extraction: automated text extraction for offline search; the raw file is authoritative.
-->

[](/help/app-store-connect/)

### App Store Connect Help

[App Store Connect](/help/app-store-connect/) / Manage subscriptions / Set up introductory offers for auto-renewable subscriptions

Filter ⌘K

Filter ⌘K

Manage subscriptions

# Set up introductory offers for auto-renewable subscriptions

You can set up introductory offers for your apps on the App Store that contain auto-renewable subscriptions in App Store Connect. An introductory offer is a limited-time discounted price or free trial for the initial period of a subscription.

When you set up an introductory offer, it automatically appears on your app’s product page on the App Store for eligible users. You can also display introductory offers within your app. When displaying offers in your app, use receipt validation to ensure that you’re only showing offers to people who can redeem them. [Learn about implementing introductory offers](https://developer.apple.com/documentation/storekit/original_api_for_in-app_purchase/subscriptions_and_offers/implementing_introductory_offers_in_your_app).

There are three types of introductory offers: free trial, pay up front, and pay as you go. You can choose the length of the introductory offer based on the standard subscription duration.

**Note:** It may take up to 1 hour for changes you make to product metadata to appear in the sandbox environment.

| Standard Subscription Duration | Pay As You Go                | Pay Up Front                  | Free Trial                                          |
|--------------------------------|------------------------------|-------------------------------|-----------------------------------------------------|
| 1 Week                         | 1 to 12 Weeks                | 1, 2, 3, or 6 Months. 1 Year. | 3 Days. 1 or 2 Weeks. 1, 2, 3, or 6 Months. 1 Year. |
| 1 Month                        | 1 to 12 Months               | 1, 2, 3, or 6 Months. 1 Year. | 3 Days. 1 or 2 Weeks. 1, 2, 3, or 6 Months. 1 Year. |
| 2 Months                       | 2, 4, 6, 8, 10, or 12 Months | 1, 2, 3, or 6 Months. 1 Year. | 3 Days. 1 or 2 Weeks. 1, 2, 3, or 6 Months. 1 Year. |
| 3 Months                       | 3, 6, 9, or 12 Months        | 1, 2, 3, or 6 Months. 1 Year. | 3 Days. 1 or 2 Weeks. 1, 2, 3, or 6 Months. 1 Year. |
| 6 Months                       | 6 or 12 Months               | 1, 2, 3, or 6 Months. 1 Year. | 3 Days. 1 or 2 Weeks. 1, 2, 3, or 6 Months. 1 Year. |
| 1 Year                         | 1 Year                       | 1, 2, 3, or 6 Months. 1 Year. | 3 Days. 1 or 2 Weeks. 1, 2, 3, or 6 Months. 1 Year. |

Although you can create an introductory offer for each subscription product in App Store Connect, each person is only eligible to redeem one introductory offer per subscription group.

[Learn how to set up introductory offers with the App Store Connect API.](https://developer.apple.com/documentation/appstoreconnectapi/app_store/auto-renewable_subscriptions/subscription_introductory_offers)

**Required role:** Account Holder, Admin, App Manager, or Marketing. [View role permissions.](/help/app-store-connect/reference/account-management/role-permissions)

## Create an introductory offer

1.  From Apps, select your app.

2.  In the sidebar, click Subscriptions.

3.  Choose the subscription group containing your subscription.

4.  Select a subscription, then go to the Subscription Prices section and click View all Subscription pricing.

5.  Select Set up Introductory Offer.

    ![Set Up Introductory Price](/help/app-store-connect/manage-subscriptions/set-up-introductory-offers-for-auto-renewable-subscriptions/images/Set-an-introductory-price-for-an-auto-renewable-subscription-iOS-tvOS-macOS-Create-an-introductory-price-Step4_2x.png)

6.  Select the countries or regions where you want to offer a discounted price, and click Next. You can have one current and one future introductory offer per storefront.

    ![Countries or regions for introductory price](/help/app-store-connect/manage-subscriptions/set-up-introductory-offers-for-auto-renewable-subscriptions/images/Set-an-introductory-price-for-an-auto-renewable-subscription-iOS-tvOS-macOS-Create-an-introductory-price-Step5_2x.png)

7.  Choose the start and end dates for your introductory offer. If you choose today as the start date, your introductory offer begins immediately. Offers end on the selected end date, with the [exact time varying by region](/help/app-store-connect/reference/pricing-and-availability/app-store-pricing-and-availability-start-times-by-country-or-region).

    Click Next. If you create new offers that have overlapping dates, the latest action overwrites existing introductory offers. [Learn about available offers and subscriber eligibility using the In-App Purchase API.](https://developer.apple.com/documentation/storekit/product/subscriptioninfo)

8.  Choose [Pay as you go, Pay up front, or Free](/help/app-store-connect/reference/pricing-and-availability/in-app-purchase-and-subscriptions-pricing-and-availability), then choose the appropriate duration, country or region, and price. To search from a larger list of price points, click See Additional Prices.

9.  App Store connect provides comparable prices for all 175 App Store countries and regions, taking into account taxes and foreign exchange rates. If you want to set different prices for specific storefronts, make the changes and click Next.

    ![Introductory prices for countries or regions](/help/app-store-connect/manage-subscriptions/set-up-introductory-offers-for-auto-renewable-subscriptions/images/Set-an-introductory-price-for-an-auto-renewable-subscription-iOS-tvOS-macOS-Create-an-introductory-price-Step8_2x.png)

10. Make sure the details of your introductory offer are correct and click Confirm. Once you create an introductory offer, you won’t be able to edit it. To change the details of your introductory offer, delete it and create a new one.

### Delete an introductory offer

1.  From Apps, select your app.

2.  In the sidebar, click Subscriptions.

3.  Choose the subscription group containing your subscription.

4.  Click the subscription you want to delete, then go to the Subscription Prices section and click View all Subscription Pricing.

5.  Navigate to the Introductory Offers tab to view, all your offers listed by date and country or region.

6.  Find the introductory offer you wish to delete, and move your pointer over the right side of the price change row until the remove button (—) appears. Click the remove button.

    ![Introductory Prices](/help/app-store-connect/manage-subscriptions/set-up-introductory-offers-for-auto-renewable-subscriptions/images/Set-an-introductory-price-for-an-auto-renewable-subscription-iOS-tvOS-macOS-Delete-an-introductory-price-Step5_2x.png)

7.  Click Delete in the dialog.

    ![Confirm introductory price delete](/help/app-store-connect/manage-subscriptions/set-up-introductory-offers-for-auto-renewable-subscriptions/images/Set-an-introductory-price-for-an-auto-renewable-subscription-iOS-tvOS-macOS-Delete-an-introductory-price-Step6_2x.png)

### FAQs

### What is the difference between introductory offer limits and customer eligibility limits?

App Store Connect allows you to set an introductory offer for each subscription product in App Store Connect. You can have multiple offers in each subscription group. New and returning customers are only eligible to use one introductory offer per subscription group. For example, if a customer uses a free trial and then upgrades to a subscription product in the same group that also has a free trial, they aren't eligible for the second offer.
