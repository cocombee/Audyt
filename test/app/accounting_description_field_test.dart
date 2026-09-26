import 'package:audyt/app/accounting_description_field.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/core/text/transaction_description.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' show ChangeSource;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/accounting_text_input.dart';

void main() {
  test(
    'portable list layout reserves two digits and wraps within its own row',
    () {
      double measure(String text) => text.runes.length.toDouble();
      final lines = layoutTransactionDescription(
        '1. one two three four five\n2. six seven\n\nPlain text',
        15,
        measure,
      );
      expect(lines.first.marker, '1.');
      expect(lines.first.indent, 5);
      expect(lines[1].marker, isNull);
      expect(lines[1].indent, lines.first.indent);
      for (final line in lines) {
        expect(line.indent + measure(line.text), lessThanOrEqualTo(15));
      }
      for (final (start, next) in [
        ('1.', '2.'),
        ('9.', '10.'),
        ('i.', 'ii.'),
        ('ii.', 'iii.'),
        ('I.', 'II.'),
        ('a.', 'b.'),
        ('A.', 'B.'),
        ('-', '-'),
      ]) {
        expect(DescriptionParagraph.parse('$start text').nextMarker, next);
      }
    },
  );
  testWidgets(
    'multiline formatting retains existing character limits and legacy text',
    (tester) async {
      final controller = TextEditingController(
        text: 'Legacy text above the limit',
      );
      addTearDown(controller.dispose);
      const key = ValueKey('limited-reason');
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(
            body: SizedBox(
              width: 230,
              child: AccountingDescriptionField(
                key: key,
                controller: controller,
                fixedLines: 2,
                maxLength: 20,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final field = find.byKey(key);
      final legacy = controller.text;
      await enterAccountingText(tester, field, '$legacy extended');
      await tester.pumpAndSettle();
      expect(controller.text, legacy);
      await enterAccountingText(tester, field, '1. Reviewed');
      await tester.pumpAndSettle();
      expect(controller.text, '1. Reviewed');
      await enterAccountingText(
        tester,
        field,
        'This new reason exceeds twenty characters',
      );
      await tester.pumpAndSettle();
      expect(controller.text, '1. Reviewed');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'fixed multiline boxes wrap, scroll vertically and continue lists',
    (tester) async {
      await (FontLoader(
        'Inter',
      )..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2'))).load();
      final controller = TextEditingController(text: 'Memo');
      addTearDown(controller.dispose);
      const key = ValueKey('fixed-memo');
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(
            body: SizedBox(
              width: 230,
              child: AccountingDescriptionField(
                key: key,
                controller: controller,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final field = find.byKey(key);
      final frame = tester.getRect(field);
      // Approved registration screenshot: approximately 80 logical pixels,
      // with current Inter and the existing field insets.
      expect(frame.height, inInclusiveRange(77, 83));
      final text = '1. ${List.filled(30, 'A long memo line').join(' ')}';
      await enterAccountingText(tester, field, text);
      await tester.pumpAndSettle();
      final scrollables = find.descendant(
        of: field,
        matching: find.byType(Scrollable),
      );
      final positions = scrollables
          .evaluate()
          .map((e) => (e as StatefulElement).state as ScrollableState)
          .map((s) => s.position)
          .toList();
      final vertical = positions.singleWhere((p) => p.axis == Axis.vertical);
      expect(positions.where((p) => p.axis == Axis.horizontal), isEmpty);
      expect(tester.getRect(field).size, frame.size);
      expect(tester.getRect(field).height, closeTo(frame.height, .1));
      expect(
        vertical.maxScrollExtent,
        greaterThan(frame.height),
        reason: 'Long text wraps and scrolls vertically inside the fixed box.',
      );
      final editor = tester
          .state<AccountingDescriptionFieldState>(field)
          .editor;
      var end = editor.document.length - 1;
      editor.replaceText(
        end,
        0,
        '\n',
        TextSelection.collapsed(offset: end + 1),
      );
      await tester.pumpAndSettle();
      expect(controller.text, endsWith('\n2. '));
      await enterAccountingText(
        tester,
        field,
        [for (var n = 1; n <= 12; n++) '$n. Memo paragraph $n'].join('\n'),
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(field).size, frame.size);
      expect(vertical.maxScrollExtent, greaterThan(0));
      expect(controller.text, contains('\n12. Memo paragraph 12'));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'grows, wraps, continues lists and keeps portable description text',
    (tester) async {
      await (FontLoader(
        'Inter',
      )..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2'))).load();
      final controller = TextEditingController(text: 'Short description');
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(
            body: SizedBox(
              width: 230,
              child: AccountingDescriptionField(
                key: const ValueKey('description'),
                controller: controller,
                fixedLines: null,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final finder = find.byKey(const ValueKey('description'));
      final original = tester.getRect(finder);
      await enterAccountingText(
        tester,
        finder,
        '1. A long description that wraps to several visual lines within the original field width and keeps the last text padding.',
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(finder).width, original.width);
      expect(tester.getRect(finder).height, greaterThan(original.height));
      expect(controller.text, startsWith('1. A long description'));
      final editor = tester
          .state<AccountingDescriptionFieldState>(finder)
          .editor;
      final end = editor.document.length - 1;
      editor.updateSelection(
        TextSelection.collapsed(offset: end),
        ChangeSource.local,
      );
      editor.replaceText(
        end,
        0,
        '\n',
        TextSelection.collapsed(offset: end + 1),
      );
      await tester.pumpAndSettle();
      expect(controller.text, endsWith('\n2. '));
      editor.replaceText(
        end + 1,
        0,
        '\n',
        TextSelection.collapsed(offset: end + 2),
      );
      await tester.pumpAndSettle();
      expect(controller.text, endsWith('\n'));
      expect(tester.takeException(), isNull);
    },
  );
}
