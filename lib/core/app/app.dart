// core/app/app.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../locale/app_localizations.dart';
import '../locale/locale_controller.dart';
import '../routing/app_router.dart';
import '../services/connectivity_service.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import '../widgets/offline_banner.dart';

class EleagueHubApp extends ConsumerWidget {
  const EleagueHubApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeControllerProvider).mode;
    final localeState = ref.watch(localeControllerProvider);

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      onGenerateTitle: (context) => context.l10n.appName,
      themeMode: themeMode,
      theme: AppTheme.skyTheme(),
      darkTheme: AppTheme.navyTheme(),
      locale: localeState.locale,
      supportedLocales: LocaleController.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: appRouter,
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        final clampedScale = mq.textScaler.clamp(
          minScaleFactor: 0.9,
          maxScaleFactor: 1.3,
        );

        return Directionality(
          textDirection: localeState.direction,
          child: MediaQuery(
            data: mq.copyWith(textScaler: clampedScale),
            child: Stack(
              children: [
                // ─────────────────────────────────────────────────────────────
                // IMPORTANT CHANGE:
                // Removed PermissionWrapper that was requesting permissions
                // (camera/mic/notifications/bluetooth) immediately on app start.
                //
                // Permissions must be requested ONLY when user triggers the
                // corresponding feature (e.g. start call, start live, enable notifications).
                // ─────────────────────────────────────────────────────────────
                child ?? const SizedBox.shrink(),

                // ─────────────────────────────────────────────────────────────
                // Notification tap -> route navigation
                //
                // This only initializes local notifications plugin to capture taps.
                // It does NOT request notification permission.
                // ─────────────────────────────────────────────────────────────
                const _NotificationTapRouter(),

                // ONLINE-ONLY: show a simple offline indicator, but do not enable local fallback.
                ValueListenableBuilder<bool>(
                  valueListenable: ConnectivityService.instance.isConnected,
                  builder: (context, online, _) {
                    return online ? const SizedBox.shrink() : const OfflineBanner();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _NotificationTapRouter extends StatefulWidget {
  const _NotificationTapRouter();

  @override
  State<_NotificationTapRouter> createState() => _NotificationTapRouterState();
}

class _NotificationTapRouterState extends State<_NotificationTapRouter> {
  StreamSubscription<String>? _sub;

  @override
  void initState() {
    super.initState();

    // ─────────────────────────────────────────────────────────────
    // Safe to call at startup:
    // - Initializes local notifications plugin
    // - Creates Android notification channels
    // - Does NOT request notification permission
    // Permission must be requested by user action via:
    //   PushMessagingService.instance.requestNotificationPermission()
    //   OR NotificationService().requestPermissionIfNeeded()
    // ─────────────────────────────────────────────────────────────
    // ignore: discarded_futures
    NotificationService().init();

    _sub = NotificationService().onNotificationTap.listen((route) {
      final r = route.trim();
      if (r.isEmpty) return;
      if (!r.startsWith('/')) return;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        appRouter.go(r);
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
