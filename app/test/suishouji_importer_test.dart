import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fuckssj/src/importer/ledger_snapshot.dart';
import 'package:fuckssj/src/importer/suishouji_importer.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('loads recent SuiShouJi income and expense records', () async {
    final tempDir = await Directory.systemTemp.createTemp('fuckssj_importer_');
    final databasePath =
        '${tempDir.path}${Platform.pathSeparator}ledger.sqlite';
    final db = sqlite3.open(databasePath);

    try {
      db
        ..execute('''
          create table t_category (
            categoryPOID integer primary key,
            name text not null,
            parentCategoryPOID integer,
            depth integer not null,
            path text,
            type integer
          )
        ''')
        ..execute('''
          create table t_transaction (
            transactionPOID integer primary key,
            type integer not null,
            tradeTime integer not null,
            sellerCategoryPOID integer,
            sellerMoney text,
            buyerCategoryPOID integer,
            buyerMoney text
          )
        ''')
        ..execute(
          "insert into t_category values (10, '餐饮', null, 1, '/-1/10/', 0)",
        )
        ..execute(
          "insert into t_category values (11, '早餐', 10, 2, '/-1/10/11/', 0)",
        )
        ..execute(
          "insert into t_category values (20, '工资', null, 1, '/-1/20/', 1)",
        )
        ..execute(
          "insert into t_transaction values (1, 0, 1700000000000, 11, '12.50', null, null)",
        )
        ..execute(
          "insert into t_transaction values (2, 1, 1700000100000, null, null, 20, '5000')",
        );
    } finally {
      db.dispose();
    }

    try {
      final snapshot = await SuiShouJiImporter().load(databasePath);

      expect(snapshot.hasSuiShouJiTables, isTrue);
      expect(snapshot.transactions, hasLength(2));
      expect(snapshot.transactions.first.kind, TransactionKind.income);
      expect(snapshot.transactions.first.amount, '5000');
      expect(snapshot.transactions.first.categoryPath, '工资');
      expect(snapshot.transactions.last.kind, TransactionKind.expense);
      expect(snapshot.transactions.last.amount, '12.50');
      expect(snapshot.transactions.last.categoryPath, '餐饮 / 早餐');
    } finally {
      await tempDir.delete(recursive: true);
    }
  });

  test('returns an empty snapshot for blank app ledgers', () async {
    final tempDir = await Directory.systemTemp.createTemp('fuckssj_blank_');
    final databasePath =
        '${tempDir.path}${Platform.pathSeparator}ledger.sqlite';
    sqlite3.open(databasePath).dispose();

    try {
      final snapshot = await SuiShouJiImporter().load(databasePath);

      expect(snapshot.hasSuiShouJiTables, isFalse);
      expect(snapshot.transactions, isEmpty);
    } finally {
      await tempDir.delete(recursive: true);
    }
  });
}
