import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/frontend_review.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final existing in [false, true]) {
    testWidgets(
      'optional Class and ${existing ? 'saved' : 'blank'} Location on invoice',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(720, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        Map<String, Object?>? saved;
        await tester.pumpWidget(
          MaterialApp(
            theme: AccountingTheme.light(),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => FrontendFormDialog(
                      form: const DesignForm(
                        'Invoices',
                        transactionFields,
                        actionLabel: 'Save Draft',
                      ),
                      initial: {
                        'Counterparty': 'Client A',
                        'Date': '27-09-2026',
                        'Class': 'Production',
                        if (existing) 'Location': 'Branch A',
                      },
                      onCommit: (values) async {
                        saved = values;
                      },
                    ),
                  ),
                  child: const Text('Open Invoice'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open Invoice'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('design-field-Class')),
          findsOneWidget,
        );
        final location = find.byKey(const ValueKey('design-field-Location'));
        expect(location, existing ? findsOneWidget : findsNothing);
        if (existing) {
          expect(
            tester.widget<TextFormField>(location).controller!.text,
            'Branch A',
          );
          await tester.ensureVisible(location);
          await tester.enterText(location, '');
          await tester.pumpAndSettle();
          expect(
            location,
            findsOneWidget,
            reason: 'Clearing an existing tag must not make the field disappear mid-edit',
          );
          await tester.enterText(location, 'Branch A');
        }
        await tester.ensureVisible(find.byKey(const ValueKey('design-review')));
        await tester.tap(find.byKey(const ValueKey('design-review')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save Draft'));
        await tester.pumpAndSettle();
        expect(saved, isNotNull);
        expect(saved!['Class'], 'Production');
        expect(saved!['Location'], existing ? 'Branch A' : isNull);
        expect(find.byType(FrontendFormDialog), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
