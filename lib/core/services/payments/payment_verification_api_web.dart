import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

import '../../config/backend_config.dart';
import 'payment_models.dart';
import 'payment_verification_api_platform.dart';

class WebPaymentVerificationApiPlatform implements PaymentVerificationApiPlatform {
  @override
  Future<VerifyPaymentResult> verifyFlutterwavePayment({
    required String attemptId,
    required String transactionId,
    required String txRef,
    required String idToken,
  }) async {
    // NOTE: This requires CORS enabled on the HTTPS function if you build web.
    final url = BackendConfig.verifyFlutterwavePaymentUrl().toString();

    final req = await html.HttpRequest.request(
      url,
      method: 'POST',
      sendData: jsonEncode({'attemptId': attemptId, 'transactionId': transactionId, 'txRef': txRef}),
      requestHeaders: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $idToken',
      },
    );

    Map<String, dynamic> json;
    try {
      json = (jsonDecode(req.responseText ?? '{}') as Map).cast<String, dynamic>();
    } catch (_) {
      return VerifyPaymentResult.failed('Verification failed: invalid server response.');
    }

    final ok = json['ok'] == true;
    if (!ok) {
      final err = (json['error'] ?? 'Verification failed').toString();
      return VerifyPaymentResult.failed(err);
    }

    return VerifyPaymentResult(
      ok: true,
      paymentId: (json['paymentId'] ?? '').toString(),
      receiptId: (json['receiptId'] ?? '').toString(),
      paidAtMs: (json['paidAtMs'] is num) ? (json['paidAtMs'] as num).toInt() : 0,
      message: 'OK',
    );
  }
}
