import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/app.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/features/accounting/application/account_repository.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'journal_workspace_integration_test.dart'
    show captureUi, loadJournalLayoutFonts;
import 'restored_page_routes_test.dart' show tables;

void main() {
  for (final width in [720.0, 1162.0, 1224.0]) {
    for (final example in [
      ('6300', 'Property Equipment Maintenance', AccountType.expense),
      ('4000', 'Loan Documentation Services', AccountType.income),
    ]) {
      testWidgets(
        'Cash Flow keeps ${example.$3.name} activity after a name change at $width',
        (tester) async {
          await tester.binding.setSurfaceSize(Size(width, 809));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await loadJournalLayoutFonts();
          final workspace = await createDemoWorkspace();
          addTearDown(workspace.dispose);
          Future<List<(String, String)>> report() async {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpWidget(
              RepaintBoundary(
                key: const ValueKey('workspace-capture'),
                child: DemoCompany(
                  child: AudytApp(
                    workspace: workspace,
                    initialPath: '/reports',
                    showInitialSetup: false,
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            await tester.tap(find.text('Cash Flow').first);
            await tester.pumpAndSettle();
            return tester
                .widget<AccountingSummaryTableCard>(
                  find.byKey(const ValueKey('report-preview-table-Cash Flow')),
                )
                .rows
                .toList();
          }

          final beforeRows = await report();
          final before = tables(workspace);
          await captureUi(
            tester,
            'Cash Flow Type ${example.$3.name} Before ${width.toInt()}',
          );
          final stored = (await workspace.accounts()).singleWhere(
            (record) => record.account.code == example.$1,
          );
          final account = stored.account;
          expect(account.type, example.$3);
          await workspace.database.saveAccount(
            StoredAccount(
              account: Account.create(
                id: account.id,
                code: account.code,
                name: example.$2,
                type: account.type,
                status: account.status,
                isParent: account.isParent,
                isSystem: account.isSystem,
                parentId: account.parentId,
                profile: account.profile,
              ),
              metadata: stored.metadata.nextRevision(
                updatedAt: stored.metadata.updatedAt.add(
                  const Duration(seconds: 1),
                ),
              ),
            ),
          );
          final afterRows = await report();
          await captureUi(
            tester,
            'Cash Flow Type ${example.$3.name} Renamed ${width.toInt()}',
          );
          final after = tables(workspace);
          // Only the isolated account name/revision may change. The posted
          // journals, payment links, tax facts and every other table stay exact.
          for (final table in before.keys.where((name) => name != 'accounts')) {
            expect(after[table], before[table], reason: table);
          }
          expect(
            afterRows,
            beforeRows,
            reason:
                'Renaming ${account.name} to ${example.$2} cannot change the '
                'cash activity of unchanged ${example.$3.name} journals.',
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
