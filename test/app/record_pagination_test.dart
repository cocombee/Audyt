import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';

void main() {
  for (final size in [5, 10]) {
    testWidgets('page size $size preserves record identity and bounds', (
      tester,
    ) async {
      int? opened;
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(
            body: AccountingRecordList(
              defaultPageSize: size,
              children: [
                for (var i = 0; i < 16; i++)
                  TextButton(
                    key: ValueKey('record-$i'),
                    onPressed: () => opened = i,
                    child: Text('Reference $i'),
                  ),
              ],
            ),
          ),
        ),
      );
      expect(find.text('Reference 0'), findsOneWidget);
      expect(find.text('Reference $size'), findsNothing);
      for (final divider in tester.widgetList<Divider>(find.byType(Divider))) {
        expect(divider.indent, accountingContentInset);
        expect(divider.endIndent, accountingContentInset);
      }
      await tester.tap(find.byKey(const ValueKey('record-page-next')));
      await tester.pumpAndSettle();
      expect(find.text('Reference 0'), findsNothing);
      await tester.tap(find.byKey(ValueKey('record-$size')));
      expect(opened, size);
      await tester.tap(find.byKey(const ValueKey('record-page-previous')));
      await tester.pumpAndSettle();
      expect(find.text('Reference 0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
