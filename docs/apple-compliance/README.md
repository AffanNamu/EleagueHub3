# eSportlyic — Apple App Store compliance library

Local, offline copy of Apple's official App Store documentation, plus the
eSportlyic-specific audit built on it. Created 2026-11-22 for the
App Store rejection-cycle remediation (v1.9.20 / v1.9.21 rejections).

**Start here:**

| File | What it is |
|---|---|
| [REJECTION_HISTORY.md](REJECTION_HISTORY.md) | Every known App Review rejection, root cause, fix, status |
| [COMPLIANCE_MATRIX.md](COMPLIANCE_MATRIX.md) | Guideline-by-guideline status with evidence, risk and verification |
| [compliance-audit/AUDIT_REPORT.md](compliance-audit/AUDIT_REPORT.md) | Full audit report: findings, changes made, tests run, open items, release-readiness decision |
| [compliance-audit/PRE_SUBMISSION_CHECKLIST.md](compliance-audit/PRE_SUBMISSION_CHECKLIST.md) | Repeatable checklist for every future iOS submission |
| [compliance-audit/APP_REVIEW_NOTES_TEMPLATE.md](compliance-audit/APP_REVIEW_NOTES_TEMPLATE.md) | Draft "Notes for Review" text for App Store Connect |
| [manifest.json](manifest.json) | Machine-readable record of every download (URL, final URL, HTTP status, retrieval time, size, SHA-256) |
| [tools/](tools/) | The fetch script and URL lists used to build this library (re-run to refresh) |

## How the library was built

* Every document was fetched directly from Apple's servers on **2026-11-22**
  (UTC timestamps per file in `manifest.json` and in each `.md` header).
* **The raw file is authoritative.** Server-rendered pages are stored as
  `.html`; Apple's JavaScript-rendered documentation and Human Interface
  Guidelines pages are stored as the official JSON payload those pages load
  (`developer.apple.com/tutorials/data/...json`). Each has a `.md` text
  extraction next to it for searching, with source URL, retrieval time and
  the raw file's SHA-256 in its header.
* Nothing here is a summary or paraphrase presented as Apple text. Analysis
  lives only in the four eSportlyic files listed above.
* 152 of 156 requested documents were retrieved with content. The four that
  were not are listed with reasons in the tables below (marked **FAILED**,
  **SOFT_404** or **REDIRECT_SHELL**); in each case the same requirement was
  captured from another official page that is listed.

To refresh before a future submission:

```bash
python3 -I docs/apple-compliance/tools/fetch_apple_docs.py docs/apple-compliance/tools/manifest-core.tsv docs/apple-compliance
python3 -I docs/apple-compliance/tools/fetch_apple_docs.py docs/apple-compliance/tools/manifest-news.tsv docs/apple-compliance
```

Then check <https://developer.apple.com/news/> for new items and add any
relevant URLs to `tools/manifest-news.tsv`.

## Requirement changes that matter to eSportlyic

Apple's App Review Guidelines in this library are the version **last updated
October 16, 2026** (see `app-review-guidelines/app-review-guidelines.md`).
Several requirements post-date many online tutorials; these are the ones that
apply to this app.

### In force now

| Since | Requirement | Source in this library |
|---|---|---|
| 2025-11-13 | 1.2.1(a) creator apps need age-restriction for content above the app's rating; 5.1.2(i) explicit consent before sharing personal data with third parties, including third-party AI | `app-review-guidelines/news-2025-11-13-updated-app-review-guidelines.md` |
| 2026-01-31 | Updated age-rating questionnaire (in-app controls, capabilities, medical, violence) must be answered to submit updates | `metadata-and-product-pages/news-2025-07-24-updated-age-ratings.md` |
| 2026-02-06 | Random or anonymous chat is explicitly covered by 1.2 | `app-review-guidelines/news-2026-02-06-updated-app-review-guidelines.md` |
| 2026-04-28 | iOS apps must be built with the iOS 26 SDK or later | `ios-sdk-and-build-requirements/news-2026-02-03-upcoming-sdk-minimum-requirements.md` |
| 2026-09 | Age-rating questionnaire **social media capability** questions required for every update | `metadata-and-product-pages/news-2026-07-09-age-rating-social-media-questions.md` |
| 2026-10-16 | Guidelines update: 1.2 now explicitly covers nonconsensual intimate imagery; new 2.5.19 (no hidden, dormant or undocumented features); new 2.3.14 (creative assets); 3.1.1(a) link-entitlement wording | `app-review-guidelines/news-2026-10-16-*.md` |
| 2026-10-13 | Updated Apple Developer Program License Agreement (Account Holder must accept) | `app-review-guidelines/news-2026-10-13-updated-dpla.md` |
| 2026-11-16 | Age-rating **Shared Location** and **Dating and Relationships** declarations required on every update (this is the notice seen in App Store Connect — it is not a rejection) | `metadata-and-product-pages/news-2026-11-02-new-age-rating-content-descriptors.md` |
| ongoing | Digital Goods and Services questionnaire (App Information) when shown for the app | `app-store-connect/digital-goods-and-services-questionnaire.md` |

### Future effective dates (not yet enforced)

| Date | Requirement | Source |
|---|---|---|
| 2027-01-12 | Every app must have Shared Location / Dating declarations completed | `metadata-and-product-pages/news-2026-11-02-new-age-rating-content-descriptors.md` |
| 2027-04 | iOS apps must be built with the iOS 27 SDK or later | `ios-sdk-and-build-requirements/news-2026-09-09-submissions-open-latest-os.md` |
| iOS 27.2 | Alternative ATT prompt available in the EU (mandatory in DE, FR, IT, PL, RO) — only relevant if the app ever adopts ATT | `privacy-and-security/news-2026-09-16-att-updates-eu.md` |
| winter 2026 | Group (multiseat) subscription purchases launch; multiseat is **enabled by default** for subscriptions | `subscriptions/news-2026-09-16-subscriptions-ready-for-ios-27.md` |

### Territory- or category-specific requirements

| Territory / category | Requirement | Applies to eSportlyic? | Source |
|---|---|---|---|
| European Union | Trader status declaration (DSA); single business terms from 2026-10-01; Digital Goods questionnaire EU answers lock for 12 months | Yes if distributed in the EU | `app-store-connect/eu-dsa-trader-requirements.md`, `regional-and-territory-requirements/news-2026-08-18-changes-for-apps-in-eu.md` |
| Australia | Social media platforms must prevent under-16 accounts (law from 2025-12-10); 18+ apps need adult confirmation | Legal determination needed — eSportlyic has a public feed, follows and chat | `regional-and-territory-requirements/news-2025-12-08-australia-social-media-apps.md` |
| Brazil | Shared Location ⇒ A16, Dating ⇒ A18 rating; age-category sharing via Declared Age Range API | Shared Location/Dating: No (no such features). Age API: legal determination | `metadata-and-product-pages/news-2026-11-02-*.md`, `regional-and-territory-requirements/news-2026-02-24-*.md` |
| Texas, Utah, Louisiana | Age assurance and parental consent for minors' downloads and In-App Purchases; Declared Age Range and Significant Change APIs | Apple enforces at the store level; developer obligations need a legal review | `regional-and-territory-requirements/news-2026-06-03-texas-update.md` and related |
| Republic of Korea | Korea-based developers using Sign in with Apple must register a server-to-server notification endpoint | Only if the developer account is Korea-based | `privacy-and-security/news-2025-10-09-siwa-account-creation-requirement.md` |
| China mainland | ICP filing / compliance information required to distribute there | Only if distributed in China mainland | `regional-and-territory-requirements/china-mainland-compliance-information.md` |
| United States | StoreKit External Purchase Link entitlement rules | Not applicable — no external purchase links | `app-review-guidelines/app-review-guidelines.md` §3.1.1(a) |

