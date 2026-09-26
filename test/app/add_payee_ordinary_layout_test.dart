import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/field_row_trial.dart';
import 'package:audyt/features/accounting/domain/payee.dart';
import 'package:audyt/features/accounting/presentation/record_expense_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixed_popout_host.dart';
import 'claim_receipts_proposal_test.dart' show prepare, capture;

void main() {
  for (final width in [720.0, 1224.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('actual Add Payee fits and preserves writes at $width/$scale', (
        tester,
      ) async {
        await prepare(tester, width);
        tester.view.physicalSize = Size(width, 1800);
        installFixedPopoutHost(tester);
        final saved = <Payee>[];
        final store = PayeeStore(payees: PayeeCatalog.demo, persist: saved.add);
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AccountingTheme.light(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Scaffold(
                body: RecordExpensePage(
                  includeTopSafeArea: false,
                  payeeStore: store,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        Future<void> open({bool recordSelector = false}) async {
          await tester.tap(find.byKey(const ValueKey('expense-field-payee')));
          await tester.pumpAndSettle();
          if (recordSelector) {
            final add = find.byKey(const ValueKey('expense-add-payee'));
            expect(add, findsOneWidget);
            final firstExisting = find.text(PayeeCatalog.demo.first.name);
            expect(firstExisting, findsOneWidget);
            expect(
              tester.getRect(add).top,
              lessThan(tester.getRect(firstExisting).top),
            );
            await capture(
              tester,
              'Payee Selector First Add ${width.toInt()} Scale ${scale.toInt()}',
            );
          }
          await tester.tap(find.byKey(const ValueKey('expense-add-payee')));
          await tester.pumpAndSettle();
        }

        await open(recordSelector: true);
        final name = find.byKey(const ValueKey('payee-name-field'));
        final type = find.byKey(const ValueKey('payee-type-field'));
        final shared = find.ancestor(
          of: name,
          matching: find.byType(AccountingOrdinaryFields),
        );
        expect(shared, findsOneWidget);
        final usable = tester.getRect(shared);
        final nameLabel = find.byKey(const ValueKey('payee-name-label'));
        expect(
          find.descendant(of: nameLabel, matching: find.text('Payee Name')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: nameLabel, matching: find.text('*')),
          findsOneWidget,
        );
        expect(find.text('Type'), findsOneWidget);
        final nameRect = tester.getRect(
          find.byKey(const ValueKey('payee-name-field-group')),
        );
        final typeRect = tester.getRect(
          find.byKey(const ValueKey('payee-type-field-group')),
        );
        expect(nameRect.width, greaterThanOrEqualTo((usable.width - 20) / 2));
        if ((nameRect.top - typeRect.top).abs() < .1) {
          expect(typeRect.left - nameRect.right, closeTo(20, .1));
        } else {
          expect(typeRect.top - nameRect.bottom, closeTo(20, .1));
          expect(nameRect.width, closeTo(usable.width, .1));
          expect(typeRect.width, closeTo(usable.width, .1));
        }
        final quickTypes = tester.widget<AccountingSelector<String>>(
          find.byWidgetPredicate(
            (w) =>
                w is AccountingSelector<String> &&
                w.triggerKey == const ValueKey('payee-type-field'),
          ),
        );
        expect(
          quickTypes.options.any((o) => o.value == PayeeType.staff.name),
          isFalse,
        );
        await tester.tap(type);
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: find.byKey(const ValueKey('payee-type-menu')),
            matching: find.text('Small Provider'),
          ),
        );
        await tester.pumpAndSettle();
        final selected = find.descendant(
          of: type,
          matching: find.text('Small Provider'),
        );
        final paragraph = tester.renderObject<RenderParagraph>(selected);
        expect(paragraph.didExceedMaxLines, isFalse);
        final glyphs = paragraph.getBoxesForSelection(
          const TextSelection(baseOffset: 0, extentOffset: 14),
        );
        final right = paragraph.localToGlobal(Offset(glyphs.last.right, 0)).dx;
        final arrow = find.descendant(
          of: find.descendant(
            of: type,
            matching: find.byType(AccountingSelectorChevron),
          ),
          matching: find.byType(CustomPaint),
        );
        expect(tester.getRect(arrow).left - right, greaterThanOrEqualTo(19.9));
        await tester.tap(find.byKey(const ValueKey('payee-create-action')));
        await tester.pumpAndSettle();
        expect(find.text('Payee name is required.'), findsOneWidget);
        expect(saved, isEmpty);
        const longName = 'A Very Long Employee And Company Payee Name';
        await tester.enterText(name, longName);
        await tester.pumpAndSettle();
        expect(find.text('Payee name is required.'), findsNothing);
        await capture(
          tester,
          'Add Payee Shared ${width.toInt()} Scale ${scale.toInt()}',
        );
        await tester.tap(find.byKey(const ValueKey('payee-create-action')));
        await tester.pumpAndSettle();
        expect(saved.single.name, longName);
        expect(saved.single.type, PayeeType.smallProvider);
        expect(store.all.where((p) => p.name == longName), hasLength(1));
        expect(find.byKey(const ValueKey('payee-name-field')), findsNothing);
        final expensePayee = find.descendant(
          of: find.byKey(const ValueKey('expense-field-payee')),
          matching: find.byType(EditableText),
        );
        expect(
          tester.widget<EditableText>(expensePayee).controller.text,
          longName,
        );
        await open();
        await tester.enterText(name, 'Cancelled new payee');
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(saved, hasLength(1));
        expect(tester.takeException(), isNull);
      });
    }
  }
}
