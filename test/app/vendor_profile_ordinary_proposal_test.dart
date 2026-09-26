import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/features/accounting/presentation/attachment_preview_dialog.dart';
import 'package:audyt/app/frontend_review.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/purchases/presentation/vendor_profile_proposal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'claim_receipts_proposal_test.dart' show prepare;
import 'journal_workspace_integration_test.dart' show captureUi;

Finder field(String label) => find.byKey(ValueKey('design-field-$label'));

void main() {
  for (final width in [720.0, 1224.0]) {
    testWidgets(
      'Vendor proposal reflow, focus and existing evidence owner at $width',
      (tester) async {
        await prepare(tester, width);
        final workspace = await AccountingWorkspace.open(':memory:');
        addTearDown(workspace.dispose);
        final before = workspace.database.exportDataArchive(
          workspace.identity.businessId,
          DateTime.utc(2026),
        );
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: MaterialApp(
              theme: AccountingTheme.light(),
              debugShowCheckedModeBanner: false,
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    child: const Text('Open Proposal'),
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => FrontendFormDialog(
                        form: vendorProfileProposal(
                          expenseAccounts: const {
                            'expense-office': '5000 · Office And General Administrative Expenses',
                          },
                        ),
                        initial: const {
                          'Country': 'Malaysia',
                          'Vendor Type': 'Supplier',
                          'Party Type': 'Business',
                          'Supplier Terms': 'Net 30',
                          'Name': 'Sample Supplier',
                          'Company Name': 'Sample Supplier Sdn Bhd',
                          '_files': ['supplier-support.pdf'],
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open Proposal'));
        await tester.pumpAndSettle();
        await captureUi(tester, 'Vendor Profile Default ${width.toInt()}');
        final state = tester.state<EditableTextState>(
          find.descendant(
            of: field('Name'),
            matching: find.byType(EditableText),
          ),
        );
        final originalWidth = tester.getSize(field('Name')).width;
        await tester.enterText(
          field('Name'),
          'Regional Supplier For Manufacturing And Maintenance Services',
        );
        await tester.pumpAndSettle();
        final afterState = tester.state<EditableTextState>(
          find.descendant(
            of: field('Name'),
            matching: find.byType(EditableText),
          ),
        );
        expect(identical(state, afterState), isTrue);
        expect(afterState.widget.focusNode.hasFocus, isTrue);
        expect(
          afterState.widget.controller.selection.baseOffset,
          afterState.widget.controller.text.length,
        );
        expect(tester.getSize(field('Name')).width, greaterThan(originalWidth));
        final names = [
          tester.getRect(field('Name')),
          tester.getRect(field('Company Name')),
        ];
        expect(names[1].width, greaterThanOrEqualTo(originalWidth - 0.1));
        await captureUi(tester, 'Vendor Profile Long Name ${width.toInt()}');
        Future<void> show(String label) async {
          await tester.ensureVisible(field(label));
          await tester.pumpAndSettle();
        }

        await show('Supplier Category');
        await tester.tap(field('Supplier Category'));
        await tester.pumpAndSettle();
        for (final label in [
          'Domestic Business',
          'Domestic Individual',
          'Foreign Business',
          'Foreign Individual',
        ]) {
          expect(find.widgetWithText(MenuItemButton, label), findsOneWidget);
        }
        await captureUi(
          tester,
          'Vendor Profile Category Menu ${width.toInt()}',
        );
        await tester.tap(
          find.widgetWithText(MenuItemButton, 'Domestic Business'),
        );
        await tester.pumpAndSettle();
        await show('Default Expense Category');
        await tester.tap(field('Default Expense Category'));
        await tester.pumpAndSettle();
        expect(
          find.text('5000 · Office And General Administrative Expenses'),
          findsOneWidget,
        );
        await tester.tap(
          find.text('5000 · Office And General Administrative Expenses'),
        );
        await tester.pumpAndSettle();
        await show('Opening Balance Date');
        await captureUi(tester, 'Vendor Profile Accounting ${width.toInt()}');
        await tester.ensureVisible(find.byType(AccountingAttachmentDropzone));
        await tester.pumpAndSettle();
        expect(find.byType(AccountingAttachmentList), findsOneWidget);
        expect(
          tester.getRect(find.text('supplier-support.pdf')).top,
          greaterThan(
            tester.getRect(find.byType(AccountingAttachmentDropzone)).bottom,
          ),
        );
        await captureUi(tester, 'Vendor Profile Evidence ${width.toInt()}');
        final retainedName = state.textEditingValue.text;
        await tester.tap(find.byKey(const ValueKey('design-close')));
        await tester.pumpAndSettle();
        expect(find.text('Discard Unsaved Changes?'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('design-keep-editing')));
        await tester.pumpAndSettle();
        expect(state.textEditingValue.text, retainedName);
        await tester.tap(find.byKey(const ValueKey('design-close')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('design-discard-changes')));
        await tester.pumpAndSettle();
        expect(find.byType(FrontendFormDialog), findsNothing);
        expect(
          workspace.database.exportDataArchive(
            workspace.identity.businessId,
            DateTime.utc(2026),
          ),
          before,
        );
        expect(await workspace.journals(), isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
