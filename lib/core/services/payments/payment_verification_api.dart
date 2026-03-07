import 'payment_models.dart';
import 'payment_verification_api_factory.dart';
import 'payment_verification_api_platform.dart';

class PaymentVerificationApi {
  PaymentVerificationApi._();
  static final PaymentVerificationApi instance = PaymentVerificationApi._();

  final PaymentVerificationApiPlatform _impl = createPaymentVerificationApiPlatform();

  Future<VerifyPaymentResult> verifyFlutterwavePayment({
    required String attemptId,
    required String transactionId,
    required String txRef,
    required String idToken,
  }) {
    return _impl.verifyFlutterwavePayment(
      attemptId: attemptId,
      transactionId: transactionId,
      txRef: txRef,
      idToken: idToken,
    );
  }
}
