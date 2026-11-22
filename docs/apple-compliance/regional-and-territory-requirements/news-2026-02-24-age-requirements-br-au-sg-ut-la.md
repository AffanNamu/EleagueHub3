<!--
Source: https://developer.apple.com/news/?id=f5zj08ey
Final URL: https://developer.apple.com/news/?id=f5zj08ey
Retrieved (UTC): 2026-11-22T04:12:29Z
Raw file: news-2026-02-24-age-requirements-br-au-sg-ut-la.html
SHA-256 of raw: 3c8cea003c2f8a06d2662742e885b77b11cea0019ba770c75b770d2012a0ea02
Extraction: automated text extraction for offline search; the raw file is authoritative.
-->

## Age requirements for apps distributed in Brazil, Australia, Singapore, Utah, and Louisiana

February 24, 2026

Today we’re providing an update on the tools available for developers to meet their age assurance obligations under upcoming U.S. and regional laws, including in Brazil, Australia, Singapore, Utah, and Louisiana. Updates to the Declared Age Range API are now available in beta for testing.

**Brazil**

Developers who are distributing apps in Brazil can use the updated Declared Age Range API to obtain a user’s age category. Age categories for users in Brazil will be shared when the user or a parent or guardian (where relevant) agrees to share the age category with you. The API will also return a signal from the user’s device about the method of age assurance.

**Apps rated 18+ in Australia, Singapore, and Brazil**

Starting February 24, 2026, Apple will block users in Australia, Brazil, and Singapore from downloading apps rated 18+ unless they have been confirmed to be adults through reasonable methods. The App Store will perform this confirmation automatically. However, developers may have separate obligations to independently confirm that their users are adults. To assist with this, the Declared Age Range API—available on iOS, iPadOS, and macOS—provides developers with a helpful signal about a user's age.

For developers distributing their apps in Brazil, if you identify your app as containing loot boxes through the age rating questionnaire, the age rating of your app on the Brazil storefront will be updated to 18+.

**Utah and Louisiana**

For users with new Apple Accounts in Utah as of May 6, 2026, and in Louisiana as of July 1, 2026, age categories will be shared with the developer’s app when requested through the Declared Age Range API. The tools we previously announced have been expanded to help developers meet compliance obligations for Louisiana and Utah, including:

[Declared Age Range API](https://developer.apple.com/documentation/declaredagerange/)

[Significant Change API under PermissionKit](https://developer.apple.com/documentation/PermissionKit/SignificantAppUpdateTopic)

[New age rating property type in StoreKit](https://developer.apple.com/documentation/storekit/appstore/ageRatingCode)

[App Store Server Notifications](https://developer.apple.com/documentation/appstoreservernotifications/notificationtype)

New signals are now available through the Declared Age Range API, including whether age-related regulatory requirements apply to the user and if the user is required to share their age range. The API will also let you know if you need to get a parent or guardian's permission for significant app updates for a child.

Developers can use the Declared Age Range API to present significant update notifications to adults in these states through the Significant Update Action, now in beta. When releasing a significant update, developers must follow the Human Interface Guidelines and provide users with a meaningful description of the update.

[Age assurance frameworks Q&A](https://developer.apple.com/support/age-assurance)

[Design safe and age‑appropriate experiences for your apps and games](https://developer.apple.com/kids/#age-assurance)

- 
- 
- 
- 
