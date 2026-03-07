import 'payment_verification_api_factory_fallback.dart'
    if (dart.library.io) 'payment_verification_api_factory_io.dart'
    if (dart.library.html) 'payment_verification_api_factory_web.dart';

import 'payment_verification_api_platform.dart';

PaymentVerificationApiPlatform createPaymentVerificationApiPlatform();
