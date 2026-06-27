import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

class LedgerConfigurationStore {
  static const String defaultTemplateAsset =
      'assets/default_ledger_template.json';
  static const int currentSchemaVersion = 2;
  static const List<Map<String, Object?>> defaultCurrencies = [
    {'code': 'CNY', 'name': '人民币', 'isBase': true, 'enabled': true},
    {'code': 'USD', 'name': '美元', 'isBase': false, 'enabled': true},
    {'code': 'JPY', 'name': '日元', 'isBase': false, 'enabled': true},
    {'code': 'HKD', 'name': '港币', 'isBase': false, 'enabled': true},
    {'code': 'EUR', 'name': '欧元', 'isBase': false, 'enabled': true},
    {'code': 'GBP', 'name': '英镑', 'isBase': false, 'enabled': true},
    {'code': 'AUD', 'name': '澳元', 'isBase': false, 'enabled': true},
  ];
  static const Set<String> _defaultCurrencyCodes = {
    'CNY',
    'USD',
    'JPY',
    'HKD',
    'EUR',
    'GBP',
    'AUD',
  };

  Future<File> ensureConfiguration({
    required String ledgerId,
    required String databasePath,
    required bool preferDatabase,
  }) async {
    final file = await configurationFile(ledgerId);
    if (file.existsSync()) {
      await _migrateExistingConfiguration(
        file,
        databasePath: databasePath,
        preferDatabase: preferDatabase,
      );
      return file;
    }

    final config = preferDatabase
        ? await _configurationFromDatabaseOrTemplate(databasePath)
        : await _loadDefaultTemplate();
    await file.writeAsString(jsonEncode(config), flush: true);
    return file;
  }

