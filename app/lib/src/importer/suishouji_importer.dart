import 'package:sqlite3/sqlite3.dart';

import 'ledger_snapshot.dart';

class SuiShouJiImporter {
  static const defaultPageSize = 30;

  Future<LedgerSnapshot> load(
    String databasePath, {
    int limit = defaultPageSize,
  }) async {
    return query(databasePath, TransactionQuery(limit: limit));
  }

  Future<LedgerSnapshot> query(
    String databasePath,
    TransactionQuery query,
  ) async {
    final db = sqlite3.open(databasePath);
    try {
      final context = _readContext(db);
      if (!context.hasTables) {
        return LedgerSnapshot(
          databasePath: databasePath,
          transactions: const [],
          hasSuiShouJiTables: false,
        );
      }

      if (!query.includeIncome && !query.includeExpense) {
        return LedgerSnapshot(
          databasePath: databasePath,
          transactions: const [],
          hasSuiShouJiTables: true,
        );
      }

      final statement = _buildTransactionSql(query: query, context: context);
      final rows = db.select(statement.sql, statement.args);
      return LedgerSnapshot(
        databasePath: databasePath,
        hasSuiShouJiTables: true,
        transactions: [
          for (final row in rows)
            TransactionRecord(
              id: row['transaction_id'].toString(),
              kind: row['type'] == 1
                  ? TransactionKind.income
                  : TransactionKind.expense,
              amount: row['amount']?.toString() ?? '0',
              tradeTime: DateTime.fromMillisecondsSinceEpoch(
                (row['trade_time_ms'] as int?) ?? 0,
              ),
              firstCategory:
                  row['first_category']?.toString().trim().isNotEmpty == true
                  ? row['first_category'].toString()
                  : '未分类',
              secondCategory:
                  row['second_category']?.toString().trim().isNotEmpty == true
                  ? row['second_category'].toString()
                  : null,
              categoryId: row['category_id'] as int?,
              parentCategoryId: row['parent_category_id'] as int?,
              accountName:
                  row['account_name']?.toString().trim().isNotEmpty == true
                  ? row['account_name'].toString()
                  : null,
              accountId: row['account_id'] as int?,
              currencyCode:
                  row['currency_code']?.toString().trim().isNotEmpty == true
                  ? row['currency_code'].toString()
                  : 'CNY',
              note: row['note']?.toString(),
            ),
        ],
      );
    } finally {
      db.dispose();
    }
  }

  Future<int> count(String databasePath, TransactionQuery query) async {
    final db = sqlite3.open(databasePath);
    try {
      final context = _readContext(db);
      if (!context.hasTables ||
          (!query.includeIncome && !query.includeExpense)) {
        return 0;
      }
      final statement = _buildCountSql(query: query, context: context);
      final rows = db.select(statement.sql, statement.args);
      if (rows.isEmpty) {
        return 0;
      }
      return (rows.first['count'] as int?) ?? 0;
    } finally {
      db.dispose();
    }
  }

  Future<TransactionSummary> summarize(
    String databasePath,
    TransactionQuery query,
  ) async {
    final db = sqlite3.open(databasePath);
    try {
      final context = _readContext(db);
      if (!context.hasTables ||
          (!query.includeIncome && !query.includeExpense)) {
        return const TransactionSummary.empty();
      }
      return _summarizeOpen(db, query, context, includeCategory: true);
    } finally {
      db.dispose();
    }
  }

  Future<DashboardSummary> dashboardSummary(String databasePath) async {
    final db = sqlite3.open(databasePath);
    try {
      final context = _readContext(db);
      if (!context.hasTables) {
        return const DashboardSummary.empty();
      }

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final tomorrow = today.add(const Duration(days: 1));
      final weekStart = today.subtract(Duration(days: today.weekday - 1));
      final monthStart = DateTime(today.year, today.month);
      final yearStart = DateTime(today.year);

      return DashboardSummary(
        today: _summarizeOpen(
          db,
          TransactionQuery(startDate: today, endDate: tomorrow),
          context,
          includeCategory: false,
        ),
        week: _summarizeOpen(
          db,
          TransactionQuery(startDate: weekStart, endDate: tomorrow),
          context,
          includeCategory: false,
        ),
        month: _summarizeOpen(
          db,
          TransactionQuery(startDate: monthStart, endDate: tomorrow),
          context,
          includeCategory: false,
        ),
        year: _summarizeOpen(
          db,
          TransactionQuery(startDate: yearStart, endDate: tomorrow),
          context,
          includeCategory: false,
        ),
      );
    } finally {
      db.dispose();
    }
  }

  _ImporterContext _readContext(Database db) {
    final hasTables =
        _tableExists(db, 't_transaction') && _tableExists(db, 't_category');
    return _ImporterContext(
      hasTables: hasTables,
      noteExpression: hasTables ? _noteExpression(db) : null,
      hasAccountTable: hasTables && _tableExists(db, 't_account'),
      hasTransactionExtensionTable:
          hasTables && _tableExists(db, 'app_transaction_extensions'),
    );
  }

