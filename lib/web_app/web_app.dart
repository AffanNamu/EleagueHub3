import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/locale/app_localizations.dart';
import '../core/locale/locale_controller.dart';
import 'presentation/web_pairing_screen.dart';

class EleagueHubWebApp extends StatelessWidget {
  const EleagueHubWebApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      onGenerateTitle: (context) => context.l10n.appName,
      themeMode: ThemeMode.dark,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorSchemeSeed: const Color(0xFF25D366),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF25D366),
      ),
      locale: const Locale('en'),
      supportedLocales: LocaleController.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        ErrorWidget.builder = (FlutterErrorDetails details) {
          return Material(
            color: const Color(0xFF0B141A),
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 720),
                margin: const EdgeInsets.all(24),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF202C33),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.redAccent.withOpacity(0.25)),
                ),
                child: SingleChildScrollView(
                  child: DefaultTextStyle(
                    style: const TextStyle(color: Colors.white),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Web UI crashed',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Colors.redAccent,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(details.exceptionAsString()),
                        const SizedBox(height: 12),
                        if (details.stack != null)
                          Text(
                            details.stack.toString(),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white70,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        };

        return child ?? const SizedBox.shrink();
      },
      home: const _WebStartupGuard(),
    );
  }
}

class _WebStartupGuard extends StatefulWidget {
  const _WebStartupGuard();

  @override
  State<_WebStartupGuard> createState() => _WebStartupGuardState();
}

class _WebStartupGuardState extends State<_WebStartupGuard> {
  Object? _error;
  StackTrace? _stack;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      await Future<void>.delayed(Duration.zero);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => const WebPairingScreen(),
        ),
      );
    } catch (e, st) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _stack = st;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0B141A),
        body: SafeArea(
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 760),
              margin: const EdgeInsets.all(24),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF202C33),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.redAccent.withOpacity(0.25)),
              ),
              child: SingleChildScrollView(
                child: DefaultTextStyle(
                  style: const TextStyle(color: Colors.white),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Failed to start web app',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: Colors.redAccent,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(_error.toString()),
                      const SizedBox(height: 12),
                      if (_stack != null)
                        Text(
                          _stack.toString(),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white70,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return const Scaffold(
      backgroundColor: Color(0xFF0B141A),
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}
