import 'package:audyt/features/accounting/presentation/record_expense_page.dart';
import 'package:audyt/features/accounting/presentation/widgets/accounting_formatters.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formats only digits into dd-mm-yyyy with an eight-digit limit', () {
    const formatter = DateInputFormatter();
    final value = formatter.formatEditUpdate(
      TextEditingValue.empty,
      const TextEditingValue(
        text: '01022026abc',
        selection: TextSelection.collapsed(offset: 11),
      ),
    );

    expect(value.text, '01-02-2026');
    expect(value.selection.baseOffset, value.text.length);

    final capped = formatter.formatEditUpdate(
      value,
      const TextEditingValue(
        text: '010220261234',
        selection: TextSelection.collapsed(offset: 12),
      ),
    );
    expect(capped.text, '01-02-2026');
  });

  test('replacing date segments advances through day, month, and year', () {
    const formatter = DateInputFormatter();
    var value = const TextEditingValue(
      text: '24-09-2026',
      selection: TextSelection(baseOffset: 0, extentOffset: 2),
    );

    value = formatter.formatEditUpdate(
      value,
      const TextEditingValue(
        text: '1-09-2026',
        selection: TextSelection.collapsed(offset: 1),
      ),
    );
    expect(value.text, '14-09-2026');
    value = formatter.formatEditUpdate(
      value,
      const TextEditingValue(
        text: '184-09-2026',
        selection: TextSelection.collapsed(offset: 2),
      ),
    );
    expect(value.text, '18-09-2026');
    expect(
      value.selection,
      const TextSelection(baseOffset: 3, extentOffset: 5),
    );

    value = formatter.formatEditUpdate(
      value,
      const TextEditingValue(
        text: '18-1-2026',
        selection: TextSelection.collapsed(offset: 4),
      ),
    );
    expect(value.text, '18-19-2026');
    value = formatter.formatEditUpdate(
      value,
      const TextEditingValue(
        text: '18-129-2026',
        selection: TextSelection.collapsed(offset: 5),
      ),
    );
    expect(value.text, '18-12-2026');
    expect(
      value.selection,
      const TextSelection(baseOffset: 6, extentOffset: 10),
    );
    value = formatter.formatEditUpdate(
      value,
      const TextEditingValue(
        text: '18-12-2',
        selection: TextSelection.collapsed(offset: 7),
      ),
    );
    expect(value.text, '18-12-2026');
    expect(value.selection, const TextSelection.collapsed(offset: 7));
  });

  test('typing at a digit caret overwrites rather than shifting the date', () {
    const formatter = DateInputFormatter();
    final value = formatter.formatEditUpdate(
      const TextEditingValue(
        text: '24-09-2026',
        selection: TextSelection.collapsed(offset: 1),
      ),
      const TextEditingValue(
        text: '284-09-2026',
        selection: TextSelection.collapsed(offset: 2),
      ),
    );
    expect(value.text, '28-09-2026');
    expect(
      value.selection,
      const TextSelection(baseOffset: 3, extentOffset: 5),
    );
  });

  testWidgets('double-clicking a date selects its editable segment', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(960, 900));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: RecordExpensePage()));

    final date = find.byKey(const ValueKey('expense-field-date'));
    final editable = find.descendant(
      of: date,
      matching: find.byType(EditableText),
    );
    final controller = tester.widget<EditableText>(editable).controller;
    controller.text = '24-09-2026';
    final render = tester.renderObject<RenderEditable>(
      find.descendant(
        of: editable,
        matching: find.byElementPredicate(
          (element) => element.renderObject is RenderEditable,
        ),
      ),
    );
    final point = render.localToGlobal(
      render.getLocalRectForCaret(const TextPosition(offset: 1)).center,
    );
    await tester.tapAt(point);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(point);
    await tester.pump();
    expect(controller.selection.start, 0);
    expect(controller.selection.end, 2);
  });

  testWidgets(
    'date field displays and validates the local dd-mm-yyyy contract',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 1200));
      addTearDown(() async => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        const MaterialApp(
          home: RecordExpensePage(paymentAccounts: <String>['Cash']),
        ),
      );

      final date = find.byKey(const ValueKey('expense-field-date'));
      final controller = tester.widget<TextFormField>(date).controller!;
      expect(RegExp(r'^\d{2}-\d{2}-\d{4}$').hasMatch(controller.text), isTrue);

      await tester.enterText(date, '31022026');
      expect(controller.text, '31-02-2026');
      await tester.ensureVisible(
        find.byKey(const ValueKey('record-expense-save')),
      );
      await tester.tap(find.byKey(const ValueKey('record-expense-save')));
      await tester.pump();
      expect(find.text('Enter a valid local date.'), findsOneWidget);
    },
  );
}