## Library contents

### `app-review-guidelines/`

| Document | Official source | Local files | Retrieved (UTC) | Result |
|---|---|---|---|---|
| App Review Guidelines | <https://developer.apple.com/app-store/review/guidelines/> | [md](app-review-guidelines/app-review-guidelines.md) · [raw](app-review-guidelines/app-review-guidelines.html) | 2026-11-22 | OK |
| App Review - Distribute | <https://developer.apple.com/distribute/app-review/> | [md](app-review-guidelines/app-review-overview.md) · [raw](app-review-guidelines/app-review-overview.html) | 2026-11-22 | OK |
| Legal - Licensed Application End User License Agreement - Apple | <https://www.apple.com/legal/internet-services/itunes/dev/stdeula/> | [md](app-review-guidelines/apple-standard-eula.md) · [raw](app-review-guidelines/apple-standard-eula.html) | 2026-11-22 | OK |
| Agreements and Guidelines - Support | <https://developer.apple.com/support/terms/> | [md](app-review-guidelines/developer-terms-index.md) · [raw](app-review-guidelines/developer-terms-index.html) | 2026-11-22 | OK |
| 2.3.3 - Show your app in use with screenshots - Guideline reference | <https://developer.apple.com/help/app-review/guideline-reference/2-3-3-screenshots> | [md](app-review-guidelines/guideline-ref-2-3-3-screenshots.md) · [raw](app-review-guidelines/guideline-ref-2-3-3-screenshots.html) | 2026-11-22 | OK |
| 4.1 - Preventing copycat and impersonation rejections - Guideline reference | <https://developer.apple.com/help/app-review/guideline-reference/4-1-prevent-copycat-rejection> | [md](app-review-guidelines/guideline-ref-4-1-prevent-copycat-rejection.md) · [raw](app-review-guidelines/guideline-ref-4-1-prevent-copycat-rejection.html) | 2026-11-22 | OK |
| 5.1.1(v) - Offering account deletion in your app - Guideline reference | <https://developer.apple.com/help/app-review/guideline-reference/5-1-1-account-deletion> | [md](app-review-guidelines/guideline-ref-5-1-1-account-deletion.md) · [raw](app-review-guidelines/guideline-ref-5-1-1-account-deletion.html) | 2026-11-22 | OK |
| 5.1.1(ii) - Write clear purpose strings - Guideline reference | <https://developer.apple.com/help/app-review/guideline-reference/5-1-1-purpose-strings> | [md](app-review-guidelines/guideline-ref-5-1-1-purpose-strings.md) · [raw](app-review-guidelines/guideline-ref-5-1-1-purpose-strings.html) | 2026-11-22 | OK |
| App Review - Help | <https://developer.apple.com/help/app-review/> | [md](app-review-guidelines/help-app-review-index.md) · [raw](app-review-guidelines/help-app-review-index.html) | 2026-11-22 | OK |
| Updated App Review Guidelines now available | <https://developer.apple.com/news/?id=ey6d8onl> | [md](app-review-guidelines/news-2025-11-13-updated-app-review-guidelines.md) · [raw](app-review-guidelines/news-2025-11-13-updated-app-review-guidelines.html) | 2026-11-22 | OK |
| Updated App Review Guidelines now available | <https://developer.apple.com/news/?id=d75yllv4> | [md](app-review-guidelines/news-2026-02-06-updated-app-review-guidelines.md) · [raw](app-review-guidelines/news-2026-02-06-updated-app-review-guidelines.html) | 2026-11-22 | OK |
| Updated Apple Developer Program License Agreement and App Review Guidelines now available | <https://developer.apple.com/news/?id=a233fmpw> | [md](app-review-guidelines/news-2026-06-08-updated-dpla-and-guidelines.md) · [raw](app-review-guidelines/news-2026-06-08-updated-dpla-and-guidelines.html) | 2026-11-22 | OK |
| Updated Apple Developer Program License Agreement now available | <https://developer.apple.com/news/?id=17mwd36z> | [md](app-review-guidelines/news-2026-10-13-updated-dpla.md) · [raw](app-review-guidelines/news-2026-10-13-updated-dpla.html) | 2026-11-22 | OK |
| Strengthening App Review Guidelines against nonconsensual intimate imagery and bait-and-switch apps | <https://developer.apple.com/news/?id=vvzx6cul> | [md](app-review-guidelines/news-2026-10-16-ncii-and-bait-and-switch.md) · [raw](app-review-guidelines/news-2026-10-16-ncii-and-bait-and-switch.html) | 2026-11-22 | OK |
| Updated App Review Guidelines are now available | <https://developer.apple.com/news/?id=92th7e5i> | [md](app-review-guidelines/news-2026-10-16-updated-app-review-guidelines.md) · [raw](app-review-guidelines/news-2026-10-16-updated-app-review-guidelines.html) | 2026-11-22 | OK |

### `app-review-submission/`

