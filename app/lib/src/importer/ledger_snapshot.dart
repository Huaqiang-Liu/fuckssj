class LedgerSnapshot {
  const LedgerSnapshot({
    required this.databasePath,
    required this.transactions,
    required this.hasSuiShouJiTables,
  });

  final String databasePath;
  final List<TransactionRecord> transactions;
  final bool hasSuiShouJiTables;
}

class TransactionRecord {
  const TransactionRecord({
    required this.id,
    required this.kind,
    required this.amount,
    required this.tradeTime,
    required this.firstCategory,
    this.secondCategory,
  });

  final String id;
  final TransactionKind kind;
  final String amount;
  final DateTime tradeTime;
  final String firstCategory;
  final String? secondCategory;

  String get categoryPath {
    final second = secondCategory;
    if (second == null || second.isEmpty) {
      return firstCategory;
    }
    return '$firstCategory / $second';
  }
}

enum TransactionKind {
  expense,
  income;

  String get label {
    return switch (this) {
      TransactionKind.expense => '支出',
      TransactionKind.income => '收入',
    };
  }
}
