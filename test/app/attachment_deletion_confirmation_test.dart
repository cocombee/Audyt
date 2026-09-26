import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('attachment deletion requires explicit confirmation', (
    tester,
  ) async {
    var deleted = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                if (await confirmAttachmentDeletion(context)) deleted = true;
              },
              child: const Text('Trash'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Trash'));
    await tester.pumpAndSettle();
    expect(find.text('Delete Attachment?'), findsOneWidget);
    expect(deleted, false);
    await tester.tap(find.bySemanticsLabel('Close').last);
    await tester.pumpAndSettle();
    expect(deleted, false);
    await tester.tap(find.text('Trash'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(deleted, true);
  });
}