| Document | Official source | Local files | Retrieved (UTC) | Result |
|---|---|---|---|---|
| Request a one-on-one App Review appointment - Before submitting for review | <https://developer.apple.com/help/app-review/before-submitting-for-review/app-review-appointment> | [md](app-review-submission/app-review-appointment.md) · [raw](app-review-submission/app-review-appointment.html) | 2026-11-22 | OK |
| Appeal to the App Review Board - After submitting for review | <https://developer.apple.com/help/app-review/after-submitting-for-review/appeal-to-the-app-review-board> | [md](app-review-submission/appeal-to-the-app-review-board.md) · [raw](app-review-submission/appeal-to-the-app-review-board.html) | 2026-11-22 | OK |
| Manage a submission with unresolved issues - Manage submissions to App Review | <https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/manage-a-submission-with-unresolved-issues> | [md](app-review-submission/asc-manage-a-submission-with-unresolved-issues.md) · [raw](app-review-submission/asc-manage-a-submission-with-unresolved-issues.html) | 2026-11-22 | OK |
| Overview of submitting for review - Manage submissions to App Review | <https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/overview-of-submitting-for-review> | [md](app-review-submission/asc-overview-of-submitting-for-review.md) · [raw](app-review-submission/asc-overview-of-submitting-for-review.html) | 2026-11-22 | OK |
| Reply to App Review messages - Manage submissions to App Review | <https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/reply-to-app-review-messages> | [md](app-review-submission/asc-reply-to-app-review-messages.md) · [raw](app-review-submission/asc-reply-to-app-review-messages.html) | 2026-11-22 | OK |
| Submit an app - Manage submissions to App Review | <https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app> | [md](app-review-submission/asc-submit-an-app.md) · [raw](app-review-submission/asc-submit-an-app.html) | 2026-11-22 | OK |
| Submit an In-App Purchase - Manage submissions to App Review | <https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase> | [md](app-review-submission/asc-submit-an-in-app-purchase.md) · [raw](app-review-submission/asc-submit-an-in-app-purchase.html) | 2026-11-22 | OK |
| Accept Bug Fix Submission offers - After submitting for review | <https://developer.apple.com/help/app-review/after-submitting-for-review/bug-fix-submissions> | [md](app-review-submission/bug-fix-submissions.md) · [raw](app-review-submission/bug-fix-submissions.html) | 2026-11-22 | OK |
| Provide information for a complete review - Before submitting for review | <https://developer.apple.com/help/app-review/before-submitting-for-review/complete-review> | [md](app-review-submission/complete-review.md) · [raw](app-review-submission/complete-review.html) | 2026-11-22 | OK |
| Configure In-App Purchases for review in the sandbox - Before submitting for review | <https://developer.apple.com/help/app-review/before-submitting-for-review/configure-in-app-purchases> | [md](app-review-submission/configure-in-app-purchases-for-review.md) · [raw](app-review-submission/configure-in-app-purchases-for-review.html) | 2026-11-22 | OK |
| Contact App Review for help with a submission - After submitting for review | <https://developer.apple.com/help/app-review/after-submitting-for-review/contact-app-review> | [md](app-review-submission/contact-app-review.md) · [raw](app-review-submission/contact-app-review.html) | 2026-11-22 | OK |
| Request an expedited review - After submitting for review | <https://developer.apple.com/help/app-review/after-submitting-for-review/request-expedited-review> | [md](app-review-submission/request-expedited-review.md) · [raw](app-review-submission/request-expedited-review.html) | 2026-11-22 | OK |
| Track a submission's review status - After submitting for review | <https://developer.apple.com/help/app-review/after-submitting-for-review/review-status> | [md](app-review-submission/review-status.md) · [raw](app-review-submission/review-status.html) | 2026-11-22 | OK |
| Test your app on compatible devices - Before submitting for review | <https://developer.apple.com/help/app-review/before-submitting-for-review/test-compatible-devices> | [md](app-review-submission/test-compatible-devices.md) · [raw](app-review-submission/test-compatible-devices.html) | 2026-11-22 | OK |

### `app-store-connect/`

| Document | Official source | Local files | Retrieved (UTC) | Result |
|---|---|---|---|---|
| App and compliance information - App information - Reference | <https://developer.apple.com/help/app-store-connect/reference/app-information/app-and-compliance-information> | [md](app-store-connect/app-and-compliance-information.md) · [raw](app-store-connect/app-and-compliance-information.html) | 2026-11-22 | OK |
| App Store Connect - Help | <https://developer.apple.com/help/app-store-connect/> | [md](app-store-connect/asc-help-index.md) · [raw](app-store-connect/asc-help-index.html) | 2026-11-22 | OK |
| Business Models and Monetization - App Store | <https://developer.apple.com/app-store/business-models/> | [md](app-store-connect/business-models.md) · [raw](app-store-connect/business-models.html) | 2026-11-22 | OK |
| Determine and upload app encryption documentation - Manage app information | <https://developer.apple.com/help/app-store-connect/manage-app-information/determine-and-upload-app-encryption-documentation> | [md](app-store-connect/determine-and-upload-app-encryption-documentation.md) · [raw](app-store-connect/determine-and-upload-app-encryption-documentation.html) | 2026-11-22 | OK |
| Complete the Digital Goods and Services questionnaire - Manage app information | <https://developer.apple.com/help/app-store-connect/manage-app-information/complete-the-digital-goods-and-services-questionnaire> | [md](app-store-connect/digital-goods-and-services-questionnaire.md) · [raw](app-store-connect/digital-goods-and-services-questionnaire.html) | 2026-11-22 | OK |
| Manage European Union Digital Services Act trader requirements - Manage compliance information | <https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements> | [md](app-store-connect/eu-dsa-trader-requirements.md) · [raw](app-store-connect/eu-dsa-trader-requirements.html) | 2026-11-22 | OK |
| Export compliance documentation for encryption - App information - Reference | <https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption> | [md](app-store-connect/export-compliance-documentation-for-encryption.md) · [raw](app-store-connect/export-compliance-documentation-for-encryption.html) | 2026-11-22 | OK |
| Overview of export compliance - Manage app information | <https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance> | [md](app-store-connect/overview-of-export-compliance.md) · [raw](app-store-connect/overview-of-export-compliance.html) | 2026-11-22 | OK |
| Platform version information - App information - Reference | <https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information> | [md](app-store-connect/platform-version-information.md) · [raw](app-store-connect/platform-version-information.html) | 2026-11-22 | OK |
| Required, localizable, and editable properties - App information - Reference | <https://developer.apple.com/help/app-store-connect/reference/app-information/required-localizable-and-editable-properties> | [md](app-store-connect/required-localizable-and-editable-properties.md) · [raw](app-store-connect/required-localizable-and-editable-properties.html) | 2026-11-22 | OK |
| Sign and update agreements - Manage agreements | <https://developer.apple.com/help/app-store-connect/manage-agreements/sign-and-update-agreements> | [md](app-store-connect/sign-and-update-agreements.md) · [raw](app-store-connect/sign-and-update-agreements.html) | 2026-11-22 | OK |
| View and edit app information - Create an app record | <https://developer.apple.com/help/app-store-connect/create-an-app-record/view-and-edit-app-information> | [md](app-store-connect/view-and-edit-app-information.md) · [raw](app-store-connect/view-and-edit-app-information.html) | 2026-11-22 | OK |

### `in-app-purchases/`

