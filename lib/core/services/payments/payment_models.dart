class PaymentLineItem {
  /// Required product types for analytics:
  /// - league
  /// - coupon
  /// - masterLink
  /// - appUnlock
  final String productType;

  /// Optional detail: league_creation, league_access, coupon_purchase, etc.
  final String productSubType;

  final int quantity;

  /// Revenue attributed to this line item (in the payment currency).
  final double amount;

  const PaymentLineItem({
    required this.productType,
    required this.productSubType,
    required this.quantity,
    required this.amount,
  });

  Map<String, dynamic> toMap() => {
        'productType': productType,
        'productSubType': productSubType,
        'quantity': quantity,
        'amount': amount,
      };
}

class PaymentAttemptCreate {
  final String provider; // flutterwave
  final String currency; // NGN/USD
  final double amount; // numeric (for analytics)
  final String amountStr; // flutterwave string format

  final String userId; // auth uid

  final String leagueId;
  final String leagueName;

  final List<PaymentLineItem> items;

  /// Optional metadata
  final String masterLeagueId;
  final String couponCode;

  const PaymentAttemptCreate({
    required this.provider,
    required this.currency,
    required this.amount,
    required this.amountStr,
    required this.userId,
    required this.leagueId,
    required this.leagueName,
    required this.items,
    this.masterLeagueId = '',
    this.couponCode = '',
  });

  Map<String, dynamic> toFirestore({
    required String attemptId,
    required int createdAtMs,
  }) {
    return <String, dynamic>{
      'attemptId': attemptId,
      'provider': provider,
      'currency': currency,
      'amount': amount,
      'amountStr': amountStr,
      'userId': userId,
      'leagueId': leagueId,
      'leagueName': leagueName,
      'masterLeagueId': masterLeagueId,
      'couponCode': couponCode,
      'status': 'initiated', // initiated -> client_success|cancelled|client_failed
      'createdAtMs': createdAtMs,
      'updatedAtMs': createdAtMs,
      'items': items.map((e) => e.toMap()).toList(growable: false),
    };
  }
}

/// Result of writing a successful payment record (client-side).
class ClientRecordPaymentResult {
  final String paymentId;
  final String receiptId;
  final int paidAtMs;

  const ClientRecordPaymentResult({
    required this.paymentId,
    required this.receiptId,
    required this.paidAtMs,
  });
}
