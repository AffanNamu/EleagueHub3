<!--
Source: https://developer.apple.com/help/app-store-connect/manage-subscriptions/offer-auto-renewable-subscriptions
Final URL: https://developer.apple.com/help/app-store-connect/manage-subscriptions/offer-auto-renewable-subscriptions
Retrieved (UTC): 2026-11-22T04:11:57Z
Raw file: offer-auto-renewable-subscriptions.html
SHA-256 of raw: 5cb721ad8890d1ee693c7203bf83a9bb93ba086c662b0d055fc5ad9ac3d97f97
Extraction: automated text extraction for offline search; the raw file is authoritative.
-->

[](/help/app-store-connect/)

### App Store Connect Help

[App Store Connect](/help/app-store-connect/) / Manage subscriptions / Offer auto-renewable subscriptions

Filter ⌘K

Filter ⌘K

Manage subscriptions

# Offer auto-renewable subscriptions

App Store Connect offers tools to help you run a subscription business on the App Store. How you configure your subscriptions in App Store Connect determine how users subscribe to your service, how often they are billed, and how they upgrade and downgrade between offerings. To begin offering a subscription in your app, you will need to create a Subscription Group, then add one or more Subscription products to that group, then assign levels to those products. Subscription setup is structured as the following:

- **Subscription group:** A set of subscription products with varying levels and durations. You can have up to 100 subscriptions per group. Users can subscribe to one subscription product per group at a time.

- **Subscription:** A product that lets users purchase dynamic content for a set period. Auto-renewable subscriptions renew automatically, unless cancelled by the user. Subscription duration and price is configured in App Store Connect.

- **Subscription levels:** A ranking system of subscriptions within a subscription group that determines the upgrade, downgrade, and crossgrade path available to subscribers. Levels make it possible to offer varying access (basic, premium) of the same service.

- **Subscription duration:** The length of time before the subscription renews and the subscriber is charged. Possible durations are 1 week, 1 month, 2 months, 3 months, 6 months, and 1 year.

## Single subscription product setup

If you offer only one subscription product in your app, the subscription defaults to a single level within the subscription group.

![MacBook Pro screen with a subscription page for an app called Ocean Journal. The page shows the App Store Connect navigation menu at the top and the Subscriptions page below with one available subscription option listed.](/help/app-store-connect/manage-subscriptions/offer-auto-renewable-subscriptions/images/InApp-OfferAutoRenew-Single_2x.png)

## Multiple subscription and durations product setup

Arrange your subscriptions in order from the one that offers the most (level 1) to the one that offers the least. You can stack subscriptions with equal content but different durations and other similar variables, at the same level. Each level can have multiple subscription products, offering multiple durations and prices for people to choose from. This lets them upgrade, downgrade, and crossgrade within the subscription group without impacting their days of paid service.

![A MacBook Pro screen and a mobile phone screen. The screens show a subscription page for an app called Ocean Journal. The page shows the App Store Connect navigation menu at the top and the Subscriptions page below with one available subscription option listed.](/help/app-store-connect/manage-subscriptions/offer-auto-renewable-subscriptions/images/InApp-OfferAutoRenew-Multi_2x.png)

## Subscription proceeds rate

During a subscriber’s first year of service, you receive 70% of the subscription price at each billing cycle, minus applicable taxes. After a subscriber accumulates one year of paid service in the same subscription group, your net revenue increases to 85% of the subscription price, minus applicable taxes. Time spent within a subscription offer is also counted toward the total. Members of the [App Store Small Business Program](/app-store/small-business-program/) receive 85% starting on the first day.

When an auto-renewable subscription expires, the days of paid service stop accumulating. If someone resubscribes or the subscription is recovered within 60 days, the days of paid service continue from the recovery date. Conversely, if the subscription is recovered after 60 days, the rate reverts to 70% and the day count starts over.

When a subscription expires due to a billing issue, Apple attempts to renew the subscription and collect payment. If you enabled the billing grace period for your apps, there won’t be any interruption to days of paid service or to your revenue, if Apple is able to recover the subscription within the billing grace period (either 6 or 16 days, depending on the subscription duration). [Learn more about billing grace periods.](/help/app-store-connect/manage-subscriptions/enable-billing-grace-period-for-auto-renewable-subscriptions)

For subscription performance, subscriber activity, and proceeds in your Sales and Trends reports, visit [view subscription data](/help/app-store-connect/view-sales-and-trends/view-subscription-data).

**Note:** It may take up to 1 hour for changes you make to product metadata to appear in the sandbox environment.

