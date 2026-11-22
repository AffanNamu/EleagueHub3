<!--
Source: https://developer.apple.com/help/app-store-connect/configure-in-app-purchase-settings/generate-a-shared-secret-to-verify-receipts
Final URL: https://developer.apple.com/help/app-store-connect/configure-in-app-purchase-settings/generate-a-shared-secret-to-verify-receipts
Retrieved (UTC): 2026-11-22T04:11:57Z
Raw file: generate-a-shared-secret-to-verify-receipts.html
SHA-256 of raw: 9c6e7b6eab1b58490a0d37dff7d83f8f93ac1654b857170800769b7332aad465
Extraction: automated text extraction for offline search; the raw file is authoritative.
-->

[](/help/app-store-connect/)

### App Store Connect Help

[App Store Connect](/help/app-store-connect/) / Configure In-App Purchase settings / Generate a shared secret to verify receipts

Filter ⌘K

Filter ⌘K

Configure In-App Purchase settings

# Generate a shared secret to verify receipts

Include a shared secret in your request to verify App Store subscription or In-App Purchase receipts to increase security between your server and Apple's servers.

A shared secret is a 32-character hexadecimal string generated in App Store Connect. You may generate a primary shared secret, which is a single code for all your apps, or an app-specific shared secret for individual apps. You may also use a primary shared secret for some of your apps, and an app-specific shared secret for others.

The verifyReceipt endpoint is deprecated. To validate In-App Purchases on your server without using receipts, use the App Store Server API instead. For more information, visit [Validating Receipts with the App Store](https://developer.apple.com/documentation/storekit/original_api_for_in-app_purchase/validating_receipts_with_the_app_store).

**Required role:** Account Holder or Admin. [View role permissions.](/help/app-store-connect/reference/account-management/role-permissions)

## View or generate a shared secret for all your apps (primary shared secret)

1.  Select Users and Access at the top of the page.

2.  Click the Integrations tab.

3.  In the sidebar, under Keys, click Shared Secret.

4.  Click Generate Primary Shared Secret.

5.  Copy the code and use it for your transactions receipt for all of your apps with In-App Purchases.

### View or generate a shared secret for an individual app (app-specific shared secret)

Access the app-specific shared secret in the Subscriptions page of your app. You may want to use an app-specific shared secret if you want to keep this code private for this app, or if you're planning to transfer this app to another developer account.

**Note:** App-specific shared secrets can’t be deleted, only regenerated.

1.  In Apps, select the app you want to view.

2.  In the sidebar, under General, click App Information.

3.  In the App-Specific Shared Secret section, click Manage.

    ![In-App Purchase app-specific shared secret](/help/app-store-connect/configure-in-app-purchase-settings/generate-a-shared-secret-to-verify-receipts/images/In-App-Purchase-AppSpecificSharedSecret_2x.png)

4.  You can generate a shared secret for individual apps, or regenerate a shared secret.

    **Note:** Clicking Regenerate will automatically generate a new shared secret, and any previously generated shared secret for this app will be invalidated.

5.  Then click Done.

6.  To generate a shared secret, click Generate or Regenerate in the dialog.

7.  Copy the code and use it for your transactions receipt for this app.

When you regenerate an app-specific shared secret, use the new value to verify your In-App Purchases for this app.

### Transitioning to a new shared secret

When you regenerate or change a shared secret, expect a transition period of up to 24 hours before the new shared secret takes effect. During this transition period, do the following:

- To change to using an app-specific shared secret from using a primary shared secret, fall back to using the primary shared secret until using the new app-specific shared secret succeeds.

- To refresh a primary shared secret, fall back to the old primary shared secret until using the new primary shared secret succeeds.
