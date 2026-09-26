// Unwired proposal using the shared owners and disposable accounting data.
import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/features/accounting/domain/transaction_removal.dart';
import 'package:audyt/features/accounting/presentation/transaction_removal_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/accounting/data/transaction_removal_test.dart' show fixture;
import 'journal_workspace_integration_test.dart' show captureUi;

void main() {
  for (final width in [720.0, 1224.0]) {
    testWidgets('Proposed shared removal controls at $width', (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await (FontLoader(
        'Inter',
      )..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2'))).load();
      final f = await fixture(TransactionRecordKind.claim, pending: true);
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('workspace-capture'),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AccountingTheme.light(),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: AccountingButton.primary(
                    context,
                    key: const ValueKey('open-proposed-removal'),
                    onPressed: () => confirmTransactionRemoval(
                      context,
                      f.w,
                      f.w.reviewTransactionRemoval(
                        TransactionRecordKind.claim,
                        f.id,
                      ),
                    ),
                    child: const Text('Open Proposed Removal'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open Proposed Removal'));
      await tester.pumpAndSettle();
      await captureUi(
        tester,
        'Transaction Removal Proposed Confirmation ${width.toInt()}',
      );
      await tester.tap(
        find.byKey(const ValueKey('transaction-confirm-removal')),
      );
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('workspace-capture'),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AccountingTheme.light(),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: AccountingButton.primary(
                    context,
                    key: const ValueKey('open-proposed-removed-list'),
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => RemovedTransactionsDialog(
                        workspace: f.w,
                        kind: TransactionRecordKind.claim,
                        onView: (_) async {},
                      ),
                    ),
                    child: const Text('Open Proposed Removed List'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open Proposed Removed List'));
      await tester.pumpAndSettle();
      await captureUi(
        tester,
        'Transaction Removal Proposed List ${width.toInt()}',
      );
      expect(find.text('Removed Claims'), findsOneWidget);
      expect(find.byKey(ValueKey('removed-restore-${f.id}')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
