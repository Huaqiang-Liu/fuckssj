import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fuckssj/src/app/fuckssj_app.dart';

void main() {
  testWidgets('shows ledger entry actions', (tester) async {
    await tester.pumpWidget(const FuckssjApp());

    expect(find.text('随手记迁移账本'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '创建空白账本'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '从 SQLite 创建'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '从 KBF 创建'), findsOneWidget);
  });
}