| Document | Official source | Local files | Retrieved (UTC) | Result |
|---|---|---|---|---|
| App Store Receipts | <https://developer.apple.com/documentation/appstorereceipts> | [md](in-app-purchases/app-store-receipts.md) · [raw](in-app-purchases/app-store-receipts.json) | 2026-11-22 | OK |
| App Store Server API | <https://developer.apple.com/documentation/appstoreserverapi> | [md](in-app-purchases/app-store-server-api.md) · [raw](in-app-purchases/app-store-server-api.json) | 2026-11-22 | OK |
| App Store Server Notifications | <https://developer.apple.com/documentation/appstoreservernotifications> | [md](in-app-purchases/app-store-server-notifications.md) · [raw](in-app-purchases/app-store-server-notifications.json) | 2026-11-22 | OK |
| Create consumable or non-consumable In-App Purchases - Manage In-App Purchases | <https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/create-consumable-or-non-consumable-in-app-purchases> | [md](in-app-purchases/create-consumable-or-non-consumable.md) · [raw](in-app-purchases/create-consumable-or-non-consumable.html) | 2026-11-22 | OK |
| Create offer codes for In-App Purchases - Manage In-App Purchases | <https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/create-offer-codes-for-in-app-purchases> | [md](in-app-purchases/create-offer-codes-for-in-app-purchases.md) · [raw](in-app-purchases/create-offer-codes-for-in-app-purchases.html) | 2026-11-22 | OK |
| Enter server URLs for App Store Server Notifications - Configure In-App Purchase settings | <https://developer.apple.com/help/app-store-connect/configure-in-app-purchase-settings/enter-server-urls-for-app-store-server-notifications> | [md](in-app-purchases/enter-server-urls-for-app-store-server-notifications.md) · [raw](in-app-purchases/enter-server-urls-for-app-store-server-notifications.html) | 2026-11-22 | OK |
| Generate a shared secret to verify receipts - Configure In-App Purchase settings | <https://developer.apple.com/help/app-store-connect/configure-in-app-purchase-settings/generate-a-shared-secret-to-verify-receipts> | [md](in-app-purchases/generate-a-shared-secret-to-verify-receipts.md) · [raw](in-app-purchases/generate-a-shared-secret-to-verify-receipts.html) | 2026-11-22 | OK |
| In-App Purchase information - In-App Purchases and subscriptions - Reference | <https://developer.apple.com/help/app-store-connect/reference/in-app-purchases-and-subscriptions/in-app-purchase-information> | [md](in-app-purchases/in-app-purchase-information.md) · [raw](in-app-purchases/in-app-purchase-information.html) | 2026-11-22 | OK |
| Apple In-App Purchase | <https://developer.apple.com/in-app-purchase/> | [md](in-app-purchases/in-app-purchase-overview.md) · [raw](in-app-purchases/in-app-purchase-overview.html) | 2026-11-22 | OK |
| In-App Purchase statuses - In-App Purchases and subscriptions - Reference | <https://developer.apple.com/help/app-store-connect/reference/in-app-purchases-and-subscriptions/in-app-purchase-statuses> | [md](in-app-purchases/in-app-purchase-statuses.md) · [raw](in-app-purchases/in-app-purchase-statuses.html) | 2026-11-22 | OK |
| In-App Purchase types - In-App Purchases and subscriptions - Reference | <https://developer.apple.com/help/app-store-connect/reference/in-app-purchases-and-subscriptions/in-app-purchase-types> | [md](in-app-purchases/in-app-purchase-types.md) · [raw](in-app-purchases/in-app-purchase-types.html) | 2026-11-22 | OK |
| Overview for configuring In-App Purchases - Configure In-App Purchase settings | <https://developer.apple.com/help/app-store-connect/configure-in-app-purchase-settings/overview-for-configuring-in-app-purchases> | [md](in-app-purchases/overview-for-configuring-in-app-purchases.md) · [raw](in-app-purchases/overview-for-configuring-in-app-purchases.html) | 2026-11-22 | OK |
| StoreKit | <https://developer.apple.com/documentation/storekit> | [md](in-app-purchases/storekit.md) · [raw](in-app-purchases/storekit.json) | 2026-11-22 | OK |
| sync() | <https://developer.apple.com/documentation/storekit/appstore/sync()> | [md](in-app-purchases/storekit-appstore-sync.md) · [raw](in-app-purchases/storekit-appstore-sync.json) | 2026-11-22 | OK |
| Apple In-App Purchase | <https://developer.apple.com/documentation/storekit/in-app-purchase> | [md](in-app-purchases/storekit-in-app-purchase.md) · [raw](in-app-purchases/storekit-in-app-purchase.json) | 2026-11-22 | OK |
| Restoring purchased products | <https://developer.apple.com/documentation/storekit/restoring-purchased-products> | [md](in-app-purchases/storekit-original-restoring-purchased-products.md) · [raw](in-app-purchases/storekit-original-restoring-purchased-products.json) | 2026-11-22 | OK |
| Testing Apple In-App Purchases with sandbox | <https://developer.apple.com/documentation/storekit/testing-in-app-purchases-with-sandbox> | [md](in-app-purchases/storekit-testing-in-sandbox.md) · [raw](in-app-purchases/storekit-testing-in-sandbox.json) | 2026-11-22 | OK |
| Transaction | <https://developer.apple.com/documentation/storekit/transaction> | [md](in-app-purchases/storekit-transaction.md) · [raw](in-app-purchases/storekit-transaction.json) | 2026-11-22 | OK |
| finish() | <https://developer.apple.com/documentation/storekit/transaction/finish()> | [md](in-app-purchases/storekit-transaction-finish.md) · [raw](in-app-purchases/storekit-transaction-finish.json) | 2026-11-22 | OK |
| updates | <https://developer.apple.com/documentation/storekit/transaction/updates> | [md](in-app-purchases/storekit-transaction-updates.md) · [raw](in-app-purchases/storekit-transaction-updates.json) | 2026-11-22 | OK |
| storekit-verifying-receipt-legacy | <https://developer.apple.com/documentation/appstorereceipts/verifyreceipt> | — | 2026-11-22 | **FAILED** — HTTP 404 |
| View and edit In-App Purchase information - Manage In-App Purchases | <https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/view-and-edit-in-app-purchase-information> | [md](in-app-purchases/view-and-edit-in-app-purchase-information.md) · [raw](in-app-purchases/view-and-edit-in-app-purchase-information.html) | 2026-11-22 | OK |

### `subscriptions/`

