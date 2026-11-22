<!--
Source: https://developer.apple.com/help/app-store-connect/manage-subscriptions/set-up-subscription-offer-codes
Final URL: https://developer.apple.com/help/app-store-connect/manage-subscriptions/set-up-subscription-offer-codes
Retrieved (UTC): 2026-11-22T04:11:57Z
Raw file: set-up-subscription-offer-codes.html
SHA-256 of raw: e0e7debc7442688110f3a35ee2edeed26ee68c75fdf9a0a77627014cfdbf79f5
Extraction: automated text extraction for offline search; the raw file is authoritative.
-->

[](/help/app-store-connect/)

### App Store Connect Help

[App Store Connect](/help/app-store-connect/) / Manage subscriptions / Set up offer codes

Filter ⌘K

Filter ⌘K

Manage subscriptions

# Set up subscription offer codes

If you offer auto-renewable subscriptions on the App Store, you can set up offer codes to provide people with a free or discounted price for a specific duration and help you acquire, retain, and win back subscribers. You can create codes for a maximum of 1 million redemptions per app, per quarter.

There are two types of offer codes:

## One-time-use codes

- Unique, one-time-use codes that customers redeem through a redemption URL, by entering the code in the [App Store code redemption flow](https://support.apple.com/en-us/118242), or within your app.

- Customers are limited to redeeming one code per offer.

- Redeemable by customers within your app if they’re using a device running iOS 14, iPadOS 14, or macOS 15, or later and your app supports the appropriate StoreKit method. [Learn how to support offer codes in your app](https://developer.apple.com/documentation/storekit/supporting-offer-codes-in-your-app).

- Useful for small-scale distribution or when code access needs to be restricted.

- Each app can have up to 1 million codes per quarter, shared across all subscriptions.

- Expire after a maximum of six months from the date they’re created.

### Custom codes

- Uniquely named custom codes — for example, SPRINGPROMO — that customers redeem through a redemption URL or within your app.

- Customers are limited to redeeming one code per offer.

- Redeemable by customers within your app if they’re using a device running iOS 14, iPadOS 14, or macOS 15, or later and your app supports the appropriate StoreKit method. [Learn how to support offer codes in your app](https://developer.apple.com/documentation/storekit/supporting-offer-codes-in-your-app).

- Ideal for large campaigns that require mass distribution.

- An expiration date isn't required for custom codes. You can optionally set a maximum redemption limit and/or expiration date.

- Each app can have up to 1 million codes per quarter, shared across all subscriptions.

Customer eligibility is determined by you in App Store Connect and can include customers with new, active, and expired subscriptions. Consider your offer’s eligibility requirements before creating and distributing offer codes.

[Learn about offer types and which one to choose.](/app-store/subscriptions/#providing-subscription-offers)

[Get business guidance for auto-renewable subscriptions.](/app-store/subscriptions/)

![Configure offer codes](/help/app-store-connect/manage-subscriptions/set-up-subscription-offer-codes/images/InApp-Subs-offercode-config2_2x.png)

[Learn how to provide offer codes using the App Store Connect API.](https://developer.apple.com/documentation/appstoreconnectapi/app_store/auto-renewable_subscriptions/subscription_offer_codes)

**Required role:** Account Holder, Admin, App Manager, or Marketing. [View role permissions.](/help/app-store-connect/reference/account-management/role-permissions)

### Set up subscription offer codes

1.  From Apps, select your app.

2.  In the sidebar, click Subscriptions.

3.  Choose the subscription group containing your subscription.

4.  Select the subscription from the list.

5.  In the Subscription Prices section, click the add button (+).

6.  From the menu, click Create Offer Codes.

7.  Enter a reference name for the offer. You’ll use this reference name to manage the offer in App Store Connect and to identify sales associated with offers in Sales and Trends reports and [StoreKit transactions](/documentation/storekit/in-app_purchase).

8.  Choose whether you'd like the subscription to automatically renew to the standard price upon conclusion of the offer period. (Checking the box will prevent auto-renewal, ensuring customers receive a commitment-free trial subscription. If you choose this option, you’ll only be able to choose Free offers).

9.  Select the customer eligibility for your offer. You can select one or more of the following:

    - **New subscribers:** Customers who have never subscribed to any subscription product within the group.

    - **Existing subscribers:** Customers who are currently subscribed to a product within the group. This includes subscribers in billing retry or a grace period, as long as auto-renew remains enabled.

    - **Expired subscribers:** Customers who were previously subscribed to a product within the group, but whose auto-renew is turned off and subscription period has ended.

10. If your subscription has an introductory offer, determine whether people redeeming your codes should be eligible to redeem both a code and the introductory offer by choosing from the following options:

    - **Yes.** Eligible customers will redeem your app’s introductory offer first, then automatically renew to the offer they redeemed with the code. (If you've disabled auto-renewal, you won’t be able to choose this option).

    - **No.** Eligible customers will redeem the offer code first, then automatically renew to the standard subscription price without using the introductory offer. If they cancel and resubscribe at any point, they’re still eligible to redeem an introductory offer.

11. Click Next.

12. Select the countries or regions where you want to make your offer available, then click Next.

13. Choose [Pay as you go, Pay up front, or Free](/help/app-store-connect/reference/pricing-and-availability/in-app-purchase-and-subscriptions-pricing-and-availability). (If you've opted to disable auto-renewal, you'll only have the option to make your offer free.)

14. Choose the appropriate duration, and if applicable, the discounted price for a base country or region, then click Next. To search from a larger list of price points,click See Additional Prices.

    App Store Connect provides comparable prices for all 175 App Store countries and regions, taking into account taxes and foreign exchange rates. If you want to set different prices for specific storefronts, make the changes and click Next.

15. Make sure the details of your offer are correct and click Confirm.

    **Note:** Once you create an offer, you won’t be able to edit it. If changes to customer eligibility are needed, create a new offer.

### Create sandbox codes

Sandbox codes are one-time use codes for testing purposes. You can test offer redemptions through your Sandbox Account settings on iOS 16.3, macOS 15.0, and visionOS 1.0 or later, and if your app supports the required StoreKit APIs. [Learn how to support offer codes in your app.](https://developer.apple.com/documentation/storekit/supporting-subscription-offer-codes-in-your-app)

1.  From Apps, select your app.

2.  In the sidebar, click subscriptions.

3.  Choose the subscription group containing your subscription.

4.  Select the subscription from the list.

5.  Scroll down to the Offers section and locate your offer in the list.

6.  Click the reference name.

7.  In the Sandbox Codes section, click the Create Sandbox Codes button.

8.  In the pop-up window, choose the number of codes you want to create. You must select a minimum of 10 and a maximum of 10,000 codes.

9.  Choose an expiration date to determine how long the codes are valid. Sandbox codes can be valid for a maximum of six months. Codes expire at 12:00 a.m PT on the expiration date.

### Create one-time use codes

In order for customers to redeem codes, your app must be in the Ready for Sale state.

1.  From Apps, select your app.

2.  In the sidebar, click subscriptions.

3.  Choose the subscription group containing your subscription.

4.  Click the subscription, then go to the Subscription Prices section and click View all Subscription Pricing.

5.  In the menu bar, click Offer Codes.

6.  Select your offer from the list.

7.  Click the “Create One-Time Use Codes” button.

8.  In the pop-up window, select the number of codes you want to create.

    You must select a minimum of 500 and a maximum of 25,000. If you need more than 25,000 codes, you can create multiple batches of codes for the same offer.

9.  Choose an expiration date to determine how long the codes are valid. One-time use codes can be valid for a maximum of six months. Codes expire at 12:00 a.m. PT on the expiration date.

10. Click Create. It may take up to an hour before codes are redeemable by customers.

### Download one-time use codes

Once your one-time use codes are created, you’ll need to download them from App Store Connect so you can share them.

1.  From Apps, select your app.

2.  In the sidebar, click subscriptions.

3.  Choose the subscription group containing your subscription.

4.  Click the subscription, then go to the Subscription Prices section and click View all Subscription Pricing.

5.  In the menu bar, click Offer Codes.

6.  Locate your offer in the list and click the reference name.

7.  Locate the codes you want to download and click Download.

8.  Open the extracted text (`.csv`) file in a spreadsheet application.

### Create custom codes

Once you’ve created custom codes, you won’t be able to edit them. Custom codes can’t be used for other offer campaigns or subscriptions for the app. To create a custom code that's already being used by a different offer for the same app, you must first deactivate the code.

1.  From Apps, select your app.

2.  In the sidebar, click subscriptions.

3.  Choose the subscription group containing your subscription.

4.  Click the subscription, then go to the Subscription Prices section and click View all Subscription Pricing.

5.  In the menu bar, click Offer Codes.

6.  Select the offer from the list.

7.  Click the “Create Custom Codes” button.

8.  Enter a custom code up to 64 characters and without any special characters.

9.  Choose a redemption limit. This is the total number of people who can redeem this custom code. You can choose a limit of up to 25,000 at a time. If you need more, use the same custom code multiple times for the same offer.

    **Note:** To extend a custom code's availability, create a new batch using the same code and a later expiration date. The system always redeems from the earliest non-expired batch first, so codes from both batches remain redeemable until each expires or reaches its redemption limit. To stop the original batch from being redeemed, deactivate it before creating the new one.

10. Choose an expiration date to determine how long the codes will be valid (with a maximum of 6 months for codes with an expiration date). Codes expire at 12:00 a.m. PT on the expiration date.

    To create codes with no expiration date, choose No End Date from the date picker. Expiration dates can't be edited.

11. Click Create. It may take up to an hour before codes are redeemable by customers.

### Distribute offer codes

You're responsible for distributing offer codes to your customers. You can utilize your own channels, such as email or offline marketing campaigns.

- **Give codes to customers directly:** Codes can be shared through online or offline channels. For example, you might print the codes on cards that you give out at an event. People can redeem one-time use codes by entering them in the “Redeem Gift Card or Code” page in their App Store account settings, or redeem custom codes within your app if you’ve implemented the appropriate StoreKit method. [Learn more about offer codes distribution](/app-store/subscriptions/#offer-codes).

- **Create a unique redemption URL:** Codes can be used to create redemption URLs that you can share directly. When someone visits the URL, they'll land on a page where they can redeem your code. People who haven't installed your app will first be prompted to download the app before redeeming the code.

  To create these URLs for one-time use codes, copy the example link from your offer details page, then add each code to the end of the URL. One-time use code URLs are also included in the downloadable text file.

![Distribute offer code](/help/app-store-connect/manage-subscriptions/set-up-subscription-offer-codes/images/InApp-Subs-offercode-dist2_2x.png)

### Deactivate offer codes

1.  From Apps, select your app.

2.  In the sidebar, click subscriptions.

3.  Choose the subscription group containing your subscription.

4.  Click a subscription, then go to the Subscription Prices section and click View all Subscription Pricing.

5.  In the menu bar, click Offer Codes.

6.  Click the reference name of the offer.

7.  Locate the codes you want to deactivate and click Deactivate.

8.  Click Deactivate again to proceed

    The codes will expire immediately. Subscribers who have already redeemed the codes won’t be affected. Unredeemed codes will also expire and will not be reapplied to the 1,000,000 quarterly limit.

### Deactivate offers

You can have up to 10 active offers per subscription SKU at a time in App Store Connect. If you wish to deactivate an offer, please note that the offer can't be reactivated later. All codes associated with the offer will be invalidated. Subscribers who have already redeemed codes for the offer won't be affected.

1.  From Apps, select your app.

2.  In the sidebar, click subscriptions.

3.  Choose the subscription group containing your subscription.

4.  Click a subscription, then go to the Subscription Prices section and click View all Subscription Pricing.

5.  In the menu bar, click Offer Codes.

6.  Click the reference name of the offer.

7.  In the upper corner, click Deactivate.

    You can view your deactivated offers anytime, as well as download expired codes associated with deactivated offers.

**Related** [Offer codes](/app-store/subscriptions/#offer-codes) [Implementing offer codes in your app](https://developer.apple.com/documentation/storekit/original_api_for_in-app_purchase/subscriptions_and_offers/implementing_offer_codes_in_your_app) [Supporting subscription offer codes in your app](https://developer.apple.com/documentation/storekit/appstore/supporting_subscription_offer_codes_in_your_app) [Watch "Subscription offer codes"](https://developer.apple.com/videos/play/tech-talks/10868/)
