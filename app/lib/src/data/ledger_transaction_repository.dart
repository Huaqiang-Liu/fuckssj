import 'package:sqlite3/sqlite3.dart';

import '../importer/ledger_snapshot.dart';

class LedgerTransactionChoice {
  const LedgerTransactionChoice({
    required this.id,
    required this.label,
    required this.value,
    this.sqliteId,
    this.parent,
  });

  final String id;
  final String label;
  final String value;
  final int? sqliteId;
  final LedgerTransactionChoice? parent;
}

class LedgerTransactionDraft {
  const LedgerTransactionDraft({
    required this.kind,
    required this.amountText,
    required this.tradeTime,
    required this.category,
    required this.account,
    required this.currencyCode,
    required this.note,
  });

  final TransactionKind kind;
  final String amountText;
  final DateTime tradeTime;
  final LedgerTransactionChoice category;
  final LedgerTransactionChoice account;
  final String currencyCode;
  final String note;
}

class LedgerTransactionRepository {
  Future<int> save({
    required String databasePath,
    required TransactionRecord? record,
    required LedgerTransactionDraft draft,
  }) async {
    final db = sqlite3.open(databasePath);
    var transactionStarted = false;
    try {
      db.execute('begin immediate');
      transactionStarted = true;
      _ensureTransactionSchema(db);
      final categoryId = _ensureTransactionCategory(
        db,
        draft.category,
        draft.kind,
      );
      final accountId = _ensureTransactionAccount(db, draft.account);
      final transactionId = int.tryParse(record?.id ?? '');
      final savedId = record == null || transactionId == null
          ? _insertTransaction(
              db,
              kind: draft.kind,
              amountText: draft.amountText,
              tradeTime: draft.tradeTime,
              categoryId: categoryId,
              accountId: accountId,
              note: draft.note,
            )
          : _updateTransaction(
              db,
              transactionId: transactionId,
              kind: draft.kind,
              amountText: draft.amountText,
              tradeTime: draft.tradeTime,
              categoryId: categoryId,
              accountId: accountId,
              note: draft.note,
            );
      _upsertTransactionCurrency(db, savedId, draft.currencyCode);
      db.execute('commit');
      transactionStarted = false;
      return savedId;
    } catch (_) {
      if (transactionStarted) {
        db.execute('rollback');
      }
      rethrow;
    } finally {
      db.dispose();
    }
  }

  Future<void> delete(String databasePath, String recordId) async {
    final transactionId = int.tryParse(recordId);
    if (transactionId == null) {
      throw ArgumentError('流水 ID 无效：$recordId');
    }
    final db = sqlite3.open(databasePath);
    var transactionStarted = false;
    try {
      db.execute('begin immediate');
      transactionStarted = true;
      if (_sqliteTableExists(db, 't_transaction')) {
        db.execute('delete from t_transaction where transactionPOID = ?', [
          transactionId,
        ]);
      }
      if (_sqliteTableExists(db, 'app_transaction_extensions')) {
        db.execute(
          'delete from app_transaction_extensions where transaction_id = ?',
          [recordId],
        );
      }
      db.execute('commit');
      transactionStarted = false;
    } catch (_) {
      if (transactionStarted) {
        db.execute('rollback');
      }
      rethrow;
    } finally {
      db.dispose();
    }
  }
}

void _ensureTransactionSchema(Database db) {
  db.execute('''
    create table if not exists t_category (
      categoryPOID integer primary key,
      name text not null,
      parentCategoryPOID integer,
      depth integer not null default 1,
      path text,
      type integer not null default 0,
      ordered integer not null default 0,
      hidden integer not null default 0
    )
  ''');
  db.execute('''
    create table if not exists t_account (
      accountPOID integer primary key,
      name text not null,
      accountGroupPOID integer,
      ordered integer not null default 0,
      hidden integer not null default 0
    )
  ''');
  db.execute('''
    create table if not exists t_transaction (
      transactionPOID integer primary key,
      type integer not null,
      tradeTime integer not null,
      sellerCategoryPOID integer,
      sellerMoney text,
      buyerCategoryPOID integer,
      buyerMoney text,
      sellerAccountPOID integer,
      buyerAccountPOID integer,
      memo text
    )
  ''');
  _addColumnIfMissing(db, 't_transaction', 'sellerAccountPOID integer');
  _addColumnIfMissing(db, 't_transaction', 'buyerAccountPOID integer');
  _addColumnIfMissing(db, 't_transaction', 'memo text');
  db.execute('''
    create table if not exists app_transaction_extensions (
      transaction_id text primary key,
      currency_code text not null default 'CNY',
      encrypted_note integer not null default 0
    )
  ''');
}