| Document | Official source | Local files | Retrieved (UTC) | Result |
|---|---|---|---|---|
| Auto-renewable subscription information - In-App Purchases and subscriptions - Reference | <https://developer.apple.com/help/app-store-connect/reference/in-app-purchases-and-subscriptions/auto-renewable-subscription-information> | [md](subscriptions/auto-renewable-subscription-information.md) · [raw](subscriptions/auto-renewable-subscription-information.html) | 2026-11-22 | OK |
| Auto-renewable Subscriptions - App Store | <https://developer.apple.com/app-store/subscriptions/> | [md](subscriptions/auto-renewable-subscriptions-guide.md) · [raw](subscriptions/auto-renewable-subscriptions-guide.html) | 2026-11-22 | OK |
| Create non-renewing subscriptions - Manage subscriptions | <https://developer.apple.com/help/app-store-connect/manage-subscriptions/create-non-renewing-subscriptions> | [md](subscriptions/create-non-renewing-subscriptions.md) · [raw](subscriptions/create-non-renewing-subscriptions.html) | 2026-11-22 | OK |
| Enable billing grace period for auto-renewable subscriptions - Manage subscriptions | <https://developer.apple.com/help/app-store-connect/manage-subscriptions/enable-billing-grace-period-for-auto-renewable-subscriptions> | [md](subscriptions/enable-billing-grace-period.md) · [raw](subscriptions/enable-billing-grace-period.html) | 2026-11-22 | OK |
| Manage pricing for auto-renewable subscriptions - Manage subscriptions | <https://developer.apple.com/help/app-store-connect/manage-subscriptions/manage-pricing-for-auto-renewable-subscriptions> | [md](subscriptions/manage-pricing-for-auto-renewable-subscriptions.md) · [raw](subscriptions/manage-pricing-for-auto-renewable-subscriptions.html) | 2026-11-22 | OK |
| Now Available: Monthly Subscriptions with a 12-Month Commitment | <https://developer.apple.com/news/?id=agq42lxe> | [md](subscriptions/news-2026-04-27-monthly-with-12-month-commitment.md) · [raw](subscriptions/news-2026-04-27-monthly-with-12-month-commitment.html) | 2026-11-22 | OK |
| Get your subscriptions ready for iOS 27 | <https://developer.apple.com/news/?id=likeohx4> | [md](subscriptions/news-2026-09-16-subscriptions-ready-for-ios-27.md) · [raw](subscriptions/news-2026-09-16-subscriptions-ready-for-ios-27.html) | 2026-11-22 | OK |
| Now available: Retention messages for subscriptions | <https://developer.apple.com/news/?id=fk9ps3gv> | [md](subscriptions/news-2026-11-04-retention-messages.md) · [raw](subscriptions/news-2026-11-04-retention-messages.html) | 2026-11-22 | OK |
| Tax and price updates for apps, In-App Purchases, and subscriptions | <https://developer.apple.com/news/?id=4o5ie73a> | [md](subscriptions/news-2026-11-17-tax-and-price-updates.md) · [raw](subscriptions/news-2026-11-17-tax-and-price-updates.html) | 2026-11-22 | OK |
| Offer auto-renewable subscriptions - Manage subscriptions | <https://developer.apple.com/help/app-store-connect/manage-subscriptions/offer-auto-renewable-subscriptions> | [md](subscriptions/offer-auto-renewable-subscriptions.md) · [raw](subscriptions/offer-auto-renewable-subscriptions.html) | 2026-11-22 | OK |
| Set up introductory offers for auto-renewable subscriptions - Manage subscriptions | <https://developer.apple.com/help/app-store-connect/manage-subscriptions/set-up-introductory-offers-for-auto-renewable-subscriptions> | [md](subscriptions/set-up-introductory-offers.md) · [raw](subscriptions/set-up-introductory-offers.html) | 2026-11-22 | OK |
| Set up offer codes - Manage subscriptions | <https://developer.apple.com/help/app-store-connect/manage-subscriptions/set-up-subscription-offer-codes> | [md](subscriptions/set-up-subscription-offer-codes.md) · [raw](subscriptions/set-up-subscription-offer-codes.html) | 2026-11-22 | OK |
| Product.SubscriptionInfo | <https://developer.apple.com/documentation/storekit/product/subscriptioninfo> | [md](subscriptions/storekit-product-subscriptioninfo.md) · [raw](subscriptions/storekit-product-subscriptioninfo.json) | 2026-11-22 | OK |
| showManageSubscriptions(in:) | <https://developer.apple.com/documentation/storekit/appstore/showmanagesubscriptions(in:)> | [md](subscriptions/storekit-show-manage-subscriptions.md) · [raw](subscriptions/storekit-show-manage-subscriptions.json) | 2026-11-22 | OK |
| SubscriptionStoreView | <https://developer.apple.com/documentation/storekit/subscriptionstoreview> | [md](subscriptions/storekit-subscriptionstoreview.md) · [raw](subscriptions/storekit-subscriptionstoreview.json) | 2026-11-22 | OK |

### `privacy-and-security/`

| Document | Official source | Local files | Retrieved (UTC) | Result |
|---|---|---|---|---|
| Adding a privacy manifest to your app or third-party SDK | <https://developer.apple.com/documentation/bundleresources/adding-a-privacy-manifest-to-your-app-or-third-party-sdk> | [md](privacy-and-security/adding-a-privacy-manifest.md) · [raw](privacy-and-security/adding-a-privacy-manifest.json) | 2026-11-22 | OK |
| App Privacy Details - App Store | <https://developer.apple.com/app-store/app-privacy-details/> | [md](privacy-and-security/app-privacy-details.md) · [raw](privacy-and-security/app-privacy-details.html) | 2026-11-22 | OK |
| App Tracking Transparency | <https://developer.apple.com/documentation/apptrackingtransparency> | [md](privacy-and-security/app-tracking-transparency.md) · [raw](privacy-and-security/app-tracking-transparency.json) | 2026-11-22 | OK |
| Manage app privacy - Manage app information | <https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy> | [md](privacy-and-security/asc-manage-app-privacy.md) · [raw](privacy-and-security/asc-manage-app-privacy.html) | 2026-11-22 | OK |
| App privacy - App information - Reference | <https://developer.apple.com/help/app-store-connect/reference/app-information/app-privacy> | [md](privacy-and-security/asc-reference-app-privacy.md) · [raw](privacy-and-security/asc-reference-app-privacy.html) | 2026-11-22 | OK |
| Complying with Encryption Export Regulations | <https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations> | [md](privacy-and-security/complying-with-encryption-export-regulations.md) · [raw](privacy-and-security/complying-with-encryption-export-regulations.json) | 2026-11-22 | OK |
| Declared Age Range | <https://developer.apple.com/documentation/declaredagerange> | [md](privacy-and-security/declared-age-range.md) · [raw](privacy-and-security/declared-age-range.json) | 2026-11-22 | OK |
| Describing data use in privacy manifests | <https://developer.apple.com/documentation/bundleresources/describing-data-use-in-privacy-manifests> | [md](privacy-and-security/describing-data-use-in-privacy-manifests.md) · [raw](privacy-and-security/describing-data-use-in-privacy-manifests.json) | 2026-11-22 | OK |
| Describing use of required reason API | <https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api> | [md](privacy-and-security/describing-use-of-required-reason-api.md) · [raw](privacy-and-security/describing-use-of-required-reason-api.json) | 2026-11-22 | OK |
| New requirement for apps using Sign in with Apple for account creation | <https://developer.apple.com/news/?id=j9zukcr6> | [md](privacy-and-security/news-2025-10-09-siwa-account-creation-requirement.md) · [raw](privacy-and-security/news-2025-10-09-siwa-account-creation-requirement.html) | 2026-11-22 | OK |
| New domain for Sign in with Apple and iCloud+ Hide My Email | <https://developer.apple.com/news/?id=sus6t6ab> | [md](privacy-and-security/news-2026-06-15-siwa-new-domain.md) · [raw](privacy-and-security/news-2026-06-15-siwa-new-domain.html) | 2026-11-22 | OK |
| Update: New domain for Sign in with Apple | <https://developer.apple.com/news/?id=1ptvdtcm> | [md](privacy-and-security/news-2026-08-24-siwa-new-domain-update.md) · [raw](privacy-and-security/news-2026-08-24-siwa-new-domain-update.html) | 2026-11-22 | OK |
| Updates to App Tracking Transparency in the European Union | <https://developer.apple.com/news/?id=idsft9ai> | [md](privacy-and-security/news-2026-09-16-att-updates-eu.md) · [raw](privacy-and-security/news-2026-09-16-att-updates-eu.html) | 2026-11-22 | OK |
| Privacy manifest files | <https://developer.apple.com/documentation/bundleresources/privacy-manifest-files> | [md](privacy-and-security/privacy-manifest-files.md) · [raw](privacy-and-security/privacy-manifest-files.json) | 2026-11-22 | OK |
| Page Not Found | <https://developer.apple.com/support/required-reason-api/> | [md](privacy-and-security/required-reason-api-support.md) · [raw](privacy-and-security/required-reason-api-support.html) | 2026-11-22 | **SOFT_404** — Apple serves a 'Page Not Found' page at this URL (HTTP 200). Requirement captured instead in privacy-and-security/describing-use-of-required-reason-api.md (DocC) and third-party-sdk-requirements.md. |
| Sign in with Apple | <https://developer.apple.com/documentation/signinwithapple> | [md](privacy-and-security/sign-in-with-apple-docs.md) · [raw](privacy-and-security/sign-in-with-apple-docs.json) | 2026-11-22 | OK |
| Sign in with Apple | <https://developer.apple.com/sign-in-with-apple/> | [md](privacy-and-security/sign-in-with-apple-overview.md) · [raw](privacy-and-security/sign-in-with-apple-overview.html) | 2026-11-22 | **REDIRECT_SHELL** — URL redirects to the HIG page, which is a JavaScript shell; full content captured in human-interface-guidelines/hig-sign-in-with-apple.md and privacy-and-security/sign-in-with-apple-docs.md. |
| Processing changes for Sign in with Apple accounts | <https://developer.apple.com/documentation/signinwithapple/processing-changes-for-sign-in-with-apple-accounts> | [md](privacy-and-security/siwa-processing-account-changes.md) · [raw](privacy-and-security/siwa-processing-account-changes.json) | 2026-11-22 | OK |
| Token revocation | <https://developer.apple.com/documentation/signinwithapplerestapi/revoke-tokens> | [md](privacy-and-security/siwa-rest-revoke-tokens.md) · [raw](privacy-and-security/siwa-rest-revoke-tokens.json) | 2026-11-22 | OK |
| Third-party SDK requirements - Support | <https://developer.apple.com/support/third-party-SDK-requirements/> | [md](privacy-and-security/third-party-sdk-requirements.md) · [raw](privacy-and-security/third-party-sdk-requirements.html) | 2026-11-22 | OK |
| User Privacy and Data Use - App Store | <https://developer.apple.com/app-store/user-privacy-and-data-use/> | [md](privacy-and-security/user-privacy-and-data-use.md) · [raw](privacy-and-security/user-privacy-and-data-use.html) | 2026-11-22 | OK |