  bool _tableExists(Database db, String tableName) {
    final rows = db.select(
      "select 1 from sqlite_master where type = 'table' and name = ? limit 1",
      [tableName],
    );
    return rows.isNotEmpty;
  }

  String? _noteExpression(Database db) {
    const candidates = [
      'memo',
      'remark',
      'note',
      'comment',
      'description',
      'buyerMemo',
      'sellerMemo',
    ];
    final columns = {
      for (final row in db.select('pragma table_info(t_transaction)'))
        row['name']?.toString(),
    };
    final expressions = [
      for (final candidate in candidates)
        if (columns.contains(candidate)) 't.${_quoteIdentifier(candidate)}',
    ];
    if (expressions.isNotEmpty) {
      return 'coalesce(${[...expressions, "''"].join(', ')})';
    }
    return null;
  }
}

TransactionSummary _summarizeOpen(
  Database db,
  TransactionQuery query,
  _ImporterContext context, {
  required bool includeCategory,
}) {
  final statement = _buildSummarySql(
    query: query,
    context: context,
    includeCategory: includeCategory,
  );
  final rows = db.select(statement.sql, statement.args);
  var count = 0;
  final summaryRows = <TransactionSummaryRow>[];
  for (final row in rows) {
    final rowCount = (row['record_count'] as int?) ?? 0;
    count += rowCount;
    summaryRows.add(
      TransactionSummaryRow(
        kind: row['type'] == 1
            ? TransactionKind.income
            : TransactionKind.expense,
        currencyCode: row['currency_code']?.toString().trim().isNotEmpty == true
            ? row['currency_code'].toString()
            : 'CNY',
        amount: _doubleValue(row['amount']),
        firstCategory: includeCategory
            ? (row['first_category']?.toString().trim().isNotEmpty == true
                  ? row['first_category'].toString()
                  : '未分类')
            : null,
      ),
    );
  }
  return TransactionSummary(count: count, rows: summaryRows);
}

_QueryStatement _buildTransactionSql({
  required TransactionQuery query,
  required _ImporterContext context,
}) {
  final filtered = _buildFilteredTransactionSql(query: query, context: context);
  return _QueryStatement(
    sql:
        '''
select
    transaction_id,
    type,
    trade_time_ms,
    amount_text as amount,
    first_category,
    second_category,
    category_id,
    parent_category_id,
    account_name,
    account_id,
    currency_code,
    note
from (${filtered.sql}) source
where ${filtered.whereSql}
order by trade_time_ms desc, transaction_id desc
limit ?
offset ?
''',
    args: [...filtered.args, query.limit, query.offset],
  );
}

_QueryStatement _buildCountSql({
  required TransactionQuery query,
  required _ImporterContext context,
}) {
  final filtered = _buildFilteredTransactionSql(query: query, context: context);
  return _QueryStatement(
    sql:
        '''
select count(*) as count
from (${filtered.sql}) source
where ${filtered.whereSql}
''',
    args: filtered.args,
  );
}

_QueryStatement _buildSummarySql({
  required TransactionQuery query,
  required _ImporterContext context,
  required bool includeCategory,
}) {
  final filtered = _buildFilteredTransactionSql(query: query, context: context);
  final categorySelect = includeCategory ? 'first_category,' : '';
  final categoryGroup = includeCategory ? ', first_category' : '';
  return _QueryStatement(
    sql:
        '''
select
    type,
    currency_code,
    $categorySelect
    sum(amount_real) as amount,
    count(*) as record_count
from (${filtered.sql}) source
where ${filtered.whereSql}
group by type, currency_code$categoryGroup
''',
    args: filtered.args,
  );
}

_FilteredTransactionSql _buildFilteredTransactionSql({
  required TransactionQuery query,
  required _ImporterContext context,
}) {
  final whereParts = <String>['type in (0, 1)'];
  final args = <Object?>[];

  if (query.includeIncome != query.includeExpense) {
    whereParts.add('type = ?');
    args.add(query.includeIncome ? 1 : 0);
  }
  final startDate = query.startDate;
  if (startDate != null) {
    whereParts.add('trade_time_ms >= ?');
    args.add(startDate.millisecondsSinceEpoch);
  }
  final endDate = query.endDate;
  if (endDate != null) {
    whereParts.add('trade_time_ms < ?');
    args.add(endDate.millisecondsSinceEpoch);
  }
  final minAmount = query.minAmount;
  if (minAmount != null) {
    whereParts.add('amount_real >= ?');
    args.add(minAmount);
  }
  final maxAmount = query.maxAmount;
  if (maxAmount != null) {
    whereParts.add('amount_real <= ?');
    args.add(maxAmount);
  }
  final noteKeyword = query.noteKeyword?.trim();
  if (noteKeyword != null && noteKeyword.isNotEmpty) {
    if (context.noteExpression == null) {
      whereParts.add('0 = 1');
    } else {
      whereParts.add('note like ?');
      args.add('%$noteKeyword%');
    }
  }
  _addCategoryFilter(whereParts, args, query.categoryPaths);
  _addInFilter(whereParts, args, 'account_name', query.accountNames);
  _addInFilter(whereParts, args, 'currency_code', query.currencyCodes);

  return _FilteredTransactionSql(
    sql: _transactionSourceSql(context),
    whereSql: whereParts.join(' and '),
    args: args,
  );
}