**Required role:** Account Holder, Admin, App Manager, Developer, or Marketing. [View role permissions.](/help/app-store-connect/reference/account-management/role-permissions)

### Create a subscription group

To offer subscriptions within your app, you must first create a subscription group in App Store Connect. When you create subscription products, you'll be able to add these products to the subscriptions group. Before creating subscriptions, ensure that you understand the right subscription setup for your business model. [Learn about offering subscriptions.](/app-store/subscriptions/)

1.  In the sidebar, under Monetization, click Subscriptions.

2.  Click the add button (+).

3.  Enter a reference name.

4.  Click Create

    ![Subscriptions page showing Subscription Groups section displays a plus (+) button for adding new groups. A single subscription group is currently listed in the section.](/help/app-store-connect/manage-subscriptions/offer-auto-renewable-subscriptions/images/InApp-subscriptions-mainpg_2x.png)

### Create an additional subscription group

A subscription group contains all the variations of a single subscription product — for example, monthly and annual plans for the same service, or basic and premium tiers. Customers can only hold one active subscription per group at a time. Create additional subscription groups only when your app offers separate subscription products that customers can purchase at the same time.

**Note:** Since users can only buy one subscription within a group at a time, creating a single group is the best practice for most apps, as it prevents people from accidentally purchasing multiple subscriptions. Users who buy subscriptions in multiple groups are billed separately for each subscription.

1.  In the sidebar, under Monetization, click Subscriptions.

2.  Click the add button (+).

3.  Read and acknowledge the warning by selecting the checkbox and clicking Next.

    **Note:** You’ll only be prompted with a warning when creating your second subscription group.

    ![Create an Additional Subscription Group? dialog with the I understand, create additional subscription group checkbox selected. Buttons for navigation include Cancel and Next.](/help/app-store-connect/manage-subscriptions/offer-auto-renewable-subscriptions/images/InApp-Subs-addsub-checkbox_2x.png)

4.  Enter the reference name for the new group.

5.  Click Create.

### Delete subscriptions and groups

You can delete a subscription group only if it contains no subscriptions. Delete all subscriptions within the group first, then delete the group itself.

To delete a subscription:

1.  In the sidebar, under Monetization, click Subscriptions.

2.  Click the subscription group containing the subscription you want to delete.

3.  Click the subscription you want to delete.

4.  Scroll to the bottom of the page, click Delete Subscription and confirm in the dialog that appears.

To delete a subscription group:

1.  In the sidebar, under Monetization, click Subscriptions.

2.  Click the subscription group you want to delete.

3.  Scroll to the bottom of the page, click Delete Subscription Group and confirm in the dialog that appears.

### Add subscription products

1.  In the Sidebar, under Monetization, click Subscriptions.

2.  Click a subscription group name.

3.  Click Create.

    **Note:** If you're adding a subscription to a group that already has existing subscriptions, you'll click the add button (+).

    ![Subscriptions page showing a ‘Create’ button in the Subscriptions section.](/help/app-store-connect/manage-subscriptions/offer-auto-renewable-subscriptions/images/InApp-Subscription-CreateNew_2x.png)

4.  Enter the subscription’s reference name and Product ID, then click Create. Once you've created your subscription product, you'll be taken to its information page to add more details.

    ![Create Subscription dialog with fields for Reference Name and Product ID, and Cancel and Create buttons.](/help/app-store-connect/manage-subscriptions/offer-auto-renewable-subscriptions/images/InApp-Subscription-CreateNew2_2x.png)