### `permissions-and-background-modes/`

| Document | Official source | Local files | Retrieved (UTC) | Result |
|---|---|---|---|---|
| CallKit | <https://developer.apple.com/documentation/callkit> | [md](permissions-and-background-modes/callkit.md) · [raw](permissions-and-background-modes/callkit.json) | 2026-11-22 | OK |
| Configuring background execution modes | <https://developer.apple.com/documentation/xcode/configuring-background-execution-modes> | [md](permissions-and-background-modes/configuring-background-execution-modes.md) · [raw](permissions-and-background-modes/configuring-background-execution-modes.json) | 2026-11-22 | OK |
| Configuring your app for media playback | <https://developer.apple.com/documentation/avfoundation/configuring-your-app-for-media-playback> | [md](permissions-and-background-modes/configuring-your-app-for-media-playback.md) · [raw](permissions-and-background-modes/configuring-your-app-for-media-playback.json) | 2026-11-22 | OK |
| NSCameraUsageDescription | <https://developer.apple.com/documentation/bundleresources/information-property-list/nscamerausagedescription> | [md](permissions-and-background-modes/nscamerausagedescription.md) · [raw](permissions-and-background-modes/nscamerausagedescription.json) | 2026-11-22 | OK |
| NSLocalNetworkUsageDescription | <https://developer.apple.com/documentation/bundleresources/information-property-list/nslocalnetworkusagedescription> | [md](permissions-and-background-modes/nslocalnetworkusagedescription.md) · [raw](permissions-and-background-modes/nslocalnetworkusagedescription.json) | 2026-11-22 | OK |
| NSMicrophoneUsageDescription | <https://developer.apple.com/documentation/bundleresources/information-property-list/nsmicrophoneusagedescription> | [md](permissions-and-background-modes/nsmicrophoneusagedescription.md) · [raw](permissions-and-background-modes/nsmicrophoneusagedescription.json) | 2026-11-22 | OK |
| NSPhotoLibraryAddUsageDescription | <https://developer.apple.com/documentation/bundleresources/information-property-list/nsphotolibraryaddusagedescription> | [md](permissions-and-background-modes/nsphotolibraryaddusagedescription.md) · [raw](permissions-and-background-modes/nsphotolibraryaddusagedescription.json) | 2026-11-22 | OK |
| NSPhotoLibraryUsageDescription | <https://developer.apple.com/documentation/bundleresources/information-property-list/nsphotolibraryusagedescription> | [md](permissions-and-background-modes/nsphotolibraryusagedescription.md) · [raw](permissions-and-background-modes/nsphotolibraryusagedescription.json) | 2026-11-22 | OK |
| NSUserTrackingUsageDescription | <https://developer.apple.com/documentation/bundleresources/information-property-list/nsusertrackingusagedescription> | [md](permissions-and-background-modes/nsusertrackingusagedescription.md) · [raw](permissions-and-background-modes/nsusertrackingusagedescription.json) | 2026-11-22 | OK |
| Pushing background updates to your App | <https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app> | [md](permissions-and-background-modes/pushing-background-updates-to-your-app.md) · [raw](permissions-and-background-modes/pushing-background-updates-to-your-app.json) | 2026-11-22 | OK |
| Responding to VoIP Notifications from PushKit | <https://developer.apple.com/documentation/pushkit/responding-to-voip-notifications-from-pushkit> | [md](permissions-and-background-modes/pushkit-responding-to-voip-notifications.md) · [raw](permissions-and-background-modes/pushkit-responding-to-voip-notifications.json) | 2026-11-22 | OK |
| Asking permission to use notifications | <https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications> | [md](permissions-and-background-modes/requesting-authorization-to-use-notifications.md) · [raw](permissions-and-background-modes/requesting-authorization-to-use-notifications.json) | 2026-11-22 | OK |
| UIBackgroundModes | <https://developer.apple.com/documentation/bundleresources/information-property-list/uibackgroundmodes> | [md](permissions-and-background-modes/uibackgroundmodes.md) · [raw](permissions-and-background-modes/uibackgroundmodes.json) | 2026-11-22 | OK |

