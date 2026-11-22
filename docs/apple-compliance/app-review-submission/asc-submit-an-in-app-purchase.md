<!--
Source: https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase
Final URL: https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase
Retrieved (UTC): 2026-11-22T04:11:57Z
Raw file: asc-submit-an-in-app-purchase.html
SHA-256 of raw: 36d89d7419b5c4f58debf4ff7dd4a2439bc6792d3dd3491951fda304149f0b53
Extraction: automated text extraction for offline search; the raw file is authoritative.
-->

[](/help/app-store-connect/)

### App Store Connect Help

[App Store Connect](/help/app-store-connect/) / Manage submissions to App Review / Submit an In-App Purchase

Filter ⌘K

Filter ⌘K

Manage submissions to App Review

# Submit an In-App Purchase

You can submit In-App Purchases and subscriptions for review directly from the In-App Purchases and Subscriptions sections in App Store Connect. Items you add for review are collected in a submission, which you can submit with or without an app version.

**Note:** The first consumable, non-consumable, auto-renewable subscription, and non-renewing subscription In-App Purchase of each type must be submitted with a new app version. After the first item of a given type is approved, you can submit additional items of that type without a new app version, as long as your app has at least one approved app version at the time of submission. If your app doesn't have an approved version, include one in your next submission.

Learn how to submit [In-App Purchases](https://developer.apple.com/documentation/appstoreconnectapi/app_store/in-app_purchase/in-app_purchase_submissions) and [subscriptions](https://developer.apple.com/documentation/appstoreconnectapi/app_store/auto-renewable_subscriptions/submitting_subscriptions_and_subscription_groups_for_app_review) with the App Store Connect API.

**Required role:** Account Holder, Admin, or App Manager. [View role permissions.](/help/app-store-connect/reference/account-management/role-permissions)

## Submit an In-App Purchase for the first time

After creating your In-App Purchase or subscription, click Add for Review to add it to a submission. If this is the first time you're submitting that type of In-App Purchase or subscription, include a new app version in the submission. If you're submitting a new subscription it must be submitted together with its subscription group. Each new subscription group must be submitted with at least one of its subscriptions. The app version, subscription group, and every subscription or In-App Purchase you want reviewed together must all be added to the same draft submission before you click Submit for Review.

1.  In Apps, select the app you want to view.

2.  In the sidebar under Monetization, click In-App Purchases or Subscriptions.

3.  Click the In-App Purchase or subscription you want to submit.

4.  Click Add for Review. If you have an existing submission, you can add the item to it or click Create New Submission.

5.  If your In-App Purchase or subscription requires a new app version, select a platform and the app version to include in your submission. If you're submitting a subscription and the subscription group hasn't been approved yet, add the subscription group to the submission as well. You can add up to 200 items per submission at a time.

6.  In the submission modal, review the items in your submission and click Submit for Review.

Once your first consumable or non-consumable In-App Purchase has been approved, you can add additional In-App Purchases of that type without including an app version. The same applies for auto-renewable and non-renewing subscriptions.

**Note:**

- In-App Purchases with content hosting can no longer be submitted for review. You can still make changes to their pricing and availability.

- In-App Purchases and subscriptions aren't supported on Apple Watch. To submit an Apple Watch app version, remove all in-app purchases and subscriptions from the submission.

### Add In-App Purchases or subscriptions to an existing submission

You can add multiple In-App Purchases or subscriptions to a submission at the same time from the In-App Purchases or Subscriptions page.

1.  In Apps, select the app you want to view.

2.  In the sidebar under Monetization, click In-App Purchases or Subscriptions.

3.  Click Edit. For subscriptions, first select a group, then click Edit.

4.  Select the items you want to submit.

5.  Click Add for Review. When you click Add for Review, a dropdown appears if there are any existing draft submissions. Select an existing submission to add an item to it, or click Create New Submission to start a new one.

6.  If any items can't be added to the submission, a banner identifies which items weren't added and includes a link to each item. You can add up to 200 items per submission at a time.

### View your submissions and submission history

The App Review section of the sidebar shows all your In-App Purchase and subscription submissions in one place — both active submissions and a history of completed ones.

1.  In Apps, select the app you want to view.

2.  In the sidebar, click App Review. Draft submissions appear under Drafts, showing the date created, platform, number of items, and status. All other submissions appear under Submissions. App Store Connect shows your last 10 completed submissions from the past 180 days.

3.  Click a submission to view its details. If App Review rejected any items, the reason and relevant guideline citation appear under Messages. You can reply to App Review directly from the submission detail page.

### Resolve and resubmit a rejected In-App Purchase or subscription

If App Review rejects one or more items in a submission, you can edit each rejected item and update the submission before resubmitting for review.

1.  In Apps, select the app you want to view.

2.  In the sidebar, click App Review and open the submission.

3.  Review the rejection reason in the Messages section and make the necessary changes by clicking Edit next to the rejected item.

4.  Click Save.

5.  Click Update Review to update the item in the submission.

6.  Repeat steps 3–6 for any other rejected items in the submission, or remove them from the submission.

7.  Once all rejected items are resolved or removed, click Resubmit to App Review.

**Note:** If you haven't been contacted by Apple with more information about the rejection, you can inquire through [Contact Us](/support).
