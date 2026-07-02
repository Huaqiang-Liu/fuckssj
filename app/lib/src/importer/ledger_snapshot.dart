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

class TransactionSummary {
  const TransactionSummary({required this.count, required this.rows});

  const TransactionSummary.empty() : count = 0, rows = const [];

  final int count;
  final List<TransactionSummaryRow> rows;
}

class TransactionSummaryRow {
  const TransactionSummaryRow({
    required this.kind,
    required this.currencyCode,
    required this.amount,
    this.firstCategory,
  });

  final TransactionKind kind;
  final String currencyCode;
  final double amount;
  final String? firstCategory;
}

class DashboardSummary {
  const DashboardSummary({
    required this.today,
    required this.week,
    required this.month,
    required this.year,
  });

  const DashboardSummary.empty()
    : today = const TransactionSummary.empty(),
      week = const TransactionSummary.empty(),
      month = const TransactionSummary.empty(),
      year = const TransactionSummary.empty();

  final TransactionSummary today;
  final TransactionSummary week;
  final TransactionSummary month;
  final TransactionSummary year;
}

class TransactionRecord {
  const TransactionRecord({
    required this.id,
    required this.kind,
    required this.amount,
    required this.tradeTime,
    required this.firstCategory,
    this.secondCategory,
    this.categoryId,
    this.parentCategoryId,
    this.accountName,
    this.accountId,
    this.currencyCode = 'CNY',
    this.note,
  });

  final String id;
  final TransactionKind kind;
  final String amount;
  final DateTime tradeTime;
  final String firstCategory;
  final String? secondCategory;
  final int? categoryId;
  final int? parentCategoryId;
  final String? accountName;
  final int? accountId;
  final String currencyCode;
  final String? note;

  String get categoryPath {
    final second = secondCategory;
    if (second == null || second.isEmpty) {
      return firstCategory;
    }
    return '$firstCategory / $second';
  }
}

class TransactionQuery {
  const TransactionQuery({
    this.startDate,
    this.endDate,
    this.includeIncome = true,
    this.includeExpense = true,
    this.minAmount,
    this.maxAmount,
    this.noteKeyword,
    this.categoryPaths,
    this.accountIds,
    this.accountNames,
    this.currencyCodes,
    this.limit = 30,
    this.offset = 0,
  });

  final DateTime? startDate;
  final DateTime? endDate;
  final bool includeIncome;
  final bool includeExpense;
  final double? minAmount;
  final double? maxAmount;
  final String? noteKeyword;
  final List<String>? categoryPaths;
  final List<int>? accountIds;
  final List<String>? accountNames;
  final List<String>? currencyCodes;
  final int limit;
  final int offset;

  TransactionQuery copyWith({int? limit, int? offset}) {
    return TransactionQuery(
      startDate: startDate,
      endDate: endDate,
      includeIncome: includeIncome,
      includeExpense: includeExpense,
      minAmount: minAmount,
      maxAmount: maxAmount,
      noteKeyword: noteKeyword,
      categoryPaths: categoryPaths,
      accountIds: accountIds,
      accountNames: accountNames,
      currencyCodes: currencyCodes,
      limit: limit ?? this.limit,
      offset: offset ?? this.offset,
    );
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
