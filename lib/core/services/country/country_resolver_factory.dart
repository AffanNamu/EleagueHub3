import 'country_resolver_factory_fallback.dart'
    if (dart.library.io) 'country_resolver_factory_io.dart'
    if (dart.library.html) 'country_resolver_factory_web.dart' as impl;

import 'country_resolver_platform.dart';

export 'country_resolver_platform.dart';

/// Returns the platform-appropriate resolver implementation (IO/Web/Fallback).
CountryResolverPlatform createCountryResolverPlatform() => impl.createCountryResolverPlatform();
