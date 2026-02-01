import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../routing/app_router.dart';
import '../theme/theme_controller.dart';

class EleagueHubApp extends ConsumerWidget {
  const EleagueHubApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(themeControllerProvider);

    final mq = MediaQuery.of(context);
    final clampedScale = mq.textScaler.clamp(
      minScaleFactor: 0.9,
      maxScaleFactor: 1.3,
    );

    return MediaQuery(
      data: mq.copyWith(textScaler: clampedScale),
      child: Router(
        routerDelegate: appRouter.routerDelegate,
        routeInformationParser: appRouter.routeInformationParser,
        routeInformationProvider: appRouter.routeInformationProvider,
      ),
    );
  }
}
