<!--
Source: https://developer.apple.com/help/app-store-connect/configure-in-app-purchase-settings/enter-server-urls-for-app-store-server-notifications
Final URL: https://developer.apple.com/help/app-store-connect/configure-in-app-purchase-settings/enter-server-urls-for-app-store-server-notifications
Retrieved (UTC): 2026-11-22T04:11:57Z
Raw file: enter-server-urls-for-app-store-server-notifications.html
SHA-256 of raw: bf9928bfef00471ce3fc0c2b3e8fe60bab6c4fde502cd015fc25a2ba12b74800
Extraction: automated text extraction for offline search; the raw file is authoritative.
-->

[](/help/app-store-connect/)

### App Store Connect Help

[App Store Connect](/help/app-store-connect/) / Configure In-App Purchase settings / Enter server URLs for App Store Server Notifications

Filter ⌘K

Filter ⌘K

Configure In-App Purchase settings

# Enter server URLs for App Store Server Notifications

App Store Server Notifications provide information about key events related to your In-App Purchases, such as changes to a subscription's status or the refund of an In-App Purchase. In order to receive these notifications from the App Store, you must provide a URL in App Store Connect that links to your server. You can enter URLs for both production and sandbox endpoints.

To receive App Store Server Notifications, configure your server and visit [Enabling App Store Server Notifications](https://developer.apple.com/documentation/appstoreservernotifications/enabling-app-store-server-notifications). For more details on notifications and their meanings, see the [App Store Server Notifications](https://developer.apple.com/documentation/appstoreservernotifications).

**Note:** It may take up to 1 hour for changes you make to product metadata to appear in the sandbox environment.

**Required role:** Account Holder, Admin, App Manager, or Marketing. [View role permissions.](/help/app-store-connect/reference/account-management/role-permissions)

## Enter a production URL for App Store Server Notifications

1.  In Apps, select the app you want to view.

2.  In the sidebar, under General, click App information.

3.  Scroll down to General Information, then go to App Store Server Notifications.

4.  Under Production Server URL, click Set Up URL.

    ![App Store Server Notifications section on the App Information page. An arrow points to the 'Set Up URL' link for Production Server URL.](/help/app-store-connect/configure-in-app-purchase-settings/enter-server-urls-for-app-store-server-notifications/images/prod-server-notifications_2x.png)

5.  Enter the URL that you've determined for App Store Server Notifications.

6.  Choose either Version 1 (deprecated) or Version 2 notifications. [Learn about versions of App Store Server Notifications](https://developer.apple.com/documentation/appstoreservernotifications/app_store_server_notifications_changelog).

7.  Click Save.

### Enter a URL for testing App Store Server Notifications in a Sandbox environment

If you do not provide a Sandbox URL in App Store Connect, please note that the App Store will automatically send notifications for both environments to the Production URL provided. If you only provide a Sandbox URL, no notifications will be sent in production.

1.  In Apps, select the app you want to view.

2.  In the sidebar, under General, click App information.

3.  Scroll down to General Information, then go to App Store Server Notifications.

4.  Under Sandbox Server URL, click Set Up URL.

    ![App Store Server Notifications section on the App Information page. An arrow points to the 'Set Up URL' link for Sandbox Server URL.](/help/app-store-connect/configure-in-app-purchase-settings/enter-server-urls-for-app-store-server-notifications/images/sandbox-server-notifications_2x.png)

5.  Enter the URL that you've determined for App Store Server Notifications.

6.  Choose either Version 1 (deprecated) or Version 2 notifications. [Learn about versions of App Store Server Notifications](https://developer.apple.com/documentation/appstoreservernotifications/app_store_server_notifications_changelog).

7.  Click Save.

### Edit your URL for App Store Server Notifications

1.  In Apps, select the app you want to view.

2.  In the sidebar, under General, click App information.

3.  Scroll down to General Information, then go to App Store Server Notifications.

4.  Next to the URL you want to edit, click Edit.

5.  Enter the desired URL and click Save.

**Related** [App Store Server Notifications](https://developer.apple.com/documentation/appstoreservernotifications/) [Choosing a Receipt Validation Technique](https://developer.apple.com/documentation/storekit/in-app_purchase/choosing_a_receipt_validation_technique#//apple_ref/doc/uid/TP40010573) [In-App Purchase](/documentation/storekit/in-app_purchase)