  Future<File> configurationFile(String ledgerId) async {
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(root.path, 'ledgers', 'configs'));
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }
    return File(p.join(directory.path, '$ledgerId.json'));
  }

  Future<Map<String, Object?>> _configurationFromDatabaseOrTemplate(
    String databasePath,
  ) async {
    final fallback = await _loadDefaultTemplate();
    final source = File(databasePath);
    if (!source.existsSync()) {
      return fallback;
    }

    final db = sqlite3.open(databasePath);
    try {
      final categories = _tableExists(db, 't_category')
          ? _categoriesFromDatabase(db)
          : const <Map<String, Object?>>[];
      final accounts =
          _tableExists(db, 't_account') || _tableExists(db, 't_account_group')
          ? _accountsFromDatabase(db)
          : const <Map<String, Object?>>[];
      final currencies = _tableExists(db, 't_currency')
          ? _currenciesFromDatabase(db)
          : const <Map<String, Object?>>[];
      return {
        'schemaVersion': currentSchemaVersion,
        'source': 'sqlite:$databasePath',
        'categories': categories.isEmpty ? fallback['categories'] : categories,
        'accounts': accounts.isEmpty ? fallback['accounts'] : accounts,
        'currencies': _mergeWithDefaultCurrencies(currencies),
        'exchangeRates': fallback['exchangeRates'],
      };
    } finally {
      db.dispose();
    }
  }

  Future<Map<String, Object?>> _loadDefaultTemplate() async {
    final text = await rootBundle.loadString(defaultTemplateAsset);
    final json = jsonDecode(text);
    if (json is Map<String, Object?>) {
      return _normalizeConfiguration(json);
    }
    throw const FormatException(
      'Default ledger template must be a JSON object',
    );
  }

  Future<void> _migrateExistingConfiguration(
    File file, {
    required String databasePath,
    required bool preferDatabase,
  }) async {
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, Object?>) {
        return;
      }

      final schemaVersion = decoded['schemaVersion'];
      if (schemaVersion is int && schemaVersion >= currentSchemaVersion) {
        final normalized = _normalizeConfiguration(decoded);
        if (jsonEncode(normalized) != jsonEncode(decoded)) {
          await file.writeAsString(jsonEncode(normalized), flush: true);
        }
        return;
      }

      final migrated = preferDatabase
          ? await _configurationFromDatabaseOrTemplate(databasePath)
          : await _loadDefaultTemplate();
      await file.writeAsString(jsonEncode(migrated), flush: true);
    } on FormatException {
      return;
    }
  }

  Map<String, Object?> _normalizeConfiguration(Map<String, Object?> config) {
    return {
      ...config,
      'schemaVersion': currentSchemaVersion,
      'currencies': _mergeWithDefaultCurrencies(
        _listOfMaps(config['currencies']),
      ),
      'exchangeRates':
          config['exchangeRates'] ??
          {
            'source': 'manual',
            'base': 'CNY',
            'updatedAt': null,
            'refreshAfterHours': 12,
            'rates': <String, Object?>{},
          },
    };
  }

  List<Map<String, Object?>> _categoriesFromDatabase(Database db) {
    final rows = db.select('''
      select categoryPOID, name, parentCategoryPOID, depth, type, ordered, hidden
      from t_category
      where categoryPOID != -1
      order by type, depth, ordered, categoryPOID
    ''');
    final byParent = <int, List<Row>>{};
    for (final row in rows) {
      final parentId = (row['parentCategoryPOID'] as int?) ?? 0;
      byParent.putIfAbsent(parentId, () => []).add(row);
    }

    Map<String, Object?> node(Row row) {
      final id = row['categoryPOID'] as int;
      return {
        'id': 'ssj_$id',
        'name': _nameOrFallback(row['name'], '未命名分类'),
        'children': [
          for (final child in byParent[id] ?? const <Row>[])
            if (child['hidden'] != 1) node(child),
        ],
      };
    }

    return [
      for (final entry in const [
        (type: 0, direction: 'expense'),
        (type: 1, direction: 'income'),
      ])
        {
          'direction': entry.direction,
          'items': [
            for (final row in rows)
              if (row['type'] == entry.type &&
                  row['depth'] == 1 &&
                  row['hidden'] != 1)
                node(row),
          ],
        },
    ];
  }

  List<Map<String, Object?>> _accountsFromDatabase(Database db) {
    final groups = _tableExists(db, 't_account_group')
        ? db.select('''
            select accountGroupPOID, name, parentAccountGroupPOID, depth, ordered
            from t_account_group
            order by depth, ordered, accountGroupPOID
          ''')
        : const <Row>[];
    final accounts = _tableExists(db, 't_account')
        ? db.select('''
            select accountPOID, name, accountGroupPOID, ordered, hidden
            from t_account
            order by ordered, accountPOID
          ''')
        : const <Row>[];
    final accountsByGroup = <int, List<Row>>{};
    for (final account in accounts) {
      final groupId = account['accountGroupPOID'] as int?;
      if (groupId == null || account['hidden'] == 1) {
        continue;
      }
      accountsByGroup.putIfAbsent(groupId, () => []).add(account);
    }

    if (groups.isEmpty) {
      return [
        {
          'id': 'accounts',
          'name': '账户',
          'children': [
            for (final account in accounts)
              if (account['hidden'] != 1)
                {
                  'id': 'ssj_account_${account['accountPOID']}',
                  'name': _nameOrFallback(account['name'], '未命名账户'),
                },
          ],
        },
      ];
    }

    final groupsByParent = <int, List<Row>>{};
    final groupIds = <int>{};
    for (final group in groups) {
      final groupId = group['accountGroupPOID'] as int;
      groupIds.add(groupId);
      final parentId = group['parentAccountGroupPOID'] as int?;
      if (parentId != null) {
        groupsByParent.putIfAbsent(parentId, () => []).add(group);
      }
    }

    List<Map<String, Object?>> accountChildrenForGroup(int groupId) {
      final children = <Map<String, Object?>>[
        for (final account in accountsByGroup[groupId] ?? const <Row>[])
          {
            'id': 'ssj_account_${account['accountPOID']}',
            'name': _nameOrFallback(account['name'], '未命名账户'),
          },
      ];

      for (final childGroup in groupsByParent[groupId] ?? const <Row>[]) {
        final childGroupId = childGroup['accountGroupPOID'] as int;
        children.add({
          'id': 'ssj_group_$childGroupId',
          'name': _nameOrFallback(childGroup['name'], '未命名账户组'),
          'children': accountChildrenForGroup(childGroupId),
        });
      }
      return children;
    }

    var rootGroups = [
      for (final group in groups)
        if (group['depth'] == 1) group,
    ];
    if (rootGroups.isEmpty) {
      rootGroups = [
        for (final group in groups)
          if ((group['parentAccountGroupPOID'] == null) ||
              !groupIds.contains(group['parentAccountGroupPOID']))
            group,
      ];
    }

    final ungroupedAccounts = [
      for (final entry in accountsByGroup.entries)
        if (!groupIds.contains(entry.key))
          for (final account in entry.value)
            {
              'id': 'ssj_account_${account['accountPOID']}',
              'name': _nameOrFallback(account['name'], '未命名账户'),
            },
    ];

    return [
      for (final group in rootGroups)
        {
          'id': 'ssj_group_${group['accountGroupPOID']}',
          'name': _nameOrFallback(group['name'], '未命名账户组'),
          'children': accountChildrenForGroup(group['accountGroupPOID'] as int),
        },
      if (ungroupedAccounts.isNotEmpty)
        {
          'id': 'ungrouped_accounts',
          'name': '未分组账户',
          'children': ungroupedAccounts,
        },
    ];
  }

  List<Map<String, Object?>> _currenciesFromDatabase(Database db) {
    final rows = db.select('''
      select code, name
      from t_currency
      order by case when code = 'CNY' then 0 else 1 end, code
    ''');
    return _mergeWithDefaultCurrencies([
      for (final row in rows)
        {
          'code': _nameOrFallback(row['code'], 'CNY'),
          'name': _nameOrFallback(row['name'], '人民币'),
          'isBase': row['code'] == 'CNY',
        },
    ]);
  }

  List<Map<String, Object?>> _mergeWithDefaultCurrencies(
    List<Map<String, Object?>> currencies,
  ) {
    final byCode = <String, Map<String, Object?>>{};
    for (final currency in defaultCurrencies) {
      final code = _nameOrFallback(currency['code'], '').toUpperCase();
      byCode[code] = Map<String, Object?>.from(currency);
    }
    for (final currency in currencies) {
      final code = _nameOrFallback(currency['code'], '').toUpperCase();
      if (code.isEmpty) {
        continue;
      }
      final defaultEnabled = _defaultCurrencyCodes.contains(code);
      byCode[code] = {
        ...?byCode[code],
        ...currency,
        'code': code,
        'enabled': currency['enabled'] ?? defaultEnabled,
        'isBase': code == 'CNY',
      };
    }
    _disableLegacyAllEnabledCurrencies(byCode);
    return [
      for (final code in const [
        'CNY',
        'USD',
        'JPY',
        'HKD',
        'EUR',
        'GBP',
        'AUD',
      ])
        if (byCode.containsKey(code)) byCode.remove(code)!,
      ...byCode.values,
    ];
  }

  void _disableLegacyAllEnabledCurrencies(
    Map<String, Map<String, Object?>> byCode,
  ) {
    final nonDefaultEntries = byCode.entries.where(
      (entry) => !_defaultCurrencyCodes.contains(entry.key),
    );
    if (nonDefaultEntries.isEmpty) {
      return;
    }
    final legacyAllEnabled = nonDefaultEntries.every(
      (entry) => entry.value['enabled'] != false,
    );
    if (!legacyAllEnabled) {
      return;
    }
    for (final entry in nonDefaultEntries) {
      entry.value['enabled'] = false;
    }
  }

  List<Map<String, Object?>> _listOfMaps(Object? value) {
    if (value is! List) {
      return const [];
    }
    return [
      for (final item in value)
        if (item is Map<String, Object?>) item,
    ];
  }

  bool _tableExists(Database db, String tableName) {
    final rows = db.select(
      "select 1 from sqlite_master where type = 'table' and name = ? limit 1",
      [tableName],
    );
    return rows.isNotEmpty;
  }

  String _nameOrFallback(Object? value, String fallback) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) {
      return fallback;
    }
    return text;
  }
}
