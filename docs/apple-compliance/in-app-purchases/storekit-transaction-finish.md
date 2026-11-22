<!--
Source: https://developer.apple.com/documentation/storekit/transaction/finish()
Final URL: https://developer.apple.com/tutorials/data/documentation/storekit/transaction/finish().json
Retrieved (UTC): 2026-11-22T04:11:57Z
Raw file: storekit-transaction-finish.json
SHA-256 of raw: 324ae1811f9d04bec9de332b0f7617b351037f2801055fbf31127d0295bb84b3
Extraction: automated text extraction for offline search; the raw file is authoritative.
-->

# finish()

_Instance Method_

Platforms: iOS 15.0, iPadOS 15.0, Mac Catalyst 15.0, macOS 12.0, tvOS 15.0, visionOS 1.0, watchOS 8.0

Indicates to the App Store that the app delivered the purchased content or enabled the service to finish the transaction.

```swift
func finish() async
```

### Discussion

Call [finish()](https://developer.apple.com/documentation/storekit/transaction/finish()) to complete a transaction after you deliver the purchased content or enable the purchased service. For on-demand resources, don’t finish the transaction until the app completes downloading the resource or you’ve otherwise delivered the resource.

## Finishing the transaction

- [unfinished](https://developer.apple.com/documentation/storekit/transaction/unfinished) — A sequence that emits unfinished transactions for the customer.