String _transactionSourceSql(_ImporterContext context) {
  const amountExpression = '''
case
    when t.type = 1 then t.buyerMoney
    else t.sellerMoney
end
''';
  const firstCategoryExpression = '''
case
    when c.depth <= 1 or p.categoryPOID is null then c.name
    else p.name
end
''';
  const secondCategoryExpression = '''
case
    when c.depth <= 1 or p.categoryPOID is null then null
    else c.name
end
''';

  return '''
select
    t.transactionPOID as transaction_id,
    t.type,
    t.tradeTime as trade_time_ms,
    $amountExpression as amount_text,
    cast($amountExpression as real) as amount_real,
    coalesce($firstCategoryExpression, '未分类') as first_category,
    $secondCategoryExpression as second_category,
    c.categoryPOID as category_id,
    p.categoryPOID as parent_category_id,
    case
        when $secondCategoryExpression is null then coalesce($firstCategoryExpression, '未分类')
        else coalesce($firstCategoryExpression, '未分类') || ' / ' || $secondCategoryExpression
    end as category_path,
    ${context.hasAccountTable ? 'a.name' : 'null'} as account_name,
    ${context.hasAccountTable ? 'a.accountPOID' : 'null'} as account_id,
    ${context.hasTransactionExtensionTable ? "coalesce(e.currency_code, 'CNY')" : "'CNY'"} as currency_code,
    ${context.noteExpression ?? "''"} as note
from t_transaction t
left join t_category c
    on c.categoryPOID = case
        when t.type = 1 then t.buyerCategoryPOID
        else t.sellerCategoryPOID
    end
left join t_category p
    on p.categoryPOID = c.parentCategoryPOID
${context.hasAccountTable ? '''
left join t_account a
    on a.accountPOID = case
        when t.type = 1 then t.buyerAccountPOID
        else t.sellerAccountPOID
    end
''' : ''}
${context.hasTransactionExtensionTable ? '''
left join app_transaction_extensions e
    on e.transaction_id = cast(t.transactionPOID as text)
''' : ''}
''';
}

void _addCategoryFilter(
  List<String> whereParts,
  List<Object?> args,
  List<String>? values,
) {
  final legacyPaths = <String>[];
  final incomePaths = <String>[];
  final expensePaths = <String>[];

  for (final rawValue in values ?? const <String>[]) {
    final value = rawValue.trim();
    if (value.isEmpty) {
      continue;
    }
    final separator = value.indexOf('\u0000');
    if (separator <= 0) {
      legacyPaths.add(value);
      continue;
    }
    final type = value.substring(0, separator);
    final path = value.substring(separator + 1).trim();
    if (path.isEmpty) {
      continue;
    }
    if (type == 'income') {
      incomePaths.add(path);
    } else if (type == 'expense') {
      expensePaths.add(path);
    } else {
      legacyPaths.add(value);
    }
  }

  final parts = <String>[];
  if (legacyPaths.isNotEmpty) {
    parts.add(
      'category_path in (${List.filled(legacyPaths.length, '?').join(', ')})',
    );
    args.addAll(legacyPaths);
  }
  if (incomePaths.isNotEmpty) {
    parts.add(
      '(type = 1 and category_path in (${List.filled(incomePaths.length, '?').join(', ')}))',
    );
    args.addAll(incomePaths);
  }
  if (expensePaths.isNotEmpty) {
    parts.add(
      '(type = 0 and category_path in (${List.filled(expensePaths.length, '?').join(', ')}))',
    );
    args.addAll(expensePaths);
  }
  if (parts.isNotEmpty) {
    whereParts.add('(${parts.join(' or ')})');
  }
}

void _addInFilter(
  List<String> whereParts,
  List<Object?> args,
  String column,
  List<String>? values,
) {
  final cleaned = [
    for (final value in values ?? const <String>[])
      if (value.trim().isNotEmpty) value.trim(),
  ];
  if (cleaned.isEmpty) {
    return;
  }
  whereParts.add('$column in (${List.filled(cleaned.length, '?').join(', ')})');
  args.addAll(cleaned);
}

double _doubleValue(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

String _quoteIdentifier(String identifier) {
  return '"${identifier.replaceAll('"', '""')}"';
}

class _ImporterContext {
  const _ImporterContext({
    required this.hasTables,
    required this.noteExpression,
    required this.hasAccountTable,
    required this.hasTransactionExtensionTable,
  });

  final bool hasTables;
  final String? noteExpression;
  final bool hasAccountTable;
  final bool hasTransactionExtensionTable;
}

class _FilteredTransactionSql {
  const _FilteredTransactionSql({
    required this.sql,
    required this.whereSql,
    required this.args,
  });

  final String sql;
  final String whereSql;
  final List<Object?> args;
}

class _QueryStatement {
  const _QueryStatement({required this.sql, required this.args});

  final String sql;
  final List<Object?> args;
}
