import 'package:audyt/app/frontend_review.dart';
import 'package:audyt/app/live_settings_catalog.dart';
import 'package:audyt/app/field_row_trial.dart';
import 'package:audyt/app/accounting_description_field.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/accounting/presentation/record_expense_page.dart';
import 'package:audyt/features/purchases/presentation/claims_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/accounting_text_input.dart';

void main() {
  for (final width in [720.0, 1224.0]) {
    for (final spec in [
      ('Sales Preferences', 'Customer Message'),
      ('Numbering & Document Appearance', 'Footer'),
    ]) {
      testWidgets('${spec.$2} keeps the custom tall narrative frame at $width', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(Size(width, 1800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final form = liveSettingsForms({})
            .singleWhere((f) => f.title == spec.$1);
        await tester.pumpWidget(
          MaterialApp(
            theme: AccountingTheme.light(),
            home: Scaffold(
              body: SingleChildScrollView(
                child: FrontendFormDialog(
                  embedded: true,
                  fieldLayoutOwner: AccountingFieldLayoutOwner.sharedPopup,
                  contentWidth: width - 80,
                  form: form,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final target = find.byKey(ValueKey('design-field-${spec.$2}'));
        await tester.ensureVisible(target);
        final editor = tester.widget<AccountingDescriptionField>(target);
        expect(editor.role, AccountingDescriptionRole.narrative);
        expect(
          editor.fixedLines,
          AccountingDescriptionTokens.defaultFixedLines,
        );
        final frame = tester.getSize(target);
        final content =
            '1. ${List.filled(40, 'long paragraph and bullet text').join(' ')}\n2. Second paragraph';
        await enterAccountingText(tester, target, content);
        await tester.pumpAndSettle();
        expect(tester.getSize(target), frame);
        expect(editor.controller!.text, content);
        expect(frame.width, closeTo(width - 80, .1));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('Expense field roles remain scoped at $width', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await (FontLoader(
        'Inter',
      )..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2'))).load();
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: const Scaffold(body: RecordExpensePage()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('expense-advanced-details')),
      );
      await tester.tap(find.byKey(const ValueKey('expense-advanced-details')));
      await tester.pumpAndSettle();
      for (final name in ['amount', 'date', 'payee', 'customer']) {
        final field = find.byKey(ValueKey('expense-field-$name'));
        final text = field.evaluate().single.widget is TextField
            ? field
            : find.descendant(of: field, matching: find.byType(TextField));
        expect(tester.widget<TextField>(text).maxLines, 1, reason: name);
        expect(tester.widget<TextField>(text).expands, isFalse, reason: name);
        expect(
          find.descendant(
            of: field,
            matching: find.byType(AccountingDescriptionField),
          ),
          findsNothing,
        );
      }
      final memo = find.byKey(const ValueKey('expense-field-notes'));
      expect(tester.widget(memo), isA<AccountingDescriptionField>());
      final frame = tester.getSize(memo);
      await tester.ensureVisible(memo);
      await enterAccountingText(
        tester,
        memo,
        '1. ${List.filled(30, 'memo paragraph text').join(' ')}',
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(memo), frame);
      expect(
        tester.widget<AccountingDescriptionField>(memo).fixedHeight,
        isNotNull,
      );
      // Ordinary customer references remain one line even with list-like text.
      final customer = find.byKey(const ValueKey('expense-field-customer'));
      final height = tester.getSize(customer).height;
      await tester.ensureVisible(customer);
      await tester.enterText(
        customer,
        List.filled(20, '1. customer').join(' '),
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(customer).height, height);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Claim field roles remain scoped at $width', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(
            body: ClaimEditorDialog(
              id: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-000000000099'),
              onSaveDraft: (_) {},
              onSubmit: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final name in ['amount', 'date', 'claimant', 'payee']) {
        final field = find.byKey(ValueKey('claim-$name'));
        final text = field.evaluate().single.widget is TextField
            ? field
            : find.descendant(of: field, matching: find.byType(TextField));
        expect(tester.widget<TextField>(text).maxLines, 1, reason: name);
        expect(tester.widget<TextField>(text).expands, isFalse, reason: name);
      }
      final purpose = find.byKey(const ValueKey('claim-purpose'));
      expect(tester.widget(purpose), isA<AccountingDescriptionField>());
      expect(tester.widget<AccountingDescriptionField>(purpose).fixedLines, 3);
      final frame = tester.getSize(purpose);
      await tester.ensureVisible(purpose);
      await enterAccountingText(
        tester,
        purpose,
        'a. ${List.filled(30, 'claim narrative text').join(' ')}',
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(purpose), frame);
      expect(tester.takeException(), isNull);
    });
  }
}
