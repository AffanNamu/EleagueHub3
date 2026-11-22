<!--
Source: https://developer.apple.com/help/app-store-connect/manage-subscriptions/manage-pricing-for-auto-renewable-subscriptions
Final URL: https://developer.apple.com/help/app-store-connect/manage-subscriptions/manage-pricing-for-auto-renewable-subscriptions
Retrieved (UTC): 2026-11-22T04:11:57Z
Raw file: manage-pricing-for-auto-renewable-subscriptions.html
SHA-256 of raw: d7bd365352ca646bee5ac0560806c9432af536fe94eebac1a49e4b349374c5c7
Extraction: automated text extraction for offline search; the raw file is authoritative.
-->

[](/help/app-store-connect/)

### App Store Connect Help

[App Store Connect](/help/app-store-connect/) / Manage subscriptions / Manage pricing for auto-renewable subscriptions

Filter ⌘K

Filter ⌘K

Manage subscriptions

# Manage pricing for auto-renewable subscriptions

Auto-renewable subscriptions can be priced by App Store country or region (also known as storefronts.) You can choose from 800 price points in each currency, with the option for the Account Holder to submit a request for additional higher price points.

After you set a starting price for your auto-renewable subscription, you can schedule one future price change at a time, per country or region, per billing plan type. If you schedule a second price change when you already have a change scheduled, the first scheduled change will be overwritten. Additionally, if you schedule a price increase before an earlier (previously implemented) price increase has been completed across all of your active subscribers, you may see some subscriptions renew again at their original price when there is not enough time to provide the customers with the required notice or request for consent detailed in the Price Increase section below. You also have the option to preserve prices for existing subscribers.

It may take up to 1 hour for changes you make to product metadata to appear in the sandbox environment.

**Subscriptions with volume pricing configured using the App Store Connect API:**  
If you configure volume discount tiers for an auto-renewable subscription using the App Store Connect API, you won't be able to view or manage pricing until volume pricing is supported in App Store Connect early next year. You also can't un-preserve prices while volume discount tiers are configured. To un-preserve prices or manage pricing in App Store Connect again, first remove all volume discount tiers using the API.

