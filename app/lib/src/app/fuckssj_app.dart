import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../data/app_settings_store.dart';
import '../features/ledger/ledger_home_page.dart';

class FuckssjApp extends StatefulWidget {
  const FuckssjApp({super.key});

  @override
  State<FuckssjApp> createState() => _FuckssjAppState();
}

class _FuckssjAppState extends State<FuckssjApp> {
  @override
  void initState() {
    super.initState();
    appSettingsController.load();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appSettingsController,
      builder: (context, _) {
        final settings = appSettingsController.settings;
        return MaterialApp(
          title: 'fuckssj',
          debugShowCheckedModeBanner: false,
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          themeMode: settings.themeMode,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.teal,
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
          ),
          builder: (context, child) {
            final mediaQuery = MediaQuery.of(context);
            return MediaQuery(
              data: mediaQuery.copyWith(
                textScaler: TextScaler.linear(settings.textScaleFactor),
              ),
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: const LedgerHomePage(),
        );
      },
    );
  }
}
