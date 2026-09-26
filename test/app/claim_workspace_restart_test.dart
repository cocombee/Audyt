import 'dart:io';

import 'package:audyt/features/accounting/domain/account.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audyt/app/app.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/purchases/domain/claim.dart';
import 'package:audyt/features/purchases/domain/claim_store.dart';

void main() {
  testWidgets(
    'production claim submission and approval survive restart with evidence',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1224, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final dir = Directory.systemTemp.createTempSync('claim-ui-restart-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/ledger.sqlite';
      var workspace = await AccountingWorkspace.open(path);
      await workspace.createAccount(
        code: '5000',
        name: 'Office Expense',
        type: AccountType.expense,
      );
      await workspace.createAccount(
        code: '2100',
        name: 'Claims Payable',
        type: AccountType.liability,
      );
      final claim = ClaimStore.demo().all.first;
      workspace.claims.saveDraft(claim);
      await tester.pumpWidget(
        AudytApp(workspace: workspace, initialPath: '/claims'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('claim-more-${claim.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('claim-submit-${claim.id}')));
      await tester.pumpAndSettle();
      expect(workspace.claims.byId(claim.id)!.status, ClaimStatus.submitted);
      await tester.pumpWidget(const SizedBox());
      workspace.dispose();
      workspace = await AccountingWorkspace.open(path);
      await tester.pumpWidget(
        AudytApp(workspace: workspace, initialPath: '/claims'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('claim-more-${claim.id}')));
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('claim-approve-${claim.id}')), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('claim-approve-${claim.id}')));
      await tester.pumpAndSettle();
      expect(workspace.claims.byId(claim.id)!.status, ClaimStatus.submitted);
      expect(await workspace.journals(), isEmpty);
      await tester.tap(find.text('Expense Account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('5000 · Office Expense').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Claims Payable Account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2100 · Claims Payable').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(workspace.claims.byId(claim.id)!.status, ClaimStatus.approved);
      final journalId = (await workspace.journals()).single.entry.id;
      await tester.pumpWidget(const SizedBox());
      workspace.dispose();
      workspace = await AccountingWorkspace.open(path);
      addTearDown(workspace.dispose);
      final restored = workspace.claims.byId(claim.id)!;
      expect(restored.status, ClaimStatus.approved);
      expect((await workspace.journals()).single.entry.id, journalId);
      expect(
        restored.attachments.single.originalBytes,
        claim.attachments.single.originalBytes,
      );
      expect(
        restored.attachments.single.originalSha256,
        claim.attachments.single.originalSha256,
      );
      await tester.pumpWidget(
        AudytApp(workspace: workspace, initialPath: '/claims'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('claim-more-${claim.id}')));
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('claim-pay-${claim.id}')), findsOneWidget);
      expect(find.byKey(ValueKey('claim-submit-${claim.id}')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