[Learn how to configure auto-renewable subscription pricing with the App Store Connect API](https://developer.apple.com/documentation/appstoreconnectapi/app_store/auto-renewable_subscriptions/managing_auto-renewable_subscriptions)

**Required role:** Account Holder, Admin, or App Manager. [View role permissions.](/help/app-store-connect/reference/account-management/role-permissions)

## Set a starting price for your auto-renewable subscription

1.  In Apps, select the app you want to view.

2.  In the sidebar, click Subscriptions.

3.  Click the subscription group name.

4.  Click the subscription reference name.

5.  Scroll down to the Subscription Prices section and click Add Subscription Price.

6.  Choose a country or region and price, then click Next. To search from a larger list of price points, click See Additional Prices.

7.  App Store Connect provides comparable prices for all 175 App Store countries and regions, taking into account taxes and foreign exchange rates. If you want to set different prices for specific storefronts, make the changes and click Next.

8.  Make sure your subscription’s starting price is correct and click Confirm.

## Decrease the price of an auto-renewable subscription

If you decrease the price of your auto-renewable subscription, existing subscriptions will automatically renew at the lower price. You don’t have the option to preserve the higher price for existing subscribers.

1.  In Apps, select the app you want to view.

2.  In the sidebar, click Subscriptions.

3.  Click the subscription group name.

4.  Click the subscription reference name.

5.  Scroll down to the Subscription Prices section and click the add button (+).

6.  Select the storefronts where you want to edit pricing.

7.  Choose a start date, country or region, and price, then click Next. To search from a larger list of price points, click See Additional Prices.

8.  App Store Connect provides comparable prices for all 175 App Store countries and regions, taking into account taxes and foreign exchange rates. If you want to set different prices for specific storefronts, make the changes and click Next.

9.  Make sure the details of your price decrease are correct and click Confirm.

    You can schedule one future price change at a time, per storefront, per billing plan type. If you schedule a second price change when you already have a change scheduled, the first scheduled change will be overwritten.

10. Once a price decrease goes into effect, it can’t be reversed. However, you can schedule a price increase later.

## Increase the price of an auto-renewable subscription

Increases in auto-renewable subscription prices result in either a notice to active subscribers or a request for consent, based on certain criteria below. Subscribers on introductory or promotional price subscriptions, including free trials and paid offers, will renew for at least one more renewal period at the price that was displayed when they subscribed, to ensure their notice or request for consent for the new price is sent at least 30 days in advance. If a subscriber doesn't consent before the first renewal at the higher price, their subscription will expire at the end of the last renewal cycle at the former price. If your subscription has multiseat purchasing enabled, additional criteria apply. Visit the FAQs below.

### Consent needed

If any of the following applies, subscribers must consent to the price increase before their next renewal date in order for the subscription to renew. \* Apple will automatically contact subscribers by email or push notification to request consent.

- The subscriber is located in a region that requires consent for any price changes.

- The price increase is more than 50% of the current price and the difference in price exceeds approximately US\$5 per period for non-annual subscriptions, or US\$50 per year for annual subscriptions. (International equivalents for prices not in USD are based on current exchange rates with specific thresholds that are subject to change based on changes in taxes or foreign exchange rates.) [View a list of thresholds per storefront.](/help/app-store-connect/reference/in-app-purchases-and-subscriptions/auto-renewable-subscription-price-increase-thresholds)

- The subscriber experienced a price increase for that subscription within the past 12 months.

The timing of price consent requests from Apple depends on the length of the subscription. If a price increase occurs within the minimum required notice period (7 days for weekly subscriptions, 27 days for 1 month subscriptions, and 30 days for subscription durations longer than 1 month), subscribers will renew at their existing price for one more billing period and will receive price consent requests from Apple before the end of their next billing period.

| Subscription duration                                   | First email notification (email, push, in-app messaging) |
|---------------------------------------------------------|----------------------------------------------------------|
| 2 month, 3 month, and 6 month, and annual subscriptions | 60 days before renewal date                              |
| Monthly subscriptions                                   | 27 days before renewal date                              |
| Weekly subscriptions                                    | 7 days before renewal date                               |

If a subscriber doesn’t agree to the new price or takes no action, Apple will continue to request consent approximately weekly through email, push notifications, and in-app messaging until their subscription expires at the end of their current billing cycle. [Learn how StoreKit displays price increase consent messages in your app](https://developer.apple.com/documentation/storekit/message)

\* If you increase the price of an auto-renewable subscription in India, subscribers who have enabled UPI AutoPay must consent to the new price and have a sufficient payment balance associated with their Apple Account, or they’ll go into the billing retry state at the end of their current billing period. Apple will notify these subscribers as part of the price increase notice, but you may also wish to notify subscribers separately. Subscribers who don’t have a sufficient Apple Account balance or who wish to continue paying with UPI AutoPay must repurchase the subscription at the new price. [Learn more](https://support.apple.com//HT212781)

\* For users converting from trials or offers in South Korea, Apple will collect consent via email, in-app sheets, or push notifications. The timing and frequency of these communications may differ from those shown for standard subscription price increases. [Learn about consent for subscription offer conversions.](/help/app-store-connect/reference/in-app-purchases-and-subscriptions/consent-for-subscription-offer-conversions)

### Consent not needed

If none of the criteria apply, Apple will automatically notify subscribers of the price increase with no additional request for consent. After the new price goes into effect, notifications are sent via email and push notifications — if enabled by the subscriber — 27 or 7 days before the next renewal date. On iOS 13.4 or later, Apple will also notify subscribers via in-app messaging. If a price increase occurs within the minimum required notice period, subscribers will renew at their existing price for one more billing period and will be notified before the end of their next billing period.

**Note:** A new price increase can overwrite a previous one that a customer was notified about but hasn't yet renewed at. In that case, the customer renews at their existing price for one more billing period.

Price changes apply only to active subscribers. If a subscription recovers during billing retry or the grace period, it renews at the existing price for one more billing period. However, if a subscriber actively renews or purchases the subscription directly, the new price applies immediately. Subscribers receive notice of a price change 27 days before the renewal date, and the subscription renews at the new price on the next renewal date. Subscribers who aren't going to renew don't receive a notification. A subscriber in billing retry who repurchases the current plan, or an offer for it, can consent to the higher price and is charged immediately.

[TABLE]

**Note:** Price changes only apply to active subscribers. If a subscription is recovered in the billing retry or grace period state, it will renew at the existing price for one more billing period. 27 days before the renewal date, the subscriber receives notice of the price change, and the subscription renews at the next renewal date at the new price. Subscribers won't receive a notification if the subscription isn't going to renew. If a user in billing retry attempts to restart service by repurchasing the subscription or an offer for the current plan, they can consent to the higher price and will be charged immediately.

To schedule a price increase:

**Note:** If you've configured volume discount tiers for an auto-renewable subscription using the App Store Connect API, you won't be able to view or manage pricing until volume pricing is supported in App Store Connect early next year.

1.  In Apps, select the app you want to view.

2.  In the sidebar, click Subscriptions.

3.  Click an auto-renewable subscription, go to the Subscription Prices section, and click the add button (+).

4.  Click Plan Subscription Price Change, then select the countries or regions where you want to edit pricing.

5.  Choose a start date, country or region, and price, then click Next. To search from a larger list of 800 price points, click See Additional Prices.

    App Store Connect will determine the soonest your price change can be scheduled for based on timezones for your desired date (generally 1 to 2 days in advance.) The time of day your price change goes into effect will [vary by region](/help/app-store-connect/reference/pricing-and-availability/app-store-pricing-and-availability-start-times-by-country-or-region). Ensure you're scheduling your price changes with enough time in advance.

6.  App Store Connect provides comparable prices for all 175 App Store countries and regions, taking into account taxes and foreign exchange rates. If you want to set different prices for specific storefronts, make the changes and click Next.

7.  Choose an option for subscribers paying the current price shown in App Store Connect:

    - **A**: Keep the current price for existing subscribers. Anyone who subscribed before the start date of this price change won’t be affected. Subscribers whose subscription expires can resubscribe at the preserved price within 60 days of expiration.

    &nbsp;

    - **B**: Apply the price change to existing subscribers who are paying the price of your subscription currently displayed on the App Store. App Store Connect will provide an indication if consent is required (or if they'll simply be notified) for each country or region. If you have customer groups that have had their prices preserved and your change is scheduled for the future, keep in mind that circumstances may change and consent will be required based on the conditions of the customer at the time of the increase. you're responsible for ensuring you understand when consent will be required.

8.  Click Next.

9.  View the list of planned price changes.

10. If all of the information is correct, click Confirm.

Once a price increase goes into effect, it can’t be reversed.

## Un-preserve prices for subscribers

**Note:** If you've configured volume discount tiers for this subscription using the App Store Connect API, un-preserving prices in App Store Connect is disabled until volume pricing is supported in App Store Connect early next year. To un-preserve prices for existing subscribers or manage pricing in App Store Connect again, first remove all volume discount tiers using the API.

1.  In Apps, select the app you want to view.

2.  In the sidebar, click Subscriptions.

3.  Click the subscription group name.

4.  Click the subscription reference name.

5.  Scroll down to the Subscription Pricing section and click View all Subscription Pricing.

6.  Click Starting Price.

7.  Click Edit Price.

8.  App Store Connect displays the countries or regions where subscribers currently pay a lower price

9.  Select the countries or regions where you want to increase the price. Click Next.

10. Click Confirm. Any changes you make can’t be reversed.

## View or modify your planned price changes

1.  In Apps, select the app you want to view.

2.  In the sidebar, click Subscriptions.

3.  Click the subscription name, go to the Subscription Prices section, then click View all Subscription Pricing.

4.  View your planned price changes.

    You can download a list of prices customers are currently paying for your auto-renewable subscriptions, as well as a list of upcoming prices. Click Export as CSV.

    **Note:** If you've configured volume discount tiers for this subscription using the App Store Connect API, scheduling a price change in App Store Connect is disabled. A dialog will direct you to manage pricing using the API.

5.  To cancel a scheduled price change, move your pointer over the right side of the price change row until the delete button (—) appears. Click the delete button.

    **Note:** In certain cases, such as upcoming tax or foreign exchange rate adjustments, or when a manually adjusted price is starting or reverting, you may not be able to remove an upcoming price change.

6.  In the dialog that appears, click Delete.

    Click the date to view the set or planned price. If you’ve previously preserved pricing for existing subscribers, the current prices paid by these subscribers and the start date of the prices will also appear.

## FAQs

### How will changes to foreign exchange rates and tax adjustments affect auto-renewable subscription pricing?

Apple will not make price adjustments on your auto-renewable subscription products. Retail price changes initiated by Apple due to tax changes and significant foreign exchange rate movements will exclude auto-renewable subscriptions. For any value-added tax (VAT) rate changes, your proceeds and Apple’s commission will be calculated after the deduction of VAT, which means that your proceeds will change. You can choose to pass any changes caused by taxation or foreign exchange onto your subscribers by adjusting the price for your subscription.

### How do price increases work for multiseat purchases?

For multiseat purchases, Apple evaluates the price of the first seat and the group purchaser's total price, meaning the combined price of all seats, separately. The first seat follows the same criteria described in Consent needed above. Beyond the first seat, consent is required if the group purchaser's total price increases by more than 50%, or if they're located in a country or region that requires consent for any price increase (Visit [Auto-renewable subscription price increase thresholds](/help/app-store-connect/reference/in-app-purchases-and-subscriptions/auto-renewable-subscription-price-increase-thresholds)). If none of these criteria apply, Apple notifies the group purchaser of their new total price with no request for consent, on the same timing shown above. If the purchaser doesn't consent before the first renewal at the higher price, the entire subscription expires at the end of the last renewal cycle at the former price, including all seats.

Changes to your pricing tiers only count as a price increase if they increase what the purchaser pays. If you add, remove, merge, or adjust tiers and the group purchaser's total price stays the same or decreases, Apple notifies them of the change but doesn't request consent, including in countries or regions that require consent for any price increase. Group purchasers who add seats while an increase is scheduled buy those seats at the new price and see their new total before purchasing. If the increase requires consent, completing that purchase counts as consent.
