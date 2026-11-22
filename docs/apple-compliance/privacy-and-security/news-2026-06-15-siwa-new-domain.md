<!--
Source: https://developer.apple.com/news/?id=sus6t6ab
Final URL: https://developer.apple.com/news/?id=sus6t6ab
Retrieved (UTC): 2026-11-22T04:12:29Z
Raw file: news-2026-06-15-siwa-new-domain.html
SHA-256 of raw: 1d560215cd260869446f1b1976bd10d76f107ee1df2d029160610161b9a11383
Extraction: automated text extraction for offline search; the raw file is authoritative.
-->

![New domain for Sign in with Apple and iCloud+ Hide My Email](/assets/elements/icons/icloud/icloud-128x128_2x.png)

## New domain for Sign in with Apple and iCloud+ Hide My Email

June 15, 2026

**Note:** This announcement contains outdated information. Please refer to [Update: New domain for Sign in with Apple](https://developer.apple.com/news/?id=1ptvdtcm) for the latest guidance.

Later this summer, Apple will unify the email domains used by Sign in with Apple and iCloud+ Hide My Email under a single, shared domain: **private.icloud.com**.

New addresses generated for both features will be issued on the new domain. For example:

- Sign in with Apple addresses, previously issued on `privaterelay.appleid.com`, will be issued on `private.icloud.com`.

&nbsp;

- iCloud+ Hide My Email addresses, previously issued on `icloud.com`, will be issued on `private.icloud.com`.

Existing addresses on the legacy domains will continue to work and forward mail to users without interruption.

### What you need to do

- Developers with apps or websites that use Sign in with Apple should ensure that their account systems, email validation logic, and allowlists accept addresses on the new `private.icloud.com` domain in addition to existing domains: `privaterelay.appleid.com` and `icloud.com`.

&nbsp;

- Email service providers should update any domain-based filtering, suppression lists, or routing rules that explicitly enumerate relay domains so that the new `private.icloud.com` domain is included.

[Learn more about Sign in with Apple](https://developer.apple.com/sign-in-with-apple/)

[Communicating using the Private Email Relay Service](https://developer.apple.com/documentation/signinwithapple/communicating-using-the-private-email-relay-service)

- 
- 
- 
- 
