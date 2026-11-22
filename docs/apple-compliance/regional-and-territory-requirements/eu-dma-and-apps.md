<!--
Source: https://developer.apple.com/support/dma-and-apps-in-the-eu/
Final URL: https://developer.apple.com/support/apps-in-the-eu
Retrieved (UTC): 2026-11-22T04:11:57Z
Raw file: eu-dma-and-apps.html
SHA-256 of raw: dc2e55c881562031dec3ebfa96c16d3914d32644c6bb2f6f481098748d65479a
Extraction: automated text extraction for offline search; the raw file is authoritative.
-->

# Changes for apps in the European Union

Since 2024, Apple has made updates to iOS, iPadOS, Safari, and the App Store in the European Union (EU) to comply with the Digital Markets Act (DMA), giving developers more options in the EU — including the ability to process payments for digital goods and services outside of Apple In-App Purchase, distribute on alternative app marketplaces, operate alternative app marketplaces, distribute directly from their website, and use alternative browser engines.

## What’s new

The Apple Developer Program License Agreement, updated August 18, 2026, introduced new business terms and policies for apps distributed in the European Union, following engagement with the European Commission. Effective October 1, 2026, the updates include:

- **Unified business terms.** Apps distributed in the EU are now subject to a single set of terms, under which Apple charges a commission on the sale of digital goods and services. The Core Technology Fee, a per-install fee for developers who achieve extraordinary scale, has been replaced by the Core Technology Commission, a simple 5% commission on digital transactions in apps distributed outside the App Store. The new terms also eliminate the Initial Acquisition Fee and Store Services Fee.
- **Alternative payments and Apple In-App Purchase.** Apps distributed in EU storefronts can now offer alternative payment methods and offers alongside Apple In-App Purchase. To help ensure a consistent user experience, developers must maintain their choice of payment options for 12 months.
- **Child safety protections.** New child safety requirements apply to apps that use alternative payment options on the App Store.
- **Eligibility for operating an alternative app marketplace and Web Distribution.** Eligibility requirements for both have been expanded to include additional options. Companies are no longer required to have a legal entity or be established in the EU to operate an alternative app marketplace or use Web Distribution.

## ![](/assets/elements/icons/symbols/appstore.svg) Payment options on the App Store

The App Store provides multiple ways for you to offer digital goods and services that customers can discover and enjoy using Apple’s technology and services. In the EU, there are additional options, which include specific business terms for iOS, iPadOS, macOS, tvOS, visionOS, and watchOS apps distributed in EU storefronts.

- **Apple In-App Purchase.** You can continue using Apple In-App Purchase, which is convenient and easy for users. It offers worldwide end-to-end payment processing, foreign currency exchange, tax support, customer service, and more. No changes are required on your part.
- **Alternative payment options.** In addition to Apple In‑App Purchase, you can:
  - Offer digital goods and services for purchase within your app using an alternative payment processor.
  - Provide out-of-app offers that direct users to purchase digital goods and services at a destination of your choice — a website, alternative app marketplace, or another app — regardless of whether you use an actionable link.

To provide consistency and clarity for users, developers offering payment options — Apple In-App Purchase, alternative payment processing in their app, linking to the web, or a combination — must maintain those options for 12 months.

Also, reader apps distributed in the EU may promote out-of-app offers for digital goods and services without an actionable link, regardless of whether they use the StoreKit External Link Account Entitlement. These offers are subject to requirements about where they may be displayed. [Learn more](/support/reader-apps/).

For details, see [Payment options on the App Store in the EU](/support/payment-options-on-the-app-store-in-the-eu).

##  Child safety protections for alternative payments on the App Store

The App Store is designed to be a safe and trusted place for everyone, including children. Apple has worked with the European Commission to implement child safety measures for alternative payments similar to those already in place in other markets.

- **Apps in the Kids category** must place purchase flows that use an alternative payment processor behind a parental gate, and cannot provide an out-of-app offer to purchase on a website.
- **For users under 13 years old**, alternative payment purchases must be behind a parental gate, and out-of-app offers are not permitted.
- **For users 13 years old to 17 years old**, both alternative payment processing within the app and out-of-app purchase offers must be behind a parental gate.

