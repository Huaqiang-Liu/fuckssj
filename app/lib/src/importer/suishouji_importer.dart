import 'package:sqlite3/sqlite3.dart';

import 'ledger_snapshot.dart';

class SuiShouJiImporter {
  Future<LedgerSnapshot> load(String databasePath, {int limit = 200}) async {
    return query(databasePath, TransactionQuery(limit: limit));
  }

  Future<LedgerSnapshot> query(
    String databasePath,
    TransactionQuery query,
  ) async {
    final db = sqlite3.open(databasePath);
    try {
      final hasTables =
          _tableExists(db, 't_transaction') && _tableExists(db, 't_category');
      if (!hasTables) {
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

      final noteExpression = _noteExpression(db);
      final statement = _buildTransactionSql(
        query: query,
        noteExpression: noteExpression,
        hasAccountTable: _tableExists(db, 't_account'),
        hasTransactionExtensionTable: _tableExists(
          db,
          'app_transaction_extensions',
        ),
      );
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

_QueryStatement _buildTransactionSql({
  required TransactionQuery query,
  required String? noteExpression,
  required bool hasAccountTable,
  required bool hasTransactionExtensionTable,
}) {
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
    if (noteExpression == null) {
      whereParts.add('0 = 1');
    } else {
      whereParts.add('note like ?');
      args.add('%$noteKeyword%');
    }
  }
  _addInFilter(whereParts, args, 'category_path', query.categoryPaths);
  _addInFilter(whereParts, args, 'account_name', query.accountNames);
  _addInFilter(whereParts, args, 'currency_code', query.currencyCodes);
  args
    ..add(query.limit)
    ..add(query.offset);

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
from (
    select
        t.transactionPOID as transaction_id,
        t.type,
        t.tradeTime as trade_time_ms,
        $amountExpression as amount_text,
        cast($amountExpression as real) as amount_real,
        $firstCategoryExpression as first_category,
        $secondCategoryExpression as second_category,
        c.categoryPOID as category_id,
        p.categoryPOID as parent_category_id,
        case
            when $secondCategoryExpression is null then coalesce($firstCategoryExpression, '未分类')
            else coalesce($firstCategoryExpression, '未分类') || ' / ' || $secondCategoryExpression
        end as category_path,
        ${hasAccountTable ? 'a.name' : 'null'} as account_name,
        ${hasAccountTable ? 'a.accountPOID' : 'null'} as account_id,
        ${hasTransactionExtensionTable ? "coalesce(e.currency_code, 'CNY')" : "'CNY'"} as currency_code,
        ${noteExpression ?? "''"} as note
    from t_transaction t
    left join t_category c
        on c.categoryPOID = case
            when t.type = 1 then t.buyerCategoryPOID
            else t.sellerCategoryPOID
        end
    left join t_category p
        on p.categoryPOID = c.parentCategoryPOID
    ${hasAccountTable ? '''
    left join t_account a
        on a.accountPOID = case
            when t.type = 1 then t.buyerAccountPOID
            else t.sellerAccountPOID
        end
    ''' : ''}
    ${hasTransactionExtensionTable ? '''
    left join app_transaction_extensions e
        on e.transaction_id = cast(t.transactionPOID as text)
    ''' : ''}
) t
where ${whereParts.join(' and ')}
order by trade_time_ms desc, transaction_id desc
limit ?
offset ?
''',
    args: args,
  );
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

String _quoteIdentifier(String identifier) {
  return '"${identifier.replaceAll('"', '""')}"';
}

class _QueryStatement {
  const _QueryStatement({required this.sql, required this.args});

  final String sql;
  final List<Object?> args;
}
