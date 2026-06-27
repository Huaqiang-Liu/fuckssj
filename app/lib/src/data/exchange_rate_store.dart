import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ExchangeRateStore {
  static const int defaultRefreshAfterHours = 12;
  static const String defaultSource = 'frankfurter.app';

  Future<File> ensureCache() async {
    final file = await cacheFile();
    if (file.existsSync()) {
      return file;
    }

    await file.writeAsString(jsonEncode(defaultCache()), flush: true);
    return file;
  }

  Future<Map<String, Object?>> loadOrRefresh() async {
    final file = await ensureCache();
    final cache = await _readCache(file);
    if (!_shouldRefresh(cache)) {
      return cache;
    }

    try {
      final refreshed = await _fetchRates();
      await file.writeAsString(jsonEncode(refreshed), flush: true);
      return refreshed;
    } catch (_) {
      return cache;
    }
  }

  Future<File> cacheFile() async {
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(root.path, 'ledgers'));
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }
    return File(p.join(directory.path, 'exchange_rates.json'));
  }

  Map<String, Object?> defaultCache() => {
    'schemaVersion': 1,
    'source': defaultSource,
    'base': 'CNY',
    'updatedAt': null,
    'refreshAfterHours': defaultRefreshAfterHours,
    'rates': {'CNY': 1.0},
  };

  Future<Map<String, Object?>> _readCache(File file) async {
    try {
      final json = jsonDecode(await file.readAsString());
      if (json is Map<String, Object?>) {
        final rates = json['rates'] is Map
            ? Map<String, Object?>.from(json['rates'] as Map)
            : <String, Object?>{};
        return {
          ...defaultCache(),
          ...json,
          'rates': {'CNY': 1.0, ...rates},
        };
      }
    } on FormatException {
      // Fall through to a fresh default cache.
    }
    return defaultCache();
  }

  bool _shouldRefresh(Map<String, Object?> cache) {
    final updatedAtText = cache['updatedAt']?.toString();
    if (updatedAtText == null || updatedAtText.isEmpty) {
      return true;
    }
    final updatedAt = DateTime.tryParse(updatedAtText);
    if (updatedAt == null) {
      return true;
    }
    final refreshAfterHours =
        int.tryParse(cache['refreshAfterHours']?.toString() ?? '') ??
        defaultRefreshAfterHours;
    return DateTime.now().toUtc().difference(updatedAt.toUtc()) >=
        Duration(hours: refreshAfterHours);
  }

  Future<Map<String, Object?>> _fetchRates() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final uri = Uri.https('api.frankfurter.app', '/latest', {'from': 'CNY'});
      final request = await client.getUrl(uri);
      final response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      if (response.statusCode != HttpStatus.ok) {
        throw const HttpException('Exchange rate request failed');
      }
      final text = await response.transform(utf8.decoder).join();
      final json = jsonDecode(text);
      if (json is! Map<String, Object?> || json['rates'] is! Map) {
        throw const FormatException('Exchange rate response is invalid');
      }
      final rates = <String, Object?>{'CNY': 1.0};
      final sourceRates = json['rates'] as Map;
      for (final entry in sourceRates.entries) {
        final code = entry.key?.toString().trim().toUpperCase();
        final rate = entry.value;
        if (code == null || code.isEmpty) {
          continue;
        }
        if (rate is num) {
          rates[code] = rate.toDouble();
        } else {
          final parsed = double.tryParse(rate.toString());
          if (parsed != null) {
            rates[code] = parsed;
          }
        }
      }
      return {
        'schemaVersion': 1,
        'source': defaultSource,
        'base': 'CNY',
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
        'refreshAfterHours': defaultRefreshAfterHours,
        'rates': rates,
      };
    } finally {
      client.close(force: true);
    }
  }
}