void _addColumnIfMissing(Database db, String tableName, String definition) {
  final column = definition.split(' ').first;
  final exists = db
      .select('pragma table_info(${_quoteSqlIdentifier(tableName)})')
      .any((row) => row['name'] == column);
  if (!exists) {
    db.execute(
      'alter table ${_quoteSqlIdentifier(tableName)} add column $definition',
    );
  }
}

int _ensureTransactionCategory(
  Database db,
  LedgerTransactionChoice choice,
  TransactionKind kind,
) {
  final id = choice.sqliteId ?? _stableAppSqliteId(choice.id, 1000000000);
  final parent = choice.parent;
  final parentId = parent == null
      ? -1
      : _ensureTransactionCategory(db, parent, kind);
  final name = choice.value.split(' / ').last;
  final type = kind == TransactionKind.income ? 1 : 0;
  final depth = parent == null ? 1 : 2;
  final path = parent == null ? '/-1/$id/' : '/-1/$parentId/$id/';
  _upsertTableRow(
    db,
    tableName: 't_category',
    primaryKeyColumn: 'categoryPOID',
    primaryKeyValue: id,
    values: {
      'name': name,
      'parentCategoryPOID': parentId,
      'depth': depth,
      'path': path,
      'type': type,
      'ordered': 0,
      'hidden': 0,
    },
  );
  return id;
}

int _ensureTransactionAccount(Database db, LedgerTransactionChoice choice) {
  final id = choice.sqliteId ?? _stableAppSqliteId(choice.id, 2000000000);
  _upsertTableRow(
    db,
    tableName: 't_account',
    primaryKeyColumn: 'accountPOID',
    primaryKeyValue: id,
    values: {
      'name': choice.value,
      'accountGroupPOID': null,
      'ordered': 0,
      'hidden': 0,
    },
  );
  return id;
}

int _insertTransaction(
  Database db, {
  required TransactionKind kind,
  required String amountText,
  required DateTime tradeTime,
  required int categoryId,
  required int accountId,
  required String note,
}) {
  final isIncome = kind == TransactionKind.income;
  final transactionId = _nextTransactionId(db);
  final knownValues = <String, Object?>{
    'transactionPOID': transactionId,
    'type': isIncome ? 1 : 0,
    'tradeTime': tradeTime.millisecondsSinceEpoch,
    'sellerCategoryPOID': isIncome ? null : categoryId,
    'sellerMoney': isIncome ? null : amountText,
    'buyerCategoryPOID': isIncome ? categoryId : null,
    'buyerMoney': isIncome ? amountText : null,
    'sellerAccountPOID': isIncome ? null : accountId,
    'buyerAccountPOID': isIncome ? accountId : null,
    'memo': note,
  };
  final columns = <String>[];
  final values = <Object?>[];
  for (final column in _sqliteColumns(db, 't_transaction')) {
    final name = _stringValue(column['name'], '');
    if (name.isEmpty) {
      continue;
    }
    if (knownValues.containsKey(name)) {
      columns.add(name);
      values.add(knownValues[name]);
      continue;
    }
    if (column['notnull'] == 1 && column['dflt_value'] == null) {
      columns.add(name);
      values.add(_sqliteDefaultValueForColumn(name, column['type']));
    }
  }
  final placeholders = List.filled(columns.length, '?').join(', ');
  db.execute(
    '''
    insert into t_transaction(
      ${columns.map(_quoteSqlIdentifier).join(', ')}
    ) values ($placeholders)
    ''',
    values,
  );
  return transactionId;
}

int _updateTransaction(
  Database db, {
  required int transactionId,
  required TransactionKind kind,
  required String amountText,
  required DateTime tradeTime,
  required int categoryId,
  required int accountId,
  required String note,
}) {
  final isIncome = kind == TransactionKind.income;
  db.execute(
    '''
    update t_transaction set
      type = ?,
      tradeTime = ?,
      sellerCategoryPOID = ?,
      sellerMoney = ?,
      buyerCategoryPOID = ?,
      buyerMoney = ?,
      sellerAccountPOID = ?,
      buyerAccountPOID = ?,
      memo = ?
    where transactionPOID = ?
    ''',
    [
      isIncome ? 1 : 0,
      tradeTime.millisecondsSinceEpoch,
      isIncome ? null : categoryId,
      isIncome ? null : amountText,
      isIncome ? categoryId : null,
      isIncome ? amountText : null,
      isIncome ? null : accountId,
      isIncome ? accountId : null,
      note,
      transactionId,
    ],
  );
  return transactionId;
}

void _upsertTransactionCurrency(
  Database db,
  int transactionId,
  String currencyCode,
) {
  db.execute(
    '''
    insert into app_transaction_extensions(transaction_id, currency_code, encrypted_note)
    values (?, ?, 0)
    on conflict(transaction_id) do update set
      currency_code = excluded.currency_code
    ''',
    [transactionId.toString(), currencyCode],
  );
}

