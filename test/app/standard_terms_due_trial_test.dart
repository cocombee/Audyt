import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/frontend_review.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/purchases/domain/purchase_bill_draft.dart';
import 'package:audyt/features/purchases/presentation/bill_form.dart';
import 'package:audyt/features/sales/domain/invoice.dart';
import 'package:audyt/features/sales/invoice_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/accounting/data/bill_draft_persistence_test.dart'
    show setupBill, billFixture;
import '../support/fixed_popout_host.dart';
import '../support/sales_report_fixture.dart';
import 'journal_workspace_integration_test.dart'
    show captureUi, loadJournalLayoutFonts;

void main() {
  for (final netDays in [15, 90]) {
    for (final width in netDays == 15 ? [720.0, 1224.0] : [1224.0]) {
      for (final bill in [false, true]) {
        testWidgets(
          '${bill ? 'Bill' : 'Invoice'} Net $netDays ignores hidden due date and recalculates after issue-date edit at $width',
          (tester) async {
            tester.view.physicalSize = Size(width, 1500);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            installFixedPopoutHost(tester);
            await loadJournalLayoutFonts();
            final fixture = await salesReportFixture(seedInvoices: false);
            final w = fixture.workspace;
            addTearDown(w.dispose);
            final (vendor, purchaseAccount) = await setupBill(w);
            final oldBill = billFixture(
              w,
              vendor,
              purchaseAccount.account.id,
              attachments: const [],
            );
            final invoiceId = EntityId.random();
            final initial = <String, Object?>{
              if (bill) ...billFormValues(oldBill),
              if (bill)
                '_lines': [
                  for (final raw in billFormValues(oldBill)['_lines'] as List)
                    {
                      ...Map<String, String>.from(raw as Map),
                      'Tax Rate (%)': '0',
                    },
                ],
              if (!bill) ...{
                'Counterparty': fixture.customer.id.value,
                'Document Number': 'PROPOSAL-NET-$netDays',
                'Currency': 'MYR',
                '_lines': [
                  {
                    '_lineId': EntityId.random().value,
                    'Description': 'Fictional service',
                    'Quantity': '1',
                    'Rate': '100',
                    'Discount': '0',
                    'Tax Rate (%)': '0',
                    'Account': fixture.income.value,
                  },
                ],
              },
              'Date': '31-10-2026',
              'Due Date': '01-11-2026',
              'Payment Terms': 'Net 30',
              'Tax Mode': 'Exclusive',
            };
            final form = bill
                ? billForm(
                    {vendor.id.value: vendor.name},
                    {
                      purchaseAccount.account.id.value:
                          purchaseAccount.account.name,
                    },
                  )
                : invoiceForm(
                    {fixture.customer.id.value: fixture.customer.displayName},
                    {fixture.income.value: 'Fictional Sales'},
                  );
            Map<String, Object?>? reviewed;
            Invoice? invoice;
            PurchaseBillDraft? purchase;
            await tester.pumpWidget(
              RepaintBoundary(
                key: const ValueKey('workspace-capture'),
                child: MaterialApp(
                  theme: AccountingTheme.light(),
                  home: Scaffold(
                    body: FrontendFormDialog(
                      form: form,
                      initial: initial,
                      onCommit: (_) async {},
                      reviewInformationRowsBuilder: (values) {
                        reviewed = Map.of(values);
                        if (bill) {
                          purchase = billFromForm(
                            values,
                            metadata: oldBill.metadata,
                            vendor: vendor,
                            purchaseAccountIds: {
                              purchaseAccount.account.id.value,
                            },
                          );
                        } else {
                          invoice = invoiceFromForm(
                            values,
                            id: invoiceId,
                            customer: fixture.customer,
                            incomeAccountIds: {fixture.income.value},
                          );
                        }
                        return [
                          (
                            'Calculated due date',
                            (bill ? purchase!.bill.dueDate : invoice!.dueDate)
                                .toIso8601String(),
                          ),
                        ];
                      },
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final terms = find.byKey(
              const ValueKey('design-field-Payment Terms'),
            );
            await tester.ensureVisible(terms);
            await tester.tap(terms);
            await tester.pumpAndSettle();
            await tester.ensureVisible(find.text('Net $netDays').last);
            if (netDays == 15) {
              await captureUi(
                tester,
                'Net 15 ${bill ? 'Bill' : 'Invoice'} Menu ${width.toInt()}',
              );
            }
            await tester.tap(find.text('Net $netDays').last);
            await tester.pumpAndSettle();
            expect(
              find.byKey(const ValueKey('design-field-Due Date')),
              findsNothing,
            );
            Future<void> review() async {
              final action = find.byKey(const ValueKey('design-review'));
              await tester.ensureVisible(action);
              await tester.tap(action);
              await tester.pumpAndSettle();
              expect(find.textContaining('Could not review:'), findsNothing);
              expect(reviewed, isNotNull);
              expect(reviewed!['Due Date'], '');
              expect(reviewed!['Payment Terms'], 'Net $netDays');
              expect(tester.takeException(), isNull);
            }

            await review();
            if (netDays == 15) {
              await captureUi(
                tester,
                'Net 15 ${bill ? 'Bill' : 'Invoice'} Review ${width.toInt()}',
              );
            }
            expect(
              bill ? purchase!.bill.dueDate : invoice!.dueDate,
              netDays == 15
                  ? DateTime.utc(2026, 11, 15)
                  : DateTime.utc(2027, 1, 29),
            );
            await tester.tap(find.byKey(const ValueKey('design-back')));
            await tester.pumpAndSettle();
            final date = find.byKey(const ValueKey('design-field-Date'));
            await tester.ensureVisible(date);
            await tester.enterText(date, '01-11-2026');
            await tester.pumpAndSettle();
            await review();
            final expected = netDays == 15
                ? DateTime.utc(2026, 11, 16)
                : DateTime.utc(2027, 1, 30);
            if (bill) {
              w.saveBillDraft(purchase!, expectedRevision: 0);
              final saved = w.database.readBillDraft(
                w.identity.businessId,
                purchase!.id,
              )!;
              expect(saved.bill.dueDate, expected);
              expect(saved.bill.terms.days, netDays);
            } else {
              w.saveInvoiceDraft(
                invoice!,
                expectedRevision: 0,
                savedAt: DateTime.utc(2026, 11, 1),
              );
              final saved = w.invoiceDrafts().single.invoice;
              expect(saved.dueDate, expected);
              expect(saved.terms.days, netDays);
            }
          },
        );
      }
    }
  }
}