5.  Click Create.

    **Note:** In order to offer a monthly subscription with a 12 month commitment for subscriptions outside the United States and Singapore, select a duration of 1 year. [Learn how to offer subscriptions with a 12 month commitment.](/help/app-store-connect/manage-subscriptions/set-availability-for-an-auto-renewable-subscription#offer-monthly-subscriptions-with-12-month-commitment)

6.  Under Subscription Duration, choose a duration and click Save.

    ![Create Subscription dialog with the Subscription Duration pop-up menu open, showing duration options.](/help/app-store-connect/manage-subscriptions/offer-auto-renewable-subscriptions/images/InApp-Subscription-CreateNew3_2x.png)

7.  Under Subscription Prices, set a price.

    ![Subscription Price dialog with pop-up menus for Currency and Price, and Cancel and Next buttons.](/help/app-store-connect/manage-subscriptions/offer-auto-renewable-subscriptions/images/InApp-Subscription-CreateNew4_2x.png)

8.  Under Availability, select which countries or regions you want to make your subscription available in.

9.  Under Review Information, provide any additional information that may help the App Review team review your In-App Purchase.

    ![Review Information section showing the Screenshot upload area and Review Notes field.](/help/app-store-connect/manage-subscriptions/offer-auto-renewable-subscriptions/images/InApp-Subscription-CreateNew5_2x.png)

10. Optionally, enable [Family Sharing](/help/app-store-connect/configure-in-app-purchase-settings/turn-on-family-sharing-for-in-app-purchases), edit the [subscription’s tax category](/help/app-store-connect/configure-in-app-purchase-settings/set-a-tax-category-for-in-app-purchases), and add localizations.

    ![Subscription Information page showing the Family Sharing section with an option to turn on Family Sharing.](/help/app-store-connect/manage-subscriptions/offer-auto-renewable-subscriptions/images/InApp-Subscription-CreateNew6_2x.png)

11. Click Save.

    **Note:**

    - If you'd like your subscription to be accessible from more than one app, create an equivalent subscription product for each app. [Learn how to offer subscriptions across multiple apps](https://developer.apple.com/documentation/storekit/in-app_purchase/offering_a_subscription_across_multiple_apps).

    - Your first auto-renewable subscription must be submitted with a new app version. Your first subscription group must also be submitted with a new app version and must include an auto-renewable subscription in the same submission. After creating your subscription group and subscription product, select Add for Review on the subscription detail page to submit it for review. Once your first auto-renewable subscription has been approved, you can submit additional auto-renewable subscriptions without a new app version. [Learn more about submitting subscriptions for review.](/help/app-store-connect/manage-submissions-to-app-review/overview-of-submitting-for-review)

### Assign subscription levels

Once you create a subscription product, you can add subscription group information and set subscription levels. These levels determine the upgrades, downgrades, and crossgrades available within a group.

You don’t have to assign multiple levels. You can choose to offer a single subscription product or offer multiple subscription products and assign them all to the same level within a group. Learn about setting up subscription groups and ensure that you understand the right level setup for your business model.

1.  In Apps, select the app you want to view.

2.  In the sidebar, under Monetization, click Subscriptions.

3.  Click the subscription group you want to edit.

4.  To set subscription levels, click Edit Order.

5.  In the window that opens, click the reordering control on the left of the subscription name and drag it to a new position to change the subscriptions’ level.

6.  Click Save.

    ![Edit Subscription Order page listing subscriptions with their names, durations, and reorder controls, with Cancel and Save buttons.](/help/app-store-connect/manage-subscriptions/offer-auto-renewable-subscriptions/images/InApp-Assign-SubLevels_2x.png)

### Add localizations

You can add languages and enter localized metadata for your auto-renewable subscriptions and subscription groups. For a list of supported languages, visit [App Store localizations](/help/app-store-connect/reference/app-information/app-store-localizations). Subscription group localizations and subscription localizations are reviewed independently from your In-App Purchase submission. For the properties you can localize, visit [Required, localizable, and editable properties](/help/app-store-connect/reference/app-information/required-localizable-and-editable-properties). For a detailed example visit [Localize app information](/help/app-store-connect/manage-app-information/localize-app-store-information).

**Important:** You can manage languages only when the [app status is editable](/help/app-store-connect/reference/app-information/app-and-submission-statuses).

### Add subscription group localizations

In each localization, you can customize subscription group names and app display options. Users will see these names when they manage subscriptions on their devices.

1.  In Apps, select the app you want to view.

2.  In the sidebar, under Monetization, click Subscriptions.

3.  Click the subscription group name.

4.  In the Display Name and Description section, click Add.

5.  Follow the prompts to select localizations and enter localized subscription group display names and descriptions.

6.  Click Add.

### Add subscription localizations

The localized display name and description for your subscription appear to each customer could be impacted by certain factors, such as the language of the App Store for their location and the language settings on their device.

[Learn about App Store localization.](/help/app-store-connect/reference/app-information/app-store-localizations)

1.  In Apps, select the app you want to view.

2.  In the sidebar, under Monetization, click Subscriptions.

3.  Click the subscription group name.

4.  Select the subscription.

5.  In the Display Name and Description section, click Add.

6.  Follow the prompts to select localizations and enter localized subscription group display names and descriptions.

7.  Click Add.

**Related** [Manage pricing for auto-renewable subscriptions](/help/app-store-connect/manage-subscriptions/manage-pricing-for-auto-renewable-subscriptions) [Create consumable or non-consumable In-App Purchases](/help/app-store-connect/manage-in-app-purchases/create-consumable-or-non-consumable-in-app-purchases)
