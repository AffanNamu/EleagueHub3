import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

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
                PermissionWrapper(child: child ?? const SizedBox.shrink()),

                // Notification tap -> route navigation
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

    // Ensure plugin is initialized once.
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

class PermissionWrapper extends StatefulWidget {
  final Widget child;
  const PermissionWrapper({super.key, required this.child});

  @override
  State<PermissionWrapper> createState() => _PermissionWrapperState();
}

class _PermissionWrapperState extends State<PermissionWrapper> {
  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    await [
      Permission.camera,
      Permission.microphone,
      Permission.notification,
      Permission.bluetoothConnect,
    ].request();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
