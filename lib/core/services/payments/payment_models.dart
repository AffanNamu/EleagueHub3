class PaymentLineItem {
  final String productType;
  final String productSubType;
  final int quantity;
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
  final String provider;
  final String currency;
  final double amount;
  final String amountStr;
  final String userId;

  final String leagueId;
  final String leagueName;

  final List<PaymentLineItem> items;

  final String masterLeagueId;
  final String couponCode;

  final String productType;
  final String productSubType;

  final Map<String, dynamic> metadata;

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
    this.productType = '',
    this.productSubType = '',
    this.metadata = const <String, dynamic>{},
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
      'productType': productType,
      'productSubType': productSubType,
      'metadata': metadata,
      'status': 'initiated',
      'createdAtMs': createdAtMs,
      'updatedAtMs': createdAtMs,
      'items': items.map((e) => e.toMap()).toList(growable: false),
    };
  }
}

class PaymentVerificationResult {
  final bool success;
  final String provider;
  final String paymentId;
  final String receiptId;
  final int paidAtMs;
  final String transactionId;
  final String txRef;
  final String status;
  final String currency;
  final double amount;
  final String amountStr;
  final String? errorMessage;
  final Map<String, dynamic> raw;

  const PaymentVerificationResult({
    required this.success,
    required this.provider,
    required this.paymentId,
    required this.receiptId,
    required this.paidAtMs,
    required this.transactionId,
    required this.txRef,
    required this.status,
    required this.currency,
    required this.amount,
    required this.amountStr,
    required this.errorMessage,
    required this.raw,
  });

  factory PaymentVerificationResult.failed({
    required String provider,
    required String errorMessage,
    String paymentId = '',
    String receiptId = '',
    int paidAtMs = 0,
    String transactionId = '',
    String txRef = '',
    String status = 'failed',
    String currency = '',
    double amount = 0,
    String amountStr = '0',
    Map<String, dynamic> raw = const <String, dynamic>{},
  }) {
    return PaymentVerificationResult(
      success: false,
      provider: provider,
      paymentId: paymentId,
      receiptId: receiptId,
      paidAtMs: paidAtMs,
      transactionId: transactionId,
      txRef: txRef,
      status: status,
      currency: currency,
      amount: amount,
      amountStr: amountStr,
      errorMessage: errorMessage,
      raw: raw,
    );
  }
}

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