### `ios-sdk-and-build-requirements/`

| Document | Official source | Local files | Retrieved (UTC) | Result |
|---|---|---|---|---|
| App build statuses - App uploads - Reference | <https://developer.apple.com/help/app-store-connect/reference/app-uploads/app-build-statuses> | [md](ios-sdk-and-build-requirements/asc-app-build-statuses.md) · [raw](ios-sdk-and-build-requirements/asc-app-build-statuses.html) | 2026-11-22 | OK |
| Maximum build file sizes - App uploads - Reference | <https://developer.apple.com/help/app-store-connect/reference/app-uploads/maximum-build-file-sizes> | [md](ios-sdk-and-build-requirements/asc-maximum-build-file-sizes.md) · [raw](ios-sdk-and-build-requirements/asc-maximum-build-file-sizes.html) | 2026-11-22 | OK |
| Upload builds - Manage builds | <https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds> | [md](ios-sdk-and-build-requirements/asc-upload-builds.md) · [raw](ios-sdk-and-build-requirements/asc-upload-builds.html) | 2026-11-22 | OK |
| Latest News | <https://developer.apple.com/news/> | [md](ios-sdk-and-build-requirements/developer-news-index.md) · [raw](ios-sdk-and-build-requirements/developer-news-index.html) | 2026-11-22 | OK |
| Submitting - App Store | <https://developer.apple.com/ios/submit/> | [md](ios-sdk-and-build-requirements/ios-submit.md) · [raw](ios-sdk-and-build-requirements/ios-submit.html) | 2026-11-22 | OK |
| Upcoming SDK minimum requirements | <https://developer.apple.com/news/?id=ueeok6yw> | [md](ios-sdk-and-build-requirements/news-2026-02-03-upcoming-sdk-minimum-requirements.md) · [raw](ios-sdk-and-build-requirements/news-2026-02-03-upcoming-sdk-minimum-requirements.html) | 2026-11-22 | OK |
| App Store submissions now open for the latest OS releases | <https://developer.apple.com/news/?id=k1mtkt1k> | [md](ios-sdk-and-build-requirements/news-2026-09-09-submissions-open-latest-os.md) · [raw](ios-sdk-and-build-requirements/news-2026-09-09-submissions-open-latest-os.html) | 2026-11-22 | OK |
| Upcoming Requirements | <https://developer.apple.com/news/upcoming-requirements/> | [md](ios-sdk-and-build-requirements/upcoming-requirements.md) · [raw](ios-sdk-and-build-requirements/upcoming-requirements.html) | 2026-11-22 | OK |
| SDK and system requirements - Xcode | <https://developer.apple.com/support/xcode/> | [md](ios-sdk-and-build-requirements/xcode-support.md) · [raw](ios-sdk-and-build-requirements/xcode-support.html) | 2026-11-22 | OK |

### `human-interface-guidelines/`

| Document | Official source | Local files | Retrieved (UTC) | Result |
|---|---|---|---|---|
| Apple In-App Purchase | <https://developer.apple.com/design/human-interface-guidelines/apple-in-app-purchase> | [md](human-interface-guidelines/hig-in-app-purchase.md) · [raw](human-interface-guidelines/hig-in-app-purchase.json) | 2026-11-22 | OK |
| Launching | <https://developer.apple.com/design/human-interface-guidelines/launching> | [md](human-interface-guidelines/hig-launching.md) · [raw](human-interface-guidelines/hig-launching.json) | 2026-11-22 | OK |
| Managing accounts | <https://developer.apple.com/design/human-interface-guidelines/managing-accounts> | [md](human-interface-guidelines/hig-managing-accounts.md) · [raw](human-interface-guidelines/hig-managing-accounts.json) | 2026-11-22 | OK |
| Onboarding | <https://developer.apple.com/design/human-interface-guidelines/onboarding> | [md](human-interface-guidelines/hig-onboarding.md) · [raw](human-interface-guidelines/hig-onboarding.json) | 2026-11-22 | OK |
| Privacy | <https://developer.apple.com/design/human-interface-guidelines/privacy> | [md](human-interface-guidelines/hig-privacy.md) · [raw](human-interface-guidelines/hig-privacy.json) | 2026-11-22 | OK |
| Sign in with Apple | <https://developer.apple.com/design/human-interface-guidelines/sign-in-with-apple> | [md](human-interface-guidelines/hig-sign-in-with-apple.md) · [raw](human-interface-guidelines/hig-sign-in-with-apple.json) | 2026-11-22 | OK |

### `metadata-and-product-pages/`

| Document | Official source | Local files | Retrieved (UTC) | Result |
|---|---|---|---|---|
| Add an app icon - Manage app information | <https://developer.apple.com/help/app-store-connect/manage-app-information/add-an-app-icon> | [md](metadata-and-product-pages/add-an-app-icon.md) · [raw](metadata-and-product-pages/add-an-app-icon.html) | 2026-11-22 | OK |
| Age ratings values and definitions - App information - Reference | <https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions> | [md](metadata-and-product-pages/age-ratings-values-and-definitions.md) · [raw](metadata-and-product-pages/age-ratings-values-and-definitions.html) | 2026-11-22 | OK |
| App preview specifications - App information - Reference | <https://developer.apple.com/help/app-store-connect/reference/app-information/app-preview-specifications> | [md](metadata-and-product-pages/app-preview-specifications.md) · [raw](metadata-and-product-pages/app-preview-specifications.html) | 2026-11-22 | OK |
| App Store localizations - App information - Reference | <https://developer.apple.com/help/app-store-connect/reference/app-information/app-store-localizations> | [md](metadata-and-product-pages/app-store-localizations.md) · [raw](metadata-and-product-pages/app-store-localizations.html) | 2026-11-22 | OK |
| Updated age ratings in App Store Connect | <https://developer.apple.com/news/?id=ks775ehf> | [md](metadata-and-product-pages/news-2025-07-24-updated-age-ratings.md) · [raw](metadata-and-product-pages/news-2025-07-24-updated-age-ratings.html) | 2026-11-22 | OK |
| Age rating questionnaire now includes social media questions | <https://developer.apple.com/news/?id=tlur8uvi> | [md](metadata-and-product-pages/news-2026-07-09-age-rating-social-media-questions.md) · [raw](metadata-and-product-pages/news-2026-07-09-age-rating-social-media-questions.html) | 2026-11-22 | OK |
| Showcase your apps with new assets on the App Store | <https://developer.apple.com/news/?id=ljpl7kyn> | [md](metadata-and-product-pages/news-2026-10-05-new-assets-on-the-app-store.md) · [raw](metadata-and-product-pages/news-2026-10-05-new-assets-on-the-app-store.html) | 2026-11-22 | OK |
| Upcoming: New age rating content descriptors in App Store Connect | <https://developer.apple.com/news/?id=yxkh08us> | [md](metadata-and-product-pages/news-2026-11-02-new-age-rating-content-descriptors.md) · [raw](metadata-and-product-pages/news-2026-11-02-new-age-rating-content-descriptors.html) | 2026-11-22 | OK |
| Creating Your Product Page - App Store | <https://developer.apple.com/app-store/product-page/> | [md](metadata-and-product-pages/product-page.md) · [raw](metadata-and-product-pages/product-page.html) | 2026-11-22 | OK |
| Provide a custom license agreement - Manage app information | <https://developer.apple.com/help/app-store-connect/manage-app-information/provide-a-custom-license-agreement> | [md](metadata-and-product-pages/provide-a-custom-license-agreement.md) · [raw](metadata-and-product-pages/provide-a-custom-license-agreement.html) | 2026-11-22 | OK |
| Screenshot specifications - App information - Reference | <https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications> | [md](metadata-and-product-pages/screenshot-specifications.md) · [raw](metadata-and-product-pages/screenshot-specifications.html) | 2026-11-22 | OK |
| Set an app age rating - Manage app information | <https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating> | [md](metadata-and-product-pages/set-an-app-age-rating.md) · [raw](metadata-and-product-pages/set-an-app-age-rating.html) | 2026-11-22 | OK |

