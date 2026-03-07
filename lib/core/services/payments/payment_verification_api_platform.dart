import 'payment_models.dart';

abstract class PaymentVerificationApiPlatform {
  Future<VerifyPaymentResult> verifyFlutterwavePayment({
    required String attemptId,
    required String transactionId,
    required String txRef,
    required String idToken,
  });
}
