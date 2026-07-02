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
            buyerMoney text,
            memo text
          )
        ''')
        ..execute(
          "insert into t_category values (10, '餐饮', null, 1, '/-1/10/', 0)",
        )
        ..execute(
          "insert into t_category values (11, '烟酒饮品', 10, 2, '/-1/10/11/', 0)",
        )
        ..execute(
          "insert into t_category values (20, '工资', null, 1, '/-1/20/', 1)",
        )
        ..execute(
          "insert into t_transaction values (1, 0, 1700000000000, 11, '12.50', null, null, '买饮料')",
        )
        ..execute(
          "insert into t_transaction values (2, 1, 1700000100000, null, null, 20, '5000', '工资入账')",
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
      expect(snapshot.transactions.last.categoryPath, '餐饮 / 烟酒饮品');
      expect(snapshot.transactions.last.categoryId, 11);
      expect(snapshot.transactions.last.parentCategoryId, 10);
      expect(snapshot.transactions.last.note, '买饮料');
    } finally {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'queries SuiShouJi records with direction amount date and note filters',
    () async {
      final tempDir = await Directory.systemTemp.createTemp('fuckssj_query_');
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
            buyerMoney text,
            memo text
          )
        ''')
          ..execute(
            "insert into t_category values (10, '餐饮', null, 1, '/-1/10/', 0)",
          )
          ..execute(
            "insert into t_category values (11, '烟酒饮品', 10, 2, '/-1/10/11/', 0)",
          )
          ..execute(
            "insert into t_category values (20, '工资', null, 1, '/-1/20/', 1)",
          )
          ..execute(
            "insert into t_transaction values (1, 0, 1700000000000, 11, '12.50', null, null, '买饮料')",
          )
          ..execute(
            "insert into t_transaction values (2, 0, 1700000200000, 11, '99.00', null, null, '聚餐')",
          )
          ..execute(
            "insert into t_transaction values (3, 1, 1700000300000, null, null, 20, '5000', '工资入账')",
          );
      } finally {
        db.dispose();
      }

      try {
        final snapshot = await SuiShouJiImporter().query(
          databasePath,
          TransactionQuery(
            startDate: DateTime.fromMillisecondsSinceEpoch(1699999900000),
            endDate: DateTime.fromMillisecondsSinceEpoch(1700000100001),
            includeIncome: false,
            minAmount: 10,
            maxAmount: 20,
            noteKeyword: '饮料',
          ),
        );

        expect(snapshot.transactions, hasLength(1));
        expect(snapshot.transactions.single.kind, TransactionKind.expense);
        expect(snapshot.transactions.single.amount, '12.50');
        expect(snapshot.transactions.single.categoryPath, '餐饮 / 烟酒饮品');
        expect(snapshot.transactions.single.categoryId, 11);
        expect(snapshot.transactions.single.parentCategoryId, 10);
        expect(snapshot.transactions.single.note, '买饮料');
      } finally {
        await tempDir.delete(recursive: true);
      }
    },
  );

  test('queries SuiShouJi records by account ids', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'fuckssj_account_query_',
    );
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
          create table t_account (
            accountPOID integer primary key,
            name text not null
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
            buyerMoney text,
            sellerAccountPOID integer,
            buyerAccountPOID integer,
            memo text
          )
        ''')
        ..execute(
          "insert into t_category values (10, '餐饮', null, 1, '/-1/10/', 0)",
        )
        ..execute(
          "insert into t_category values (20, '工资', null, 1, '/-1/20/', 1)",
        )
        ..execute("insert into t_account values (100, '现金')")
        ..execute("insert into t_account values (200, '微信')")
        ..execute(
          "insert into t_transaction values (1, 0, 1700000000000, 10, '12.50', 0, '12.50', 0, 100, '现金支出')",
        )
        ..execute(
          "insert into t_transaction values (2, 1, 1700000100000, 0, '5000', 20, '5000', 100, 0, '现金收入')",
        )
        ..execute(
          "insert into t_transaction values (3, 0, 1700000200000, 10, '8.00', 0, '8.00', 0, 200, '微信支出')",
        );
    } finally {
      db.dispose();
    }

    try {
      final cashSnapshot = await SuiShouJiImporter().query(
        databasePath,
        const TransactionQuery(accountIds: [100]),
      );
      final wechatSnapshot = await SuiShouJiImporter().query(
        databasePath,
        const TransactionQuery(accountIds: [200]),
      );

      expect(cashSnapshot.transactions, hasLength(2));
      expect(
        cashSnapshot.transactions.map((record) => record.note),
        containsAll(['现金支出', '现金收入']),
      );
      expect(
        cashSnapshot.transactions.every((record) => record.accountId == 100),
        isTrue,
      );
      expect(wechatSnapshot.transactions, hasLength(1));
      expect(wechatSnapshot.transactions.single.note, '微信支出');
      expect(wechatSnapshot.transactions.single.accountId, 200);
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
