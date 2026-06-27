import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fuckssj/src/data/ledger_repository.dart';
import 'package:fuckssj/src/features/ledger/ledger_home_page.dart';

void main() {
  testWidgets('home page shows ledger entry actions', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          storeState: const LedgerStoreState(ledgers: [], lastLedgerId: null),
          loading: false,
          errorMessage: null,
          onCreateBlank: () {},
          onImportSqlite: () {},
          onImportKbf: () {},
          onOpenLedger: (_) {},
          onRenameLedger: (_) {},
          onEditLedgerNote: (_) {},
          onExportLedger: (_) {},
          onDeleteLedger: (_) {},
          onPendingFeature: (_) {},
        ),
      ),
    );

    expect(find.text('账本'), findsOneWidget);
    expect(find.text('创建或导入一个账本开始使用。'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '创建空白账本'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '从 SQLite 创建'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '从随手记本地备份导出的 KBF 文件创建'), findsOneWidget);
  });
}
