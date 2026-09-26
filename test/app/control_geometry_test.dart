import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final compact in [true, false]) {
    testWidgets('Field and action painted frames align, compact=$compact', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AccountingTheme.light(),
        home: Scaffold(body: AccountingButtonGroup(
          compact: compact,
          child: Builder(builder: (context) => Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              SizedBox(width: 240, child: TextField(
                decoration: accountingSingleLineInputDecoration(context),
              )),
              AccountingButton.primary(context, key: const ValueKey('run'),
                onPressed: () {}, child: const Text('Run Report')),
            ],
          )),
        )),
      ));
      final field = tester.getRect(find.byType(InputDecorator));
      final button = tester.getRect(find.descendant(
        of: find.byKey(const ValueKey('run')), matching: find.byType(Material)).first);
      expect(field.height, accountingControlHeight);
      expect(button.height, field.height);
      expect(button.top, field.top);
      expect(button.bottom, field.bottom);
      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(tester.getRect(find.byType(InputDecorator)), field);
      expect(tester.takeException(), isNull);
    });
  }
}
