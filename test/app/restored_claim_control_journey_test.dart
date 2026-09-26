import 'dart:io';

import 'package:audyt/app/app.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/purchases/domain/claim.dart';
import 'package:audyt/features/purchases/domain/claim_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'journal_workspace_integration_test.dart' show captureUi;
import 'restored_page_routes_test.dart' show tables;

void main() {
  for (final width in [720.0, 1224.0]) {
    testWidgets('restored claim Void binds the reviewed snapshot at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await (FontLoader(
        'Inter',
      )..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2'))).load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      final dir = Directory.systemTemp.createTempSync('claim-control-ui-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final originalPath = '${dir.path}/original.sqlite';
      final original = await AccountingWorkspace.open(originalPath);
      final draft = ClaimStore.demo().all.first;
      original.claims.saveDraft(draft);
      final archive = original.database.exportDataArchive(
        original.identity.businessId,
        DateTime.utc(2026, 9, 27),
      );
      final originalTables = tables(original);
      original.dispose();
      final originalBytes = File(originalPath).readAsBytesSync();
      final restoredPath = '${dir.path}/restored.sqlite';
      var w = await AccountingWorkspace.emptyRestore(restoredPath, archive);
      addTearDown(() => w.dispose());
      expect(tables(w), originalTables);
      Future<void> tap(Finder target) async {
        if (target.hitTestable().evaluate().isEmpty) {
          await tester.ensureVisible(target);
        }
        await tester.pumpAndSettle();
        await tester.tap(target);
        await tester.pumpAndSettle();
      }

      Future<void> openVoid() async {
        await tap(find.byKey(ValueKey('claim-more-${draft.id}')));
        await tap(find.byKey(ValueKey('claim-void-${draft.id}')));
        expect(
          find.byKey(ValueKey('claim-void-confirmation-${draft.id}')),
          findsOneWidget,
        );
      }

      Future<void> page() async {
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: DemoCompany(
              child: AudytApp(
                workspace: w,
                showInitialSetup: false,
                initialPath: '/claims',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await page();
      expect(find.text('Staff-Paid Expenses'), findsNothing);
      expect(find.text('Offline Workspace'), findsNothing);
      expect(find.textContaining('Local demo claims are included'), findsNothing);
      final baseline = tables(w);
      await openVoid();
      final confirmation = find.byKey(
        ValueKey('claim-void-confirmation-${draft.id}'),
      );
      expect(
        find.descendant(
          of: confirmation,
          matching: find.textContaining(draft.claimantName),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: confirmation,
          matching: find.textContaining(draft.vendorName),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: confirmation,
          matching: find.textContaining('12.50'),
        ),
        findsOneWidget,
      );
      await captureUi(tester, 'Claim Control Void Review ${width.toInt()}');
      await tap(find.bySemanticsLabel('Close').last);
      expect(tables(w), baseline);
      await openVoid();
      final current = w.claims.byId(draft.id)!;
      w.claims.saveDraft(
        Claim.fromJson({
          ...current.toJson(),
          'businessPurpose': 'Updated after review opened',
        }),
        expectedCurrent: current,
      );
      await tester.pumpAndSettle();
      final changedBaseline = tables(w);
      await tap(find.byKey(ValueKey('claim-confirm-void-${draft.id}')));
      expect(w.claims.byId(draft.id)!.status, ClaimStatus.draft);
      expect(tables(w), changedBaseline);
      expect(
        find.textContaining('Claim changed since it was opened'),
        findsWidgets,
      );
      await captureUi(tester, 'Claim Control Stale Void ${width.toInt()}');
      await openVoid();
      await tap(find.byKey(ValueKey('claim-confirm-void-${draft.id}')));
      expect(w.claims.byId(draft.id)!.status, ClaimStatus.voided);
      expect(
        w.claims.byId(draft.id)!.businessPurpose,
        'Updated after review opened',
      );
      expect(await w.journals(), isEmpty);
      final finalTables = tables(w);
      for (final name in changedBaseline.keys.where(
        (name) => name != 'claims',
      )) {
        expect(finalTables[name], changedBaseline[name], reason: name);
      }
      await captureUi(tester, 'Claim Control Voided ${width.toInt()}');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      w.dispose();
      w = await AccountingWorkspace.open(restoredPath);
      expect(tables(w), finalTables);
      expect(File(originalPath).readAsBytesSync(), originalBytes);
    });
  }
}