In cases where an EU storefront sets an age for parental consent above 13 years old, the same protections apply at the higher age instead of 13. For example, in some storefronts the protections apply to users under 16 (instead of under 13) and 16 to 17 (instead of 13 to 17). To find specific age requirements, see [Region-specific rules for managing an Apple Account](https://support.apple.com/en-us/125666).

For details, see [Payment options on the App Store in the EU](/support/payment-options-on-the-app-store-in-the-eu).

##  Alternative distribution on iOS and iPadOS

In addition to the App Store, users in the EU can install notarized iOS and iPadOS apps from alternative app marketplaces or directly from an authorized developer’s website. Developers distributing apps in the EU can enable alternative marketplace distribution in App Store Connect and request access to the APIs needed for Web Distribution and to operate an alternative app marketplace in the EU.

### Notarizing apps

Notarization for iOS and iPadOS apps is a baseline review that applies to all apps, regardless of their distribution channel, focused on platform policies for security and privacy and to maintain device integrity. Through a combination of automated checks and human review, notarization helps check that apps are free of known malware, viruses, or other security threats, function as promised, and don’t expose users to egregious fraud.

Information from the Notarization process is also used for app installation sheets, which provide at-a-glance descriptions of apps and their functionality before users download them, including the developer, app description, screenshots, age ratings, and other essential information.

Apps distributed on the App Store need to meet Apple’s higher standards for user safety, security, and privacy and undergo the standard [App Review process](/distribute/app-review/), which includes Notarization and enforcement of content and commerce policies.

To get your app notarized, select the alternative distribution option in App Store Connect when you submit it for review. Your app will be evaluated against the Notarization Review Guidelines, a subset of the [App Review Guidelines](/app-store/review/guidelines/). Notarization will check for:

- **Accuracy.** Apps must accurately represent the developer, capabilities, and costs to users.
- **Functionality.** Binaries must be reviewable, free of serious bugs or crashes, and compatible with the current version of iOS and/or iPadOS. They cannot manipulate software or hardware in ways that negatively impact the user experience.
- **Safety.** Apps cannot promote physical harm of the user or public.
- **Security.** Apps cannot enable distribution of malware or of suspicious or unwanted software. They cannot download executable code, read outside of the container, or direct users to lower the security on their system or device. Also, apps must provide transparency and allow user consent to enable any party to access the system or device, or reconfigure the system or other software.
- **Privacy.** Apps cannot collect or transmit private, sensitive data without a user’s knowledge or in a manner contrary to the stated purpose of the software.

Apple encrypts and signs all iOS and iPadOS apps intended for alternative distribution to help protect developers’ intellectual property and ensure that users get apps from known parties. Notarized apps also undergo a series of checks during installation to ensure that they haven’t been tampered with and that the installation was initiated through an authorized alternative app marketplace or an approved developer’s website. If Apple determines that an app contains known malware after it’s been installed, it will be prevented from launching, and new installations will be blocked.

For details, see:

- [App Store Connect Help: Submit for notarization](/help/app-store-connect/distributing-apps-in-the-european-union/submit-for-notarization)
- [Notarization Review Guidelines](/app-store/review/guidelines/)

### Distributing on an alternative app marketplace

An alternative app marketplace is an app whose primary purpose is the discovery and distribution of notarized iOS and iPadOS apps. To distribute your app on an alternative app marketplace in the EU, you’ll use App Store Connect and the App Store Connect API to complete tasks, such as:

- Registering the alternative app marketplace and providing your Developer ID.
- Adding the marketplace token (provided to you by the marketplace).
- Selecting which of your apps are eligible for alternative distribution.
- Sending notifications to the marketplace when updates are available.

If you distribute your app on an alternative app marketplace:

- App Store functionality like Apple In-App Purchase is not available.
- The sale of digital goods or services from your app is subject to a Core Technology Commission (CTC). For additional details, see the [business terms](#business-terms) section below.

For details, see [Manage distribution on an alternative app marketplace](/help/app-store-connect/managing-alternative-distribution/manage-distribution-on-an-alternative-app-marketplace).

### Operating an alternative app marketplace

In the EU, developers can build an alternative app marketplace to distribute notarized iOS and iPadOS apps. Based on specific criteria and ongoing requirements that help protect users and developers, authorization from Apple is required to operate an alternative app marketplace. Authorized developers have access to marketplace capabilities that enable them to securely receive notarized apps from other Apple Developer Program members, allow users to download and install marketplace apps from their website, integrate with system functionality, back up and restore users’ apps, and more.

Apple has expanded eligibility to operate an alternative app marketplace in the EU. Developers who meet at least one of the following criteria are eligible:

- Meet a moderate financial-stability bar as scored by Dun & Bradstreet;
- Are publicly traded, or owned by a publicly traded company;
- Have received venture funding from an established investment firm;
- Have completed a financial audit by a licensed accountant;
- Are a government entity, educational institution, or nonprofit approved for a fee waiver;
- Provide a stand-by letter of credit of USD 1,000,000 (or equivalent in local currency); or
- Have one million first annual installs worldwide.

For details, see [Operating an alternative app marketplace in the EU](/support/alternative-app-marketplace-in-the-eu/).

### Distributing directly from your website

Web Distribution lets developers distribute notarized iOS and iPadOS apps directly to EU users from a website owned by the developer and registered with Apple. Based on specific criteria and ongoing requirements that help protect users, authorization from Apple is required to use Web Distribution. Authorized developers get access to APIs that let them distribute apps from the web, integrate with system functionality, back up and restore users' apps, and more.

Apple has expanded eligibility for Web Distribution. Developers who meet at least one of the following criteria are eligible to distribute apps via their own website:

- Meet a moderate financial-stability bar as scored by Dun & Bradstreet;
- Are publicly traded, or owned by a publicly traded company;
- Have received venture funding from an established investment firm;
- Have completed a financial audit by a licensed accountant;
- Are a government entity, educational institution, or nonprofit approved for a fee waiver;
- Provide a stand-by letter of credit of USD 1,000,000 (or equivalent in local currency); or
- Have one million first annual installs worldwide.

For details, see [Web Distribution in the EU](/support/web-distribution-eu/).

### App installation experience updates

iOS and iPadOS provide an app installation experience that helps users authorize installs of apps and alternative app marketplaces, and learn more about apps and marketplaces before downloading them. The following updates will be available in the EU with iOS and iPadOS 27.2:

- An updated installation experience for alternative app marketplaces and apps distributed via a developer’s website.
- An API that lets developers initiate, from within their own app, downloads of apps distributed via their website.
- The ability for EU users to install alternative app marketplaces and alternatively distributed apps for 90 days when traveling outside the EU.

[View the user experience](/support/alt-distribution-ux-in-the-eu/)

##  Business terms for apps in the EU

When distributing your app in the EU, you're responsible for paying applicable commissions and fees to Apple for the sale of digital goods or services. The commissions and fees reflect the extensive value Apple provides developers through ongoing investments in the tools, technologies, and services that enable them to create innovative apps for the Apple ecosystem — as well as the value delivered by the App Store, which offers capabilities such as app distribution and management, discovery, trust and safety, re-engagement, promotional tools and services, app insights, and payment processing and commerce services.

### Business terms for the App Store in the EU

#### App Store commission

##### (Apple In-App Purchase)

| Rate | Applies to                                                                                                                                                                                                                 |
|------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| 26%  | Sales processed by Apple In-App Purchase.                                                                                                                                                                                  |
| 15%  | Sales processed by Apple In-App Purchase from participants in the App Store Small Business Program, Mini Apps Partner Program, or Video Partner Program, and sales of auto-renewable subscriptions after their first year. |

#### App Store commission

##### (alternative payment processing within the app)

| Rate | Applies to                                                                                                                                                                                                                                          |
|------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| 20%  | Sales processed via alternative payment processing within the app.                                                                                                                                                                                  |
| 10%  | Sales processed via alternative payment processing within the app from participants in the App Store Small Business Program, Mini Apps Partner Program, or Video Partner Program, and sales of auto-renewable subscriptions after their first year. |

App Store commission rates apply to the price paid by the customer. The calculation of any applicable taxes is performed as per the Apple Developer Program License Agreement.

#### Store services commission

The store services commission applies when your app uses an out-of-app offer with an actionable link that directs users to offers and promotions at a destination of your choice — a website, an alternative app marketplace, or another app. Only sales made within 7 days of the link tap are subject to this commission.

| Rate | Applies to                                                                                                                                                                                                                                                    |
|------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| 15%  | Out-of-app offers, excluding transactions from program participants or auto-renewable subscriptions after their first year.                                                                                                                                   |
| 10%  | Out-of-app offers for relevant transactions from participants in the App Store Small Business Program, Mini Apps Partner Program, and Video Partner Program; and out-of-app offers for relevant auto-renewable subscriptions after a subscriber’s first year. |

For purchases of digital goods or services on the App Store that don't use Apple In-App Purchase, you're responsible for the collection and remittance of any applicable taxes for sales processed by an alternative payment provider. You're also required to track and send Apple a report of all alternative payment transactions for applicable commission fee calculation and collection purposes. This report will need to be provided monthly within 15 days following the end of the calendar month.

For details, see [Payment options on App Store in the EU](/support/payment-options-on-the-app-store-in-the-eu/).

### Core Technology Commission for iOS and iPadOS apps distributed outside of the App Store

| Rate | Applies to                                                                                                                                                                                                                                                                                         |
|------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| 5%   | Alternative app marketplaces, apps distributed through them, or apps distributed via Web Distribution are subject to a commission on the sales of paid apps and digital goods or services (including one-time purchases and auto-renewing subscriptions) for use within apps on an Apple platform. |

The Core Technology Commission (CTC) reflects the value Apple provides developers through ongoing investments in the tools, technologies, and services that enable developers to build and share innovative apps with users. The CTC covers the following types of transactions:

- Sales of digital goods and services within alternative app marketplaces, apps distributed via alternative app marketplaces, and apps distributed via Web Distribution.
- Sales of digital goods or services (including one-time purchases and auto-renewing subscriptions) required to access or download alternative app marketplaces, apps distributed via alternative app marketplaces, and apps distributed via Web Distribution, including paid subscriptions to access or download app content or catalogs of apps.
- Sales when alternative app marketplaces, apps distributed via alternative app marketplaces, or apps distributed via Web Distribution direct users to offers and promotions with actionable links that open in a web browser to a website for the purchase of promoted digital goods and services. Only sales made within 7 days of the link tap are subject to this commission.

**Taxes.** The commission applies to the total price payable by each user, less any transaction taxes. You are responsible for the collection and remittance of any applicable taxes for sales processed by an alternative payment provider.

**Reporting transactions.** Developers who distribute their apps via alternative distribution, including those who operate marketplaces, are responsible for reporting their transactions of digital goods and services to Apple. All transactions subject to the Core Technology Commission must be reported, including transactions that didn’t result in a completed sale.

For details, see:

- [Reporting tokens and transactions to Apple](/help/app-store-connect/making-payments-to-apple/reporting-tokens-and-transactions/)
- [Overview of making payments to Apple](/help/app-store-connect/making-payments-to-apple/overview-of-making-payments-to-apple/)

**CTC waiver for small marketplace operators.** If you're a small marketplace operator, you qualify to have the CTC waived on fees your EU marketplace app charges to download your alternative app marketplace, or subscription fees to access apps distributed by your alternative app marketplace. To qualify you need to earn less than:

- €10 million in global revenue in the last 12 months; and
- €1 million in total lifetime revenue from your EU marketplace app’s download price or subscription fees to access apps distributed by your marketplace.

For details, see [Operating an alternative app marketplace in the EU](/support/alternative-app-marketplace-in-the-eu/).

## Get started with the Apple Developer Program License Agreement

The Apple Developer Program License Agreement has been updated to include [new options and business terms](/support/terms/apple-developer-program-license-agreement/#A14) for apps distributed in the EU. To agree to these terms in your [Apple Developer account](/account/), you’ll need to be the Account Holder of your membership. After agreeing to the terms, your developer account will:

- Have access to the entitlement you’ll need to offer alternative payment options for digital goods and services in your app on the App Store in EU storefronts.
- Have access to alternative distribution tools in App Store Connect.
- Be subject to unified business terms for apps distributed in the EU.

### Transition to the unified EU terms

As Apple has moved to a unified business model in the EU for all developers, the Alternative Terms Addendum for Apps in the EU and StoreKit External Purchase Link Entitlement (EU) Addendum have been phased out. As of October 1, 2026, these terms have been superseded by Attachment 14 of the Apple Developer Program License Agreement.

To move to the unified EU terms, developers need to agree to the updated Apple Developer Program License Agreement. After agreeing to the updated terms, their account will be subject to the unified EU terms. Developers that owe Apple fees and commissions accrued under the discontinued agreements will remain responsible for paying those amounts to Apple.

## iOS and iPadOS capabilities

###  Developer app analytics and user data portability

#### App analytics reports for the App Store, iOS, and iPadOS

Apple has expanded the analytics available for developers’ apps both in the EU and around the world to help developers get even more insight into their businesses and their apps’ performance. Over 100 reports are available through the App Store Connect API to help developers analyze their app performance and find opportunities for improvement with more metrics in areas like:

- **Engagement** — with additional information on the number of users on the App Store interacting with a developer’s app or sharing it with others;
- **Commerce** — with additional information on downloads, sales and proceeds, pre-orders, and transactions made with Apple In-App Purchase;
- **App usage** — with additional information on crashes, active devices, installs, app deletions, and more;
- **Frameworks usage** — with additional information on an app’s interaction with OS capabilities such as PhotoPicker, Widgets, and CarPlay.

Apple provides an App Store Connect API called the Analytics Reports API to provide access to reports that include data from the App Store, iOS, and iPadOS. Developers also have the ability to provide third-party access to their reports using this API. To protect the privacy of Apple users, Apple applies privacy measures to help ensure that users are not identifiable at an individual level.

For details, see [Analytics Reports API](/documentation/appstoreconnectapi/analytics).

#### User and app data portability tools for App Store account data

Apple is committed to giving users transparency and control over the data Apple collects and uses, and offers users tools for understanding and managing their personal data. This includes [Apple’s Data & Privacy](https://privacy.apple.com/) page, where users can get or transfer a copy of their data, delete their Apple account, and more. Apple’s Data & Privacy page provides users with additional App Store data categories and the ability to consent to transferring their data. Third parties are responsible for meeting minimum eligibility requirements before they may [access the Account Data Transfer API](/support/account-data-transfer-api/) for requesting transfers of user data to their apps or services. Third party app developers can request the transfer of App Store information and app-install activity about their apps by using the [App Data Transfer API](/documentation/appdatatransfer).

###  Default app controls and app deletion for users in the EU

iOS and iPadOS provide many default controls for users in the EU and around the world. They are managed from the Default Apps section at the top of the Apps area in Settings. In the EU, users have the ability to set defaults for:

- Browser apps
- Mail apps
- App marketplace apps
- Contactless apps
- Phone calls
- Messaging
- Password managers
- Keyboards
- Call spam filters
- Navigation apps
- Translation apps

Users in the EU can also delete the App Store, Messages, Camera, Photos, and Safari apps — only Settings and Phone can’t be deleted. To learn about enabling your app to be a system default, view [Default apps updates](/documentation/updates/defaultapps/).

###  Browser apps and alternative web browser engines in the EU

#### Default web browser choice

iOS and iPadOS provide a choice screen that informs users about additional ways to choose a default web browser from a list of options. When users in the EU first open Safari, they are prompted to choose their default browser and presented with a list of the main web browsers available in their market to select as their default browser.

For details, see [About the browser choice screen in the EU](/support/browser-choice-screen/).

#### Use of alternative browser engines

iOS and iPadOS include capabilities that let apps use alternative browser engines — browser engines other than WebKit — for dedicated browser apps and apps providing in-app browsing experiences in the EU. Authorized developers of dedicated browser apps have access to security mitigations and capabilities to enable them to build secure browser engines, and access features like passkeys for secure user login, multiprocess system capabilities to improve security and stability, web content sandboxes that combat evolving security threats, and more.

For details, see [Using alternative browser engines in the European Union](/support/alternative-browser-engines/).

###  Contactless transactions for iOS apps in the EEA

iOS includes APIs that support contactless transactions for in-store payments, car keys, closed-loop transit, corporate badges, home keys, hotel keys, merchant loyalty/rewards, and event tickets from within compatible iOS apps using host card emulation (HCE).

Users based in the European Economic Area (EEA) with an iPhone can initiate in-person NFC transactions from iOS apps at compatible NFC terminals or mobile devices. They can manage their preferred default contactless app through a default setting and launch the app by double-clicking the side button or when iPhone detects an NFC field at compatible terminals.

To support contactless transactions, eligible iOS apps need an HCE entitlement. The entitlement ensures that only authorized app developers who meet certain industry and regulatory requirements, and commit to ongoing security and privacy standards can access these APIs.

For details, see [HCE-based contactless NFC transactions for apps in the European Economic Area (EEA)](/support/hce-transactions-in-apps/).

###  Interoperability requests in the EU

Apple’s interoperability efforts across software development kits and developer services, encompassing more than 250,000 APIs, enable developers to leverage many of the core technologies built into iOS and iPadOS so users can access them right from developers’ apps.

Developers can ask questions or share feedback on Apple’s developer tools and services in a variety of ways — such as developer support, the Apple Developer Forums, and Feedback Assistant. To reflect the DMA’s requirements, Apple also provides a dedicated process to request additional interoperability with iOS and iPadOS. Apple evaluates each request and informs the developer about the outcome. To the extent an effective interoperability solution is feasible and appropriate under the DMA, Apple will subsequently develop the solution for release in a future software update.

For details, see [Requesting interoperability with iOS and iPadOS in the European Union](/support/ios-interoperability/).

## Contact us

If you have any additional questions about these options in the EU, we’re here to help.

[Contact Us](/contact/request/alternative-distribution/)