### `regional-and-territory-requirements/`

| Document | Official source | Local files | Retrieved (UTC) | Result |
|---|---|---|---|---|
| App pricing and availability - Pricing and availability - Reference | <https://developer.apple.com/help/app-store-connect/reference/pricing-and-availability/app-pricing-and-availability> | [md](regional-and-territory-requirements/app-pricing-and-availability.md) · [raw](regional-and-territory-requirements/app-pricing-and-availability.html) | 2026-11-22 | OK |
| View China mainland compliance information - Manage compliance information | <https://developer.apple.com/help/app-store-connect/manage-compliance-information/view-china-mainland-compliance-information> | [md](regional-and-territory-requirements/china-mainland-compliance-information.md) · [raw](regional-and-territory-requirements/china-mainland-compliance-information.html) | 2026-11-22 | OK |
| Changes for apps in the European Union - Support | <https://developer.apple.com/support/dma-and-apps-in-the-eu/> | [md](regional-and-territory-requirements/eu-dma-and-apps.md) · [raw](regional-and-territory-requirements/eu-dma-and-apps.html) | 2026-11-22 | OK |
| Manage Korea compliance information - Manage compliance information | <https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-korea-compliance-information> | [md](regional-and-territory-requirements/korea-compliance-information.md) · [raw](regional-and-territory-requirements/korea-compliance-information.html) | 2026-11-22 | OK |
| Manage availability for your app on the App Store - Manage your app's availability | <https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/manage-availability-for-your-app-on-the-app-store> | [md](regional-and-territory-requirements/manage-availability-on-the-app-store.md) · [raw](regional-and-territory-requirements/manage-availability-on-the-app-store.html) | 2026-11-22 | OK |
| New requirement for apps on the App Store in the European Union | <https://developer.apple.com/news/?id=6agg0lja> | [md](regional-and-territory-requirements/news-2025-02-18-eu-trader-requirement.md) · [raw](regional-and-territory-requirements/news-2025-02-18-eu-trader-requirement.html) | 2026-11-22 | OK |
| New requirements for apps available in Texas | <https://developer.apple.com/news/?id=btkirlj8> | [md](regional-and-territory-requirements/news-2025-10-08-texas-requirements.md) · [raw](regional-and-territory-requirements/news-2025-10-08-texas-requirements.html) | 2026-11-22 | OK |
| New Requirements for Social Media Apps in Australia | <https://developer.apple.com/news/?id=y1bckxf8> | [md](regional-and-territory-requirements/news-2025-12-08-australia-social-media-apps.md) · [raw](regional-and-territory-requirements/news-2025-12-08-australia-social-media-apps.html) | 2026-11-22 | OK |
| Update on age requirements for apps distributed in Texas | <https://developer.apple.com/news/?id=8jzbigf4> | [md](regional-and-territory-requirements/news-2025-12-23-texas-age-requirements.md) · [raw](regional-and-territory-requirements/news-2025-12-23-texas-age-requirements.html) | 2026-11-22 | OK |
| Age requirements for apps distributed in Brazil, Australia, Singapore, Utah, and Louisiana | <https://developer.apple.com/news/?id=f5zj08ey> | [md](regional-and-territory-requirements/news-2026-02-24-age-requirements-br-au-sg-ut-la.md) · [raw](regional-and-territory-requirements/news-2026-02-24-age-requirements-br-au-sg-ut-la.html) | 2026-11-22 | OK |
| Adjustments to the China storefront of the App Store on iOS and iPadOS | <https://developer.apple.com/news/?id=dadukodv> | [md](regional-and-territory-requirements/news-2026-03-12-china-storefront-adjustments.md) · [raw](regional-and-territory-requirements/news-2026-03-12-china-storefront-adjustments.html) | 2026-11-22 | OK |
| Upcoming changes to age ratings in Australia and Vietnam | <https://developer.apple.com/news/?id=yrrb45pw> | [md](regional-and-territory-requirements/news-2026-05-21-age-ratings-australia-vietnam.md) · [raw](regional-and-territory-requirements/news-2026-05-21-age-ratings-australia-vietnam.html) | 2026-11-22 | OK |
| Update for Apps Distributed in Texas | <https://developer.apple.com/news/?id=sg176nne> | [md](regional-and-territory-requirements/news-2026-06-03-texas-update.md) · [raw](regional-and-territory-requirements/news-2026-06-03-texas-update.html) | 2026-11-22 | OK |
| Changes to iOS in Brazil | <https://developer.apple.com/news/?id=dhwadr2x> | [md](regional-and-territory-requirements/news-2026-06-18-changes-to-ios-in-brazil.md) · [raw](regional-and-territory-requirements/news-2026-06-18-changes-to-ios-in-brazil.html) | 2026-11-22 | OK |
| Updates to age ratings for the Republic of Korea | <https://developer.apple.com/news/?id=oj3r9pvw> | [md](regional-and-territory-requirements/news-2026-08-12-age-ratings-korea.md) · [raw](regional-and-territory-requirements/news-2026-08-12-age-ratings-korea.html) | 2026-11-22 | OK |
| Changes for apps in the European Union | <https://developer.apple.com/news/?id=gmws0jgp> | [md](regional-and-territory-requirements/news-2026-08-18-changes-for-apps-in-eu.md) · [raw](regional-and-territory-requirements/news-2026-08-18-changes-for-apps-in-eu.html) | 2026-11-22 | OK |
| Support | <https://developer.apple.com/support/storekit-external-entitlement-us/> | [md](regional-and-territory-requirements/storekit-external-purchase-link-us.md) · [raw](regional-and-territory-requirements/storekit-external-purchase-link-us.html) | 2026-11-22 | **SOFT_404** — URL redirects to the generic Support index; page no longer exists at this address. Not applicable: the app offers no external purchase links. |

