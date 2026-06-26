import 'package:flutter/material.dart';

import '../features/ledger/ledger_home_page.dart';

class FuckssjApp extends StatelessWidget {
  const FuckssjApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'fuckssj',
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
      home: const LedgerHomePage(),
    );
  }
}
