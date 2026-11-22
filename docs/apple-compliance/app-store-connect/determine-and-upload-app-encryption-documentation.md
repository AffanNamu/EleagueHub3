<!--
Source: https://developer.apple.com/help/app-store-connect/manage-app-information/determine-and-upload-app-encryption-documentation
Final URL: https://developer.apple.com/help/app-store-connect/manage-app-information/determine-and-upload-app-encryption-documentation
Retrieved (UTC): 2026-11-22T04:11:57Z
Raw file: determine-and-upload-app-encryption-documentation.html
SHA-256 of raw: 82873a4d13021e27bb0caa35caeb844b8a56e6f7465b34a7d07604612885285d
Extraction: automated text extraction for offline search; the raw file is authoritative.
-->

[](/help/app-store-connect/)

### App Store Connect Help

[App Store Connect](/help/app-store-connect/) / Manage app information / Determine and upload app encryption documentation

Filter ⌘K

Filter ⌘K

Manage app information

# Determine and upload app encryption documentation

[Learn how to manage app encryption declarations and documentation using the App Store Connect API.](https://developer.apple.com/documentation/appstoreconnectapi/app-encryption-declarations)

**Required role:** Account Holder, Admin, or App Manager. [View role permissions.](/help/app-store-connect/reference/account-management/role-permissions)

## Determine your export compliance requirements

App Store Connect provides a set of questions to help you determine whether app encryption documentation is required from you, and which forms are specifically needed.

[Learn about the app encryption documentation you may need to provide.](/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption)

1.  In Apps, select the app you want to view.

2.  In the sidebar, click App Information.

3.  Next to App Encryption Documentation, click the add button (+) and answer the questions that appear in the dialogs.

    Alternatively, you can click Manage next to the build that’s missing app encryption information on either the Distribution tab or TestFlight tab to answer the required questions.

### Upload your documentation

If you’re required to upload app encryption documentation, you can do so in the App Encryption Documentation section in the App Store Connect. This should be completed before submitting a build for review on either App Review or TestFlight App Review. To ensure a smooth review process, populate the App Description field and [manage availability for your app on the App Store](/help/app-store-connect/manage-your-apps-availability/manage-availability-for-your-app-on-the-app-store) before providing this documentation. Without this information, Apple can’t determine whether the app encryption documents are sufficient.

1.  In Apps, select the app you want to view.

2.  In the sidebar, click App Information.

3.  Next to App Encryption Documentation, click the add button (+) and answer the questions that appear in the dialogs.

4.  When prompted, click Choose File to upload your document.

5.  Click Save.

Apple evaluates export compliance reviews on a case-by-case basis. If you provide complete information, Apple expects to review and clear apps in approximately two business days. Once your documentation is approved, Apple will provide you a key value. You must [enter this value in Xcode](https://developer.apple.com/documentation/security/complying_with_encryption_export_regulations) to avoid answering encryption questions with each app submission. You can find this key value next to your approved documentation in the App Encryption Documentation section of App Store Connect.

If your app doesn’t require documentation, [update your app’s information property list (Info.plist) file in Xcode](https://developer.apple.com/documentation/security/complying_with_encryption_export_regulations) to let us know that your app doesn't use encryption or is exempt from providing documentation.

If you have specific questions about Apple's export process, [contact us](https://developer.apple.com/contact/topic/SC1110/subtopic/30067/solution/select).
