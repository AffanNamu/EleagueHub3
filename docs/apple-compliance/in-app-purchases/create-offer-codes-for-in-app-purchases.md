<!--
Source: https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/create-offer-codes-for-in-app-purchases
Final URL: https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/create-offer-codes-for-in-app-purchases
Retrieved (UTC): 2026-11-22T04:11:57Z
Raw file: create-offer-codes-for-in-app-purchases.html
SHA-256 of raw: 713a99511be2c5ceb8a269b452a7f98a7f7622be398bdf4a1399ae83b2289b88
Extraction: automated text extraction for offline search; the raw file is authoritative.
-->

[](/help/app-store-connect/)

### App Store Connect Help

[App Store Connect](/help/app-store-connect/) / [Manage In-App Purchases](/help/app-store-connect/manage-in-app-purchases/) / Create offer codes for In-App Purchases

Filter ⌘K

Filter ⌘K

Manage In-App Purchases

# Create offer codes for In-App Purchases

Offer codes provide a way to acquire, retain, and win back customers by offering discounted or free access to In-App Purchases. You create and manage them in App Store Connect, and customers can redeem them through a redemption URL, by entering the code in the App Store, or within your app.

Each app can have up to 10 active offers at a time, with a limit of 1 million codes per app, per quarter. Each customer can redeem one code per offer. You set the eligibility criteria for who can redeem; customers who have never purchased within your app, purchased in the last 30 days, or purchased more than 30 days ago. Selecting all options makes the offer available to everyone. Carefully consider your eligibility requirements before creating and distributing offer codes.

You can create offer codes and sandbox codes regardless of your app's current App Status. To generate one-time-use or custom codes, your app must be Ready for Distribution and the associated In-App Purchase must be Approved.

There are three types of offer codes:

- **One-time-use codes** are unique, randomly generated codes that each customer can redeem only once. They're best suited to small-scale or targeted distributions. For example, giving codes to event attendees, contest winners, or individuals as a special discount. Customers can redeem them through a unique redemption URL, by entering the code in the App Store, or within your app.

- **Custom codes** are codes you name yourself. For example, SUMMER25 or VIPACCESS. Unlike one-time-use codes, a custom code can be redeemed by multiple customers up to a limit you set. They're best suited to large-scale marketing campaigns or promotions targeting specific customer groups. Customers can redeem them through a redemption URL or within your app.

- **Sandbox codes** are one-time-use codes for testing. Use them to verify your offer code redemption flow in the sandbox environment without affecting real users or production data. Each app can distribute up to 10,000 sandbox codes per quarter, and sandbox test accounts have no redemption limits. If redemptions are blocked, clear the purchase history for the sandbox Apple account and retest.

You can create offer codes and sandbox codes for your app regardless of its current App Status. However, to generate custom or unique offer codes, your app must be Ready for Distribution, and the associated In-App Purchase must be Approved.

Carefully consider your offer's eligibility requirements before creating and distributing offer codes.

[TABLE]

