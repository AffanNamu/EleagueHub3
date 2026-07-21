import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/routing/app_router.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/theme_controller.dart';

/// The web entry-point app.
///
/// We now use [MaterialApp.router] with the SAME [appRouter] used by the
/// mobile app. This gives the web shell full access to GoRouter so that
/// [GoRouter.of(context).push('/leagues/create')] works from any widget
/// inside the web tree — including [WebDesktopShellScreen] and its children.
///
/// Session gating (pairing vs shell) is handled by the router redirect
/// and [WebSessionGateScreen] — see [app_router.dart].
class EleagueHubWebApp extends ConsumerWidget {
  const EleagueHubWebApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeControllerProvider).mode;

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'eSportlyic Web',
      themeMode: themeMode,
      theme: AppTheme.skyTheme(),
      darkTheme: AppTheme.navyTheme(),
      routerConfig: appRouter,
    );
  }
}
