<!--
Source: https://developer.apple.com/distribute/app-review/
Final URL: https://developer.apple.com/distribute/app-review/
Retrieved (UTC): 2026-11-22T04:11:57Z
Raw file: app-review-overview.html
SHA-256 of raw: 709ba12a5fc7deaa5cae00825545b1055c7b32a4349221c157db1f5df3dabc0b
Extraction: automated text extraction for offline search; the raw file is authoritative.
-->

# App Review

We review all apps, app updates, app bundles, in-app purchases, and in-app events submitted to App Store Connect to help provide a safe and trusted experience for users and the opportunity for developers to succeed. As you plan and build, use these guidelines and resources to help the review process go as smoothly as possible.

Preparing for review

Learn about the guidelines your submission needs to follow and information you’ll provide for review.

### Guidelines

Get in-depth details on the technical, content, and design criteria that we use for review, and learn about other key guidelines.

- [App Review Guidelines](/app-store/review/guidelines/)
- [Human Interface Design Guidelines](/design/human-interface-guidelines/)
- [Guidelines for Using Apple Trademarks and Copyrights](https://www.apple.com/legal/intellectual-property/guidelinesfor3rdparties.html)

### Apple Developer Program License Agreement

The Apple Developer Program License Agreement details your obligations and responsibilities for the use of Apple software and services. The latest agreement can be found on the Agreements and Guidelines page.

[Read the latest license agreement](/support/terms/)

### App review information

If your app requires specific settings, user account information, or special instructions, include these details in the App Review Information section of App Store Connect. If you don’t include this information, the app review process may be delayed and your app may not pass review.

Learn more about [providing information for a complete review](/help/app-review/before-submitting-for-review/complete-review) on App Review Help.

Submitting for review

When you submit for review in App Store Connect, you can:

- Manage your submissions and communicate with App Review on the App Review page within Apps. You can visit the App Review page at any time, even if you don’t have active submissions or conversations.
- Submit items such as in-app events, custom product pages, and product page optimization tests without needing a new app version.
- Include multiple items in one submission.
- Remove items with issues from your submission and continue with items that were accepted by App Review.
- View a history of submissions created using the updated experience, including messages from App Review.
- Decide whether your app is reviewed for the App Store or [Notarization only](/help/app-store-connect/distributing-apps-in-the-european-union/submit-for-notarization).

Learn more about [submitting for review on App Store Connect Help](/help/app-store-connect/manage-submissions-to-app-review/overview-of-submitting-for-review).

### Review status

App Review works around the clock, typically reviewing at least 50% of submissions in less than 24 hours and 90% in less than 48 hours. You’ll be notified by email of status changes. You can also check the review status of your submission in the [Apps section](https://appstoreconnect.apple.com/apps/) of App Store Connect or on the [App Store Connect app](https://apps.apple.com/us/app/app-store-connect/id1234793120/) for iPhone and iPad. If your submission is incomplete, review times may be delayed or your submission may not pass.

Learn more about [how to track a submission’s review status on App Review Help](/help/app-review/after-submitting-for-review/review-status).

Avoiding common issues

We’ve highlighted some of the most common issues to help you better prepare before submitting for review. On average, over 40% of unresolved issues are related to [guideline 2.1: App Completeness](/app-store/review/guidelines/#2.1), which covers crashes, placeholder content, incomplete information, and more.

[Watch “Tips for preventing common review issues”](/videos/play/tech-talks/10885/)

### Crashes and bugs

Submit items for review only when they’re complete and ready to be published. Make sure to thoroughly test on devices running the latest software and fix all bugs before submitting. [View guideline 2.1.](/app-store/review/guidelines/#2.1)

### Broken links

All links in your app must be functional. A link to user support with up-to-date contact information and a link to your privacy policy is required for all apps. View [guideline 2.1](/app-store/review/guidelines/#2.1) and [guideline 5.1](/app-store/review/guidelines/#5.1).

### Placeholder content

Finalize all images and text before submitting for review. Items that are still in progress and contain placeholder content are not ready to be distributed and cannot be approved. [View guideline 2.1.](/app-store/review/guidelines/#2.1)

### Incomplete information

Enter all of the details needed for review in the App Review Information section of App Store Connect. If some features require signing in, provide a valid demo account username and password. If there are special configurations to set, include the specifics. If features require an environment that is hard to replicate or require specific hardware, be prepared to provide a demo video or the hardware. Also, please make sure your contact information is complete and up to date. [View guideline 2.1.](/app-store/review/guidelines/#2.1)

Specific documentation is required for certain scenarios and types of apps. Here are a few examples:

- If the app is for kids and contains third-party ads, provide a link to the ad services’ publicly documented practices and policies for Kids category apps, including human review of ad creatives for age appropriateness. [View guideline 1.3.](/app-store/review/guidelines/#1.3)
- If the app works with medical hardware, provide a copy of regulatory clearance for the locations where the app is available. [View guideline 1.4.](/app-store/review/guidelines/#1.4)
- If the app features third-party trademarks or copyrighted content or lets users stream or download third-party content, provide the authorization to do so. Examples include video streaming and marketing that uses imagery of celebrities, sports, movies, or music. View [guideline 4.1](/app-store/review/guidelines/#4.1) and [guideline 5.2](/app-store/review/guidelines/#5.2).
- If the app facilitates services requiring licensing, such as real money gaming and gambling, lotteries, raffles, and VPN licensing, provide the authorization to do so. Note that licensing requirements may vary depending on region. [View guideline 5.](/app-store/review/guidelines/#5)

### Privacy policy issues

Make sure your privacy policy adheres to [guideline 5.1](/app-store/review/guidelines/#5.1) and:

- Identifies the data the app collects, how it collects that data, and all uses of that data.
- Confirms that any third party with whom the app shares user data provides the same or equal protection of user data as stated in the app’s privacy policy.
- Explains your data retention and deletion policies and describes how a user can revoke consent and/or request deletion of their data.

[Watch “Do more with less data”](/videos/play/tech-talks/110352/)

### Unclear data access requests

When requesting permission to access user or usage data, you should clearly and completely describe how your app will use the data. Including an example can help users understand why your app is requesting access to their personal information.

If your app’s code references one or more APIs that access sensitive user data, the app’s Info.plist file should contain a `$!{infoPlistKey}` key with a user-facing purpose string explaining clearly and completely why your app needs the data. All apps submitted to App Store Connect that access user data are required to include a purpose string.

To learn more, visit [5.1.1(ii) - Write clear purpose strings](/help/app-review/guideline-reference/5-1-1-purpose-strings) on App Review Help and [view guideline 5.1.](/app-store/review/guidelines/#5.1)

### Inaccurate screenshots

Screenshots should accurately communicate value and functionality. Use text and overlay images to highlight the user experience, not obscure it. To learn more, visit [2.3.3 - Show your app in use with screenshots](/help/app-review/guideline-reference/2-3-3-screenshots) on App Review Help and [view guideline 2.3](/app-store/review/guidelines/#accurate-metadata).

### Substandard user interface

Apple places a high value on clean, refined, and user-friendly interfaces. Make sure your UI meets these requirements by planning your design carefully and following our [design guides](/design/human-interface-guidelines/).

### Web clippings, content aggregators, or a collection of links

Your app should be engaging and useful, and make the most of the features unique to iOS. Websites served in an iOS app, web content that is not formatted for iOS, and limited web interactions do not make a quality app. [View guideline 4.2.](/app-store/review/guidelines/#minimum-functionality)

### Repeated submission of similar apps

Submitting several apps that are essentially the same ties up the App Review process and risks your apps not passing review. Improve your review experience — and the experience of your future users — by thoughtfully combining your apps into one. [View guideline 4.3.](/app-store/review/guidelines/#spam)

### Copycats

When working on your app, focus on creating interesting, unique experiences that aren’t already available. Apps that actively try to copy other apps won’t pass review. To learn more, visit [4.1 - Preventing copycat and impersonation rejections](/help/app-review/guideline-reference/4-1-prevent-copycat-rejection) on App Review Help and [view guideline 4.1.](/app-store/review/guidelines/#copycats)

### Misleading users

Your app must perform as advertised and should not give users the impression the app is something it is not. If your app appears to promise certain features and functionalities, it needs to deliver. [View guideline 2.3.](/app-store/review/guidelines/#accurate-metadata)

### Not enough lasting value

If your app doesn’t offer much functionality or content, or only applies to a small niche market, it may not be approved. Before creating your app, take a look at the apps in your category on the App Store and consider how you can provide an even better user experience. [View guideline 4.2.](/app-store/review/guidelines/#minimum-functionality)

### Submitted by incorrect entity

Certain types of apps must be submitted by the legal entity that provides the services rather than an individual developer. These apps include, but are not limited to, those that require sensitive user information or provide services in highly regulated fields, such as banking and financial services, cryptocurrency, healthcare, gambling, and air travel. If you need to provide partnership documentation or authorization, attach the files in the Attachment section in App Store Connect and provide any descriptions or links in the Review Notes field. View [guideline 3](/app-store/review/guidelines/#3) and [guideline 5.1.1](/app-store/review/guidelines/#5.1.1).

![](/assets/elements/icons/wwdr-unified/service.svg)

### Technical Support

If your app didn’t pass review for technical reasons, such as crashes or bugs, view the following documentation:

- [Acquiring Crash Reports and Diagnostic Logs](/documentation/xcode/diagnosing_issues_using_crash_reports_and_device_logs/acquiring_crash_reports_and_diagnostic_logs/)
- [Analyzing a Crash Report](/documentation/xcode/diagnosing_issues_using_crash_reports_and_device_logs/analyzing_a_crash_report/)
- [Identifying the Cause of Common Crashes](/documentation/xcode/diagnosing_issues_using_crash_reports_and_device_logs/identifying_the_cause_of_common_crashes/)

You can also visit the [Apple Developer Forums](/forums/) or request [code-level support](/support/technical/).

Contacting us

### App Review submissions

You can view your past and current submissions to App Review in App Store Connect. If your submission didn’t pass review, details are provided, including any specific App Review Guidelines that your submission didn’t follow. You can correspond with App Review to resolve the issues before resubmitting the build. Access the App Review section on the app’s page in App Store Connect.

Learn more about [contacting App Review for help with a submission](/help/app-review/after-submitting-for-review/contact-app-review).

### Appointment

Meet with App Review over Webex to discuss the App Review Guidelines and explore best practices for a smooth review process. In each 30-minute video appointment, you can ask for advice on what to expect during review, how your app can best align with guidelines, reasons for common rejections, and topics related to the process of reviewing your app.

Learn more about [appointment requests](/help/app-review/before-submitting-for-review/app-review-appointment).

### Appeals

If your app didn’t pass review and you feel we misunderstood your app’s concept and functionality, or that you were treated unfairly by Apple in the course of our review, you may choose to submit an appeal to the App Review Board. If you file an appeal, make sure to:

- Provide specific reasons why you believe your app complies with the App Review Guidelines.
- Submit only one appeal per submission that didn’t pass review.
- Respond to any requests for additional information before submitting an appeal.

Learn more about [submitting complete appeals](/help/app-review/after-submitting-for-review/appeal-to-the-app-review-board).

### Expedited reviews

You can request the review of your app to be expedited if you face extenuating circumstances, such as fixing a critical bug in your app or releasing your app to coincide with an event you’re directly associated with.

**Critical bug fix.** When submitting an expedited review to fix a critical bug, include the steps to reproduce the bug on the current version of your app.

**Event-related app.** For apps associated with an event, we recommend you plan and schedule the release of your app in App Store Connect. However, if your app is still in review and the launch of your event is quickly approaching, you can request to have your app review expedited. Make sure your request includes the event, date of the event, and your app’s association with the event.

Learn more about [expedite requests](/help/app-review/after-submitting-for-review/request-expedited-review).

### Bug fix submissions

If you’re submitting a bug fix update for your app and we find additional issues during review, you have the option to resolve the additional issues with your next submission, as long as there are no legal or safety concerns. To accept, simply reply to the offer message in App Store Connect and indicate you would like the current submission to be approved.

Learn more about [bug fix submissions](/help/app-review/after-submitting-for-review/bug-fix-submissions).

### Suggestions

Help improve the App Review Guidelines or identify a need for clarity in our policies by suggesting guideline changes. Your suggestions will be taken into consideration by App Review.

Learn more about [suggesting changes to the guidelines](/help/app-review/after-submitting-for-review/improve-guidelines).

### Report a concern

If you believe that an app presents a trust or safety concern, or is in violation of the App Review Guidelines, you can share details with us to investigate.

Learn more about [reporting apps](/help/app-review/safe-and-trusted-store/report-an-app).

### Other questions

You can contact us to ask for support with an unresolved app rejection or removal.

[Contact us](/contact/request/app-review/support/)
