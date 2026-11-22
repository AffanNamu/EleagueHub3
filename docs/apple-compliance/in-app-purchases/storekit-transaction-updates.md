<!--
Source: https://developer.apple.com/documentation/storekit/transaction/updates
Final URL: https://developer.apple.com/tutorials/data/documentation/storekit/transaction/updates.json
Retrieved (UTC): 2026-11-22T04:11:57Z
Raw file: storekit-transaction-updates.json
SHA-256 of raw: 2a53dde5e48e4e783049da83cf789254b01c93005f6d76bcab2de18553f70458
Extraction: automated text extraction for offline search; the raw file is authoritative.
-->

# updates

_Type Property_

Platforms: iOS 15.0, iPadOS 15.0, Mac Catalyst 15.0, macOS 12.0, tvOS 15.0, visionOS 1.0, watchOS 8.0

The asynchronous sequence that emits a transaction when the system creates or updates transactions that occur outside the app or on other devices.

```swift
static var updates: Transaction.Transactions { get }
```

### Discussion

Use [updates](https://developer.apple.com/documentation/storekit/transaction/updates) to receive new transactions while the app is running. This sequence receives transactions that occur outside of the app, such as Ask to Buy transactions, offer code redemptions, and purchases that customers make in the App Store. It also emits transactions that customers complete in your app on another device.

Note that after a successful Apple In-App Purchase on the same device, StoreKit returns the transaction through [Product.PurchaseResult.success(_:)](https://developer.apple.com/documentation/storekit/product/purchaseresult/success(_:)).

> **Important:** Create a [Task](https://developer.apple.com/documentation/swift/task) to iterate through the transactions from the listener as soon as your app launches. If your app has unfinished transactions, the [updates](https://developer.apple.com/documentation/storekit/transaction/updates) listener receives them once, immediately after the app launches. Without the [Task](https://developer.apple.com/documentation/swift/task) to listen for these transactions, your app may miss them.

The following example shows a class that creates a [Task](https://developer.apple.com/documentation/swift/task) when it initializes. The task retrieves and processes any unfinished transactions.

```swift
final class TransactionObserver {
    
    var updates: Task<Void, Never>? = nil
    
    init() {
        updates = newTransactionListenerTask()
    }

    deinit {
        // Cancel the update handling task when you deinitialize the class.
        updates?.cancel()
    }
    
    private func newTransactionListenerTask() -> Task<Void, Never> {
        Task(priority: .background) {
            for await verificationResult in Transaction.updates {
                self.handle(updatedTransaction: verificationResult)
            }
        }
    }
    
    private func handle(updatedTransaction verificationResult: VerificationResult<Transaction>) {
        guard case .verified(let transaction) = verificationResult else {
            // Ignore unverified transactions.
            return
        }

        if let revocationDate = transaction.revocationDate {
            // Remove access to the product identified by transaction.productID.
            // Transaction.revocationReason provides details about
            // the revoked transaction.
            <#...#>
        } else if let expirationDate = transaction.expirationDate,
            expirationDate < Date() {
            // Do nothing, this subscription is expired.
            return
        } else if transaction.isUpgraded {
            // Do nothing, there is an active transaction
            // for a higher level of service.
            return
        } else {
            // Provide access to the product identified by
            // transaction.productID.
            <#...#>
        }
    }
    
}
```

The [updates](https://developer.apple.com/documentation/storekit/transaction/updates) listener receives unfinished transactions just once at app launch, but you can use the [unfinished](https://developer.apple.com/documentation/storekit/transaction/unfinished) listener to get your app’s unfinished transactions at any time. For information on finishing transactions, see [finish()](https://developer.apple.com/documentation/storekit/transaction/finish()).

## Related Documentation

- [Supporting offer codes in your app](https://developer.apple.com/documentation/storekit/supporting-offer-codes-in-your-app) — Enable customers to redeem offer codes through the App Store or within your app.

- [Testing Ask to Buy in the sandbox environment](https://developer.apple.com/documentation/storekit/testing-ask-to-buy-in-the-sandbox-environment) — Verify that your app handles Ask to Buy purchases, including those made outside your app.

## Transaction history and entitlements

- [Transaction](https://developer.apple.com/documentation/storekit/transaction) — Information that represents the customer’s purchase of a product in your app.

- [all](https://developer.apple.com/documentation/storekit/transaction/all) — A sequence that emits all the customer’s transactions for your app.

- [currentEntitlements](https://developer.apple.com/documentation/storekit/transaction/currententitlements) — A sequence of the latest transactions that entitle a customer to Apple In-App Purchases and subscriptions.