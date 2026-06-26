import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';

import 'src/app/fuckssj_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await applyWorkaroundToOpenSqlite3OnOldAndroidVersions();
  runApp(const ProviderScope(child: FuckssjApp()));
}