int _nextTransactionId(Database db) {
  final now = DateTime.now().microsecondsSinceEpoch;
  final rows = db.select(
    'select max(cast(transactionPOID as integer)) as id from t_transaction',
  );
  final maxId = rows.isEmpty ? null : rows.first['id'] as int?;
  final candidate = maxId == null || maxId < now ? now : maxId + 1;
  return candidate <= 0 ? now : candidate;
}

void _upsertTableRow(
  Database db, {
  required String tableName,
  required String primaryKeyColumn,
  required Object primaryKeyValue,
  required Map<String, Object?> values,
}) {
  final quotedTable = _quoteSqlIdentifier(tableName);
  final quotedPrimaryKey = _quoteSqlIdentifier(primaryKeyColumn);
  final exists = db
      .select(
        'select 1 from $quotedTable where $quotedPrimaryKey = ? limit 1',
        [primaryKeyValue],
      )
      .isNotEmpty;
  if (exists) {
    final columns = {
      for (final column in _sqliteColumns(db, tableName))
        _stringValue(column['name'], ''),
    };
    final updateValues = <String, Object?>{
      for (final entry in values.entries)
        if (columns.contains(entry.key)) entry.key: entry.value,
    };
    if (updateValues.isEmpty) {
      return;
    }
    db.execute(
      '''
      update $quotedTable set
        ${updateValues.keys.map((key) => '${_quoteSqlIdentifier(key)} = ?').join(', ')}
      where $quotedPrimaryKey = ?
      ''',
      [...updateValues.values, primaryKeyValue],
    );
    return;
  }

  _insertTableRow(
    db,
    tableName: tableName,
    primaryKeyColumn: primaryKeyColumn,
    primaryKeyValue: primaryKeyValue,
    values: values,
  );
}

void _insertTableRow(
  Database db, {
  required String tableName,
  required String primaryKeyColumn,
  required Object primaryKeyValue,
  required Map<String, Object?> values,
}) {
  final insertColumns = <String>[];
  final insertValues = <Object?>[];
  for (final column in _sqliteColumns(db, tableName)) {
    final name = _stringValue(column['name'], '');
    if (name.isEmpty) {
      continue;
    }
    if (name == primaryKeyColumn) {
      insertColumns.add(name);
      insertValues.add(primaryKeyValue);
      continue;
    }
    if (values.containsKey(name)) {
      insertColumns.add(name);
      insertValues.add(values[name]);
      continue;
    }
    if (column['notnull'] == 1 && column['dflt_value'] == null) {
      insertColumns.add(name);
      insertValues.add(_sqliteDefaultValueForColumn(name, column['type']));
    }
  }
  final placeholders = List.filled(insertColumns.length, '?').join(', ');
  db.execute(
    '''
    insert into ${_quoteSqlIdentifier(tableName)}(
      ${insertColumns.map(_quoteSqlIdentifier).join(', ')}
    ) values ($placeholders)
    ''',
    insertValues,
  );
}

bool _sqliteTableExists(Database db, String tableName) {
  final rows = db.select(
    "select 1 from sqlite_master where type = 'table' and name = ? limit 1",
    [tableName],
  );
  return rows.isNotEmpty;
}

int _stableAppSqliteId(String id, int base) {
  var hash = 0;
  for (final unit in id.codeUnits) {
    hash = (hash * 31 + unit) & 0x3fffffff;
  }
  return -(base + hash);
}

String _quoteSqlIdentifier(String identifier) {
  return '"${identifier.replaceAll('"', '""')}"';
}

List<Map<String, Object?>> _sqliteColumns(Database db, String tableName) {
  return [
    for (final row in db.select(
      'pragma table_info(${_quoteSqlIdentifier(tableName)})',
    ))
      {
        'cid': row['cid'],
        'name': row['name'],
        'type': row['type'],
        'notnull': row['notnull'],
        'dflt_value': row['dflt_value'],
        'pk': row['pk'],
      },
  ];
}

Object _sqliteDefaultValueForColumn(String name, Object? type) {
  final lowerName = name.toLowerCase();
  if (lowerName.contains('time') || lowerName.endsWith('at')) {
    return DateTime.now().millisecondsSinceEpoch;
  }
  final lowerType = type?.toString().toLowerCase() ?? '';
  if (lowerType.contains('int') ||
      lowerType.contains('real') ||
      lowerType.contains('numeric') ||
      lowerType.contains('double') ||
      lowerType.contains('float')) {
    return 0;
  }
  return '';
}

String _stringValue(Object? value, String fallback) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) {
    return fallback;
  }
  return text;
}
