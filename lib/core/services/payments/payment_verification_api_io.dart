import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../config/backend_config.dart';
import 'payment_models.dart';
import 'payment_verification_api_platform.dart';

class IoPaymentVerificationApiPlatform implements PaymentVerificationApiPlatform {
  @override
  Future<VerifyPaymentResult> verifyFlutterwavePayment({
    required String attemptId,
    required String transactionId,
    required String txRef,
    required String idToken,
  }) async {
    final url = BackendConfig.verifyFlutterwavePaymentUrl();

    final client = HttpClient();
    try {
      final req = await client.postUrl(url).timeout(const Duration(seconds: 6));
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $idToken');

      req.add(utf8.encode(jsonEncode({
        'attemptId': attemptId,
        'transactionId': transactionId,
        'txRef': txRef,
      })));

      final res = await req.close().timeout(const Duration(seconds: 15));
      final body = await utf8.decodeStream(res).timeout(const Duration(seconds: 15));

      Map<String, dynamic> json;
      try {
        json = (jsonDecode(body) as Map).cast<String, dynamic>();
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
    } on TimeoutException {
      return VerifyPaymentResult.failed('Verification timed out. Please try again.');
    } catch (e) {
      return VerifyPaymentResult.failed('Verification failed: $e');
    } finally {
      client.close(force: true);
    }
  }
}