**Note:** Redemption within your app for one-time-use and custom codes requires customers to use a device running iOS 16.3, macOS 15.0, or visionOS 1.0 or later, and your app must support the appropriate [StoreKit method](https://developer.apple.com/documentation/storekit/supporting-offer-codes-in-your-app#Redeem-offer-codes-in-your-app).

**Required role:** Account Holder, Admin, App Manager, or Marketing. [View role permissions.](/help/app-store-connect/reference/account-management/role-permissions)

## Set up offers

1.  From Apps, select your app.

2.  In the sidebar, click In-App Purchases.

3.  Click the In-App Purchase you want to create an offer for.

4.  Scroll down to the Offer Codes section and click Create Offer (or scroll down to the Non-Renewing Subscriptions section and click Manage, then click Create).

5.  Enter a reference name for the offer. Use this reference name to manage the offer in App Store Connect. After you’ve created your offer, the reference name can't be changed.

    **Note:** You can't use a reference name that has already been used for another offer in the same app.

6.  Select the customer eligibility for your offer, based on their In-App Purchase history within your app. You can select one or more of the following:

    - Never purchased within your app.

    - Purchased within your app in the last 30 days.

    - Purchased within your app more than 30 days ago.

    Selecting all of the options will make your offer available to everyone.

7.  Click Next.

8.  Select the countries or regions where you want to make your offer available, then click Next.

9.  Choose Paid Offer or Free Offer.

10. Choose the discounted price for a base country or region, then click Next. To search from a larger list of price points, click See Additional Prices.

11. App Store Connect provides comparable prices for all 175 App Store countries and regions, taking into account taxes and foreign exchange rates. If you want to set different prices for specific storefronts, make the changes and click Next.

12. Make sure the details of your offer are correct and click Confirm.

    **Note:** Once you create an offer, you won’t be able to edit it. If changes to customer eligibility are needed, create a new offer.

### Create one-time use codes

In order for customers to redeem codes, your app must be in the Ready for Distribution state.

1.  From Apps, select your app.

2.  In the sidebar, click In-App Purchases.

3.  Choose the In-App Purchase you wish to create codes for.

4.  Scroll down to the Offers Codes section and locate your offer in the list.

5.  Click the reference name.

6.  In the One-Time Use Codes section, click the Create One-Time Use Codes button.

7.  Click the “Create One-Time Use Codes” button.

8.  In the pop-up window, select the number of codes you want to create.

    You must select a minimum of 500 and a maximum of 25,000. If you need more than 25,000 codes, you can create multiple batches of codes for the same offer.

9.  Choose an expiration date to determine how long the codes are valid. One-time use codes can be valid for a maximum of six months. Codes expire at 12:00 a.m. PT on the expiration date.

10. Click Create.

    It may take up to an hour before codes are redeemable by customers.

### Download one-time use codes

Once your one-time use codes are created, you’ll need to download them from App Store Connect so you can share them.

1.  From Apps, select your app.

2.  In the sidebar, click In-App Purchases (or Non-renewing subscriptions).

3.  Choose the In-App Purchase you wish to create codes for.

4.  Scroll down to the Offers Codes section and locate your offer in the list.

5.  Click the reference name.

6.  Locate the codes you want to download and click Download.

7.  Open the extracted text (`.csv`) file in a spreadsheet application.

### Create custom codes

1.  From Apps, select your app.

2.  In the sidebar, click In-App Purchases.

3.  Choose the In-App Purchase you wish to create codes for.

4.  Scroll down to the Offers Codes section and locate your offer in the list.

5.  Click the reference name.

6.  Select the offer from the list.

7.  In the Custom Codes section, click the Create Custom Codes button.

8.  Enter a custom code up to 64 characters and without any special characters.

9.  Choose a redemption limit. This is the total number of people who can redeem this custom code. You can choose a limit of up to 25,000 at a time. If you need more, use the same custom code multiple times for the same offer.

10. Choose an expiration date to determine how long the codes will be valid (with a maximum of 6 months for codes with an expiration date). Codes expire at 12:00 a.m. PT on the expiration date.

    To create codes with no expiration date, choose No End Date from the date picker. Expiration dates can't be edited.

    **Note:** To extend a custom code's availability, create a new batch using the same code and a later expiration date. The system always redeems from the earliest non-expired batch first, so codes from both batches remain redeemable until each expires or reaches its redemption limit. To stop the original batch from being redeemed, deactivate it before creating the new one.

11. Click Create.

    It may take up to an hour before codes are redeemable by customers.

### Create sandbox codes

Sandbox codes are one-time use codes for testing purposes. You can test offer redemptions through your sandbox account settings on iOS 16.3 and iPadOS 16.3 or later, and if your app supports the required StoreKit APIs. [Learn more.](https://developer.apple.com/documentation/storekit/supporting-subscription-offer-codes-in-your-app)

1.  From Apps, select your app.

2.  In the sidebar, click In-App Purchases (or Non-renewing subscriptions).

3.  Choose the In-App Purchase you wish to create sandbox codes for.

4.  Scroll down to the Offers Codes section and locate your offer in the list.

5.  Click the reference name.

6.  In the Sandbox Codes section, click the Create Sandbox Codes button.

7.  In the pop-up window, choose the number of codes you want to create. You must select a minimum of 10 and a maximum of 10,000 codes.

8.  Optionally, choose an expiration date to determine how long the codes are valid. Sandbox codes can be valid for a maximum of six months. Codes expire at 12:00 a.m PT on the expiration date.

### Deactivate offer codes

1.  From Apps, select your app.

2.  In the sidebar, click In-App Purchases.

3.  Choose the In-App Purchase you wish to deactivate codes for.

4.  Scroll down to the Offers Codes section and locate your offer in the list.

5.  Click the reference name.

6.  Locate the offer you want to deactivate and click Deactivate.

7.  Click Deactivate again to proceed.

    The codes will expire immediately. Subscribers who have already redeemed the codes won’t be affected. Unredeemed codes will also expire and will not be reapplied to the quarterly limit.
