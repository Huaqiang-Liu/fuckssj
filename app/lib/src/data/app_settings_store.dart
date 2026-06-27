import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

final appSettingsController = AppSettingsController(AppSettingsStore());

class AppSettingsController extends ChangeNotifier {
  AppSettingsController(this._store);

  final AppSettingsStore _store;
  AppSettings _settings = const AppSettings();
  bool _loaded = false;

  AppSettings get settings => _settings;
  bool get loaded => _loaded;

  Future<void> load() async {
    _settings = await _store.load();
    _loaded = true;
    notifyListeners();
  }

  Future<void> update(AppSettings settings) async {
    _settings = settings;
    notifyListeners();
    await _store.save(settings);
  }
}

class AppSettingsStore {
  Future<AppSettings> load() async {
    final file = await _settingsFile();
    if (!file.existsSync()) {
      return const AppSettings();
    }
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map<String, Object?>) {
        return AppSettings.fromJson(decoded);
      }
    } on FormatException {
      return const AppSettings();
    }
    return const AppSettings();
  }

  Future<void> save(AppSettings settings) async {
    final file = await _settingsFile();
    await file.writeAsString(jsonEncode(settings.toJson()), flush: true);
  }

  Future<File> _settingsFile() async {
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(root.path, 'settings'));
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }
    return File(p.join(directory.path, 'app_settings.json'));
  }
}

class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.fontSizeBias = 0,
  });

  final ThemeMode themeMode;
  final int fontSizeBias;

  AppSettings copyWith({ThemeMode? themeMode, int? fontSizeBias}) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      fontSizeBias: fontSizeBias ?? this.fontSizeBias,
    );
  }

  double get textScaleFactor => switch (fontSizeBias) {
    0 => 1,
    1 => 1.05,
    2 => 1.10,
    _ => 1.15,
  };

  Map<String, Object?> toJson() => {
    'themeMode': themeMode.name,
    'fontSizeBias': fontSizeBias.clamp(0, 3).toInt(),
  };

  factory AppSettings.fromJson(Map<String, Object?> json) {
    final themeName = json['themeMode'] as String?;
    final bias = json['fontSizeBias'];
    return AppSettings(
      themeMode: ThemeMode.values.firstWhere(
        (mode) => mode.name == themeName,
        orElse: () => ThemeMode.system,
      ),
      fontSizeBias: bias is int ? bias.clamp(0, 3).toInt() : 0,
    );
  }
}
