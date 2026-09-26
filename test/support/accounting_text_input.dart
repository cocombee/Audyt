import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_description_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> enterAccountingText(
  WidgetTester tester,
  Finder target,
  String value,
) async {
  final fields = find.descendant(
    of: target,
    matching: find.byType(AccountingDescriptionField),
  );
  final direct = tester.widget(target) is AccountingDescriptionField;
  if (direct || fields.evaluate().isNotEmpty) {
    final field = direct ? target : fields.first;
    final state = tester.state<AccountingDescriptionFieldState>(field);
    state.focus.requestFocus();
    await tester.pump();
    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: '$value\n',
        selection: TextSelection.collapsed(offset: value.length),
      ),
    );
    await tester.pump();
  } else {
    await tester.enterText(target, value);
  }
}

Finder accountingDescriptionText(String text) => find.byElementPredicate(
  (element) =>
      element is StatefulElement &&
      element.state is AccountingDescriptionFieldState &&
      (element.state as AccountingDescriptionFieldState)
              .editor
              .plainDescription ==
          text,
);

Future<void> revealAccountingRecord(WidgetTester tester, Finder target) async {
  for (var attempt = 0; target.evaluate().isEmpty && attempt < 100; attempt++) {
    final pages = tester.widgetList<AccountingRecordPagination>(
      find.byType(AccountingRecordPagination),
    );
    final next = pages.where((page) => page.onNext != null).firstOrNull;
    if (next == null) break;
    next.onNext!();
    await tester.pumpAndSettle();
  }
}
