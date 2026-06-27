import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fuckssj/src/data/ledger_transaction_repository.dart';
import 'package:fuckssj/src/importer/ledger_snapshot.dart';
import 'package:fuckssj/src/importer/suishouji_importer.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('creates and edits transactions in strict imported schemas', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'fuckssj_transaction_repository_',
    );
    final databasePath =
        '${tempDir.path}${Platform.pathSeparator}ledger.sqlite';
    final db = sqlite3.open(databasePath);

    try {
      db
        ..execute('''
          create table t_category (
            categoryPOID integer not null unique,
            name text not null,
            parentCategoryPOID integer not null,
            depth integer not null,
            path text not null,
            type integer not null,
            ordered integer not null,
            hidden integer not null
          )
        ''')
        ..execute('''
          create table t_account (
            accountPOID integer not null unique,
            name text not null,
            accountGroupPOID integer,
            ordered integer not null,
            hidden integer not null
          )
        ''')
        ..execute('''
          create table t_transaction (
            transactionPOID integer not null unique,
            createdTime integer not null,
            modifiedTime integer not null,
            tradeTime integer not null,
            memo text not null,
            type integer not null,
            buyerAccountPOID integer,
            buyerCategoryPOID integer,
            buyerMoney text,
            sellerAccountPOID integer,
            sellerCategoryPOID integer,
            sellerMoney text
          )
        ''');
    } finally {
      db.dispose();
    }

    try {
      const rootCategory = LedgerTransactionChoice(
        id: 'ssj_10',
        label: '餐饮',
        value: '餐饮',
        sqliteId: 10,
      );
      const childCategory = LedgerTransactionChoice(
        id: 'ssj_11',
        label: '烟酒饮品',
        value: '餐饮 / 烟酒饮品',
        sqliteId: 11,
        parent: rootCategory,
      );
      const account = LedgerTransactionChoice(
        id: 'ssj_account_20',
        label: '现金',
        value: '现金',
        sqliteId: 20,
      );
      final repository = LedgerTransactionRepository();
      final tradeTime = DateTime.fromMillisecondsSinceEpoch(1700000000000);

      final transactionId = await repository.save(
        databasePath: databasePath,
        record: null,
        draft: LedgerTransactionDraft(
          kind: TransactionKind.expense,
          amountText: '14',
          tradeTime: tradeTime,
          category: childCategory,
          account: account,
          currencyCode: 'USD',
          note: '买饮料',
        ),
      );

      final afterCreate = sqlite3.open(databasePath);
      try {
        final transaction = afterCreate
            .select(
              'select * from t_transaction where transactionPOID = ?',
              [transactionId],
            )
            .single;
        expect(transaction['transactionPOID'], transactionId);
        expect(transaction['sellerCategoryPOID'], 11);
        expect(transaction['sellerAccountPOID'], 20);
        expect(transaction['sellerMoney'], '14');
        expect(transaction['buyerCategoryPOID'], isNull);
        expect(transaction['createdTime'], isA<int>());
        expect(transaction['modifiedTime'], isA<int>());

        final root = afterCreate
            .select('select * from t_category where categoryPOID = 10')
            .single;
        expect(root['parentCategoryPOID'], -1);
        final child = afterCreate
            .select('select * from t_category where categoryPOID = 11')
            .single;
        expect(child['parentCategoryPOID'], 10);

        final extension = afterCreate
            .select(
              'select * from app_transaction_extensions where transaction_id = ?',
              [transactionId.toString()],
            )
            .single;
        expect(extension['currency_code'], 'USD');
      } finally {
        afterCreate.dispose();
      }

      await repository.save(
        databasePath: databasePath,
        record: TransactionRecord(
          id: transactionId.toString(),
          kind: TransactionKind.expense,
          amount: '14',
          tradeTime: tradeTime,
          firstCategory: '餐饮',
          secondCategory: '烟酒饮品',
          categoryId: 11,
          parentCategoryId: 10,
          accountName: '现金',
          accountId: 20,
          currencyCode: 'USD',
          note: '买饮料',
        ),
        draft: LedgerTransactionDraft(
          kind: TransactionKind.income,
          amountText: '88',
          tradeTime: tradeTime.add(const Duration(minutes: 1)),
          category: childCategory,
          account: account,
          currencyCode: 'CNY',
          note: '退款',
        ),
      );

      final snapshot = await SuiShouJiImporter().load(databasePath);
      expect(snapshot.transactions, hasLength(1));
      expect(snapshot.transactions.single.id, transactionId.toString());
      expect(snapshot.transactions.single.kind, TransactionKind.income);
      expect(snapshot.transactions.single.amount, '88');
      expect(snapshot.transactions.single.accountId, 20);
      expect(snapshot.transactions.single.categoryId, 11);
      expect(snapshot.transactions.single.currencyCode, 'CNY');
      expect(snapshot.transactions.single.note, '退款');
    } finally {
      await tempDir.delete(recursive: true);
    }
  });
}
