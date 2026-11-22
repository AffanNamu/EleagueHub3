<!--
Source: https://developer.apple.com/help/app-store-connect/reference/in-app-purchases-and-subscriptions/in-app-purchase-statuses
Final URL: https://developer.apple.com/help/app-store-connect/reference/in-app-purchases-and-subscriptions/in-app-purchase-statuses
Retrieved (UTC): 2026-11-22T04:11:57Z
Raw file: in-app-purchase-statuses.html
SHA-256 of raw: 36047134a7b142b953231e7a365070aa5600be1aa356919bfa5e2e4d93921b58
Extraction: automated text extraction for offline search; the raw file is authoritative.
-->

[](/help/app-store-connect/)

### App Store Connect Help

[App Store Connect](/help/app-store-connect/) / Reference / [In-App Purchases and subscriptions](/help/app-store-connect/reference/in-app-purchases-and-subscriptions/) / In-App Purchase statuses

Filter ⌘K

Filter ⌘K

Reference

# In-App Purchase statuses

The In-App Purchase status indicates whether your In-App Purchase is available or if it needs your attention. A red status indicator means that you need to take action before the product can be made available. A yellow status indicator means that a process controlled by you or Apple is ongoing. A green status indicator means that the In-App Purchase is available.

- A red status indicator (![](/help/images/icons/status-red-icon_2x.png)) means that you need to perform some action before a product can be made available.

- A yellow status indicator (![](/help/images/icons/status-yellow-icon_2x.png)) means that some process is ongoing, controlled either by you or by Apple.

- A green status indicator (![](/help/images/icons/status-green-icon_2x.png)) means that the In-App Purchase is available.

| Status                                                                     |     |     |     | Description                                                                                                                                                                                                                                                                             |     |     |     |     |     |     |     |
|----------------------------------------------------------------------------|-----|-----|-----|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----|-----|-----|-----|-----|-----|-----|
| ![](/help/images/icons/status-yellow-icon_2x.png) Prepare for Submission   |     |     |     | Your In-App Purchase has been created, but you haven't yet submitted it for review. Use Add for Review to add it to a submission. If your In-App Purchase is missing required metadata, complete it before adding for review.                                                           |     |     |     |     |     |     |     |
| ![](/help/images/icons/status-yellow-icon_2x.png) Ready for Review         |     |     |     | Your In-App Purchase has been added to a submission, but you haven't sent the submission to App Review yet. While your product is in this state, you can edit only the reference name, pricing, and availability.                                                                       |     |     |     |     |     |     |     |
| ![](/help/images/icons/status-yellow-icon_2x.png) Waiting for Review       |     |     |     | You have submitted your In-App Purchase to be reviewed by Apple. While your product is in this state, you can edit only the reference name, pricing, and availability.                                                                                                                  |     |     |     |     |     |     |     |
| ![](/help/images/icons/status-yellow-icon_2x.png) In Review                |     |     |     | Your In-App Purchase is currently being reviewed by Apple. While your product is in this state, you can edit only the reference name, pricing, and availability.                                                                                                                        |     |     |     |     |     |     |     |
| ![](/help/images/icons/status-green-icon_2x.png) Accepted                  |     |     |     | Your In-App Purchase has been accepted, but one or more other items in the same submission were rejected. Your In-App Purchase won't be approved until all items in the submission are accepted. You can edit the rejected items and resubmit them, or remove them from the submission. |     |     |     |     |     |     |     |
| ![](/help/images/icons/status-green-icon_2x.png) Approved                  |     |     |     | Apple has approved your In-App Purchase. For this status to appear, you must provide country or region availability for your In-App Purchase. If you select "Remove from Sale," the status appears as "Developer Removed from Sale."                                                    |     |     |     |     |     |     |     |
| ![](/help/images/icons/status-red-icon_2x.png) Rejected                    |     |     |     | Apple has rejected your In-App Purchase during the review process. You can edit the item and use Update Review to resubmit it. If you haven't been contacted by Apple with more information about the rejection, you can inquire through [Contact Us](/support/).                       |     |     |     |     |     |     |     |
| ![](/help/images/icons/status-red-icon_2x.png) Developer Rejected          |     |     |     | You removed your In-App Purchase from review. When you're ready, use Add for Review to resubmit it.                                                                                                                                                                                     |     |     |     |     |     |     |     |
| ![](/help/images/icons/status-red-icon_2x.png) Developer Removed from Sale |     |     |     | You removed the In-App Purchase from sale. Customers who already purchased it retain access. Those transactions are available with StoreKit and in the App Store Server API. To make the In-App Purchase available for sale again, update its availability settings.                    |     |     |     |     |     |     |     |
| ![](/help/images/icons/status-red-icon_2x.png) Removed from Sale           |     |     |     | Apple removed this In-App Purchase from sale.                                                                                                                                                                                                                                           |     |     |     |     |     |     |     |

**Related** [In-App Purchase information](/help/app-store-connect/reference/in-app-purchases-and-subscriptions/in-app-purchase-information) [Set availability for In-App Purchases](/help/app-store-connect/manage-in-app-purchases/set-availability-for-in-app-purchases) [Schedule price changes for In-App Purchases](/help/app-store-connect/manage-in-app-purchases/schedule-price-changes-for-in-app-purchases)
