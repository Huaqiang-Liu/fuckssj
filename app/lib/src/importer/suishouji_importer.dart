import 'package:sqlite3/sqlite3.dart';

import 'ledger_snapshot.dart';

class SuiShouJiImporter {
  Future<LedgerSnapshot> load(String databasePath, {int limit = 200}) async {
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

      final rows = db.select(_transactionSql, [limit]);
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
}

const _transactionSql = '''
select
    t.transactionPOID as transaction_id,
    t.type,
    t.tradeTime as trade_time_ms,
    cast(case
        when t.type = 1 then t.buyerMoney
        else t.sellerMoney
    end as text) as amount,
    case
        when c.depth <= 1 or p.categoryPOID is null then c.name
        else p.name
    end as first_category,
    case
        when c.depth <= 1 or p.categoryPOID is null then null
        else c.name
    end as second_category
from t_transaction t
left join t_category c
    on c.categoryPOID = case
        when t.type = 1 then t.buyerCategoryPOID
        else t.sellerCategoryPOID
    end
left join t_category p
    on p.categoryPOID = c.parentCategoryPOID
where t.type in (0, 1)
order by t.tradeTime desc, t.transactionPOID desc
limit ?
''';
