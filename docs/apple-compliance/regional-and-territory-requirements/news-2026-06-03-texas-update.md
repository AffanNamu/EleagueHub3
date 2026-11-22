<!--
Source: https://developer.apple.com/news/?id=sg176nne
Final URL: https://developer.apple.com/news/?id=sg176nne
Retrieved (UTC): 2026-11-22T04:12:29Z
Raw file: news-2026-06-03-texas-update.html
SHA-256 of raw: 06d2a9b46b49b56412d5dc7b41808abf566c5e27120461d2bdf4c973f7a7b8ac
Extraction: automated text extraction for offline search; the raw file is authoritative.
-->

## Update for Apps Distributed in Texas

June 3, 2026

Due to a recent court ruling lifting an injunction on Texas law SB 2420, new Apple Accounts in Texas are now subject to the law, which introduced age assurance requirements for app marketplaces and developers. As previously [announced](https://developer.apple.com/news/?id=2ezb6jhj), this includes age assurance and parent or guardian consent on behalf of minors under the age of 18 for downloads, Apple In-App Purchases, and significant changes associated with an app. Parents or guardians will also be able to revoke their consent for any app they previously approved for their child. These changes will go into effect starting June 4, 2026.

Developers can request age category data for these Apple Accounts through the [Declared Age Range API](https://developer.apple.com/documentation/declaredagerange/). For significant changes, developers should use the [Significant Change API](https://developer.apple.com/documentation/PermissionKit/SignificantAppUpdateTopic/) under the PermissionKit framework. As a reminder, it’s the developer’s responsibility to determine when there’s a significant change to their app. To learn about a parent or guardian’s revocation of consent, the App Store is providing a server notification that developers can configure to receive notifications that consent has been withdrawn for their app on a child or teen’s device.

**Next steps**

1.  Review documentation and implement the following:

- [Declared Age Range API](https://developer.apple.com/documentation/declaredagerange/)
- [Significant Change API under PermissionKit](https://developer.apple.com/documentation/PermissionKit/SignificantAppUpdateTopic)
- [New age rating property type in StoreKit](https://developer.apple.com/documentation/storekit/appstore/ageRatingCode)
- [App Store server notification](https://developer.apple.com/documentation/appstoreservernotifications/notificationtype)

2.  Use Apple’s sandbox testing environment to validate that the APIs have been implemented correctly.

For the most up-to-date requirements and API references, see:

- [Age assurance frameworks Q&A](https://developer.apple.com/support/age-assurance)

Learn more about how you can [provide age-appropriate experiences](https://developer.apple.com/kids/) and safeguard privacy in your apps and games using robust features available across Apple platforms.

- 
- 
- 
- 
