import 'dart:io';

import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/accounting/presentation/tax_rates_page.dart';
import 'package:audyt/features/accounting/presentation/tax_overview_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/accounting/data/tax_agency_wiring_test.dart'
    show agency, code, post;
import '../support/accounting_test_finders.dart';
import '../support/accounting_text_input.dart';
import '../support/sales_report_fixture.dart';
import 'journal_workspace_integration_test.dart' show captureUi;

Finder field(String name) => find.byKey(ValueKey('design-field-$name'));
Future<void> tap(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  await t.pumpAndSettle();
}

Future<void> capture(WidgetTester t, String name) async {
  final previous = debugDisableShadows;
  debugDisableShadows = false;
  try {
    for (final r in t.allRenderObjects) {
      r.markNeedsPaint();
    }
    await t.pump();
    await captureUi(t, name);
  } finally {
    debugDisableShadows = previous;
  }
}

Future<void> prepare(WidgetTester t, double width) async {
  t.view.physicalSize = Size(width, 1400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await (FontLoader(
    'Inter',
  )..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2'))).load();
  await (FontLoader(
    'MaterialIcons',
  )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
}

Future<void> host(
  WidgetTester t,
  AccountingWorkspace w, {
  bool proposal = true,
}) async {
  await t.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('workspace-capture'),
      child: MaterialApp(
        theme: AccountingTheme.light(),
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: TaxRatesPage(
            workspace: w,
            purchaseCostProposal: proposal,
            taxAgencyProposal: proposal,
          ),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  for (final width in [720.0, 1224.0]) {
    testWidgets(
      'real agency setup and linked code Save/Edit/Cancel/Restart preserve frozen registration at $width',
      (t) async {
        await prepare(t, width);
        final dir = Directory.systemTemp.createTempSync('audyt-agency-ui-');
        addTearDown(() => dir.deleteSync(recursive: true));
        final path = '${dir.path}/books.sqlite';
        var w = await AccountingWorkspace.open(path);
        addTearDown(() => w.dispose());
        await host(t, w);
        await tap(t, find.byKey(const ValueKey('tax-agencies-open')));
        await tap(t, find.byKey(const ValueKey('tax-agency-add')));
        await t.enterText(field('Name'), 'RMCD');
        await t.enterText(
          field('Registration Number'),
          'Fictional Registration A',
        );
        await capture(t, 'Tax Agency Editor ${width.toInt()}');
        await tap(t, find.byKey(const ValueKey('design-review')));
        await capture(t, 'Tax Agency Review ${width.toInt()}');
        await tap(t, find.byKey(const ValueKey('design-review')));
        expect(w.taxAgencies.single.name, 'RMCD');
        final first = w.taxAgencies.single;
        await capture(t, 'Tax Agency List ${width.toInt()}');
        await tap(t, accountingCloseIcon());
        await tap(t, find.byKey(const ValueKey('tax-rate-add')));
        await t.enterText(field('Name'), 'Service Tax');
        await t.enterText(field('Rate (%)'), '8');
        await t.enterText(field('Effective From'), '01-01-2026');
        await tap(t, field('Applies To'));
        await tap(t, find.text('Purchases').last);
        await tap(t, field('Tax Agency'));
        await tap(t, find.text('RMCD').last);
        await capture(t, 'Tax Code Agency Selection ${width.toInt()}');
        await tap(t, find.byKey(const ValueKey('design-review')));
        await tap(t, find.byKey(const ValueKey('design-review')));
        final original = w.taxRates.single;
        expect(original.toJson()['version'], 3);
        expect(original.agencySnapshot!.toJson(), first.toJson());
        await tap(t, find.byKey(const ValueKey('tax-agencies-open')));
        await tap(t, find.byKey(ValueKey('tax-agency-edit-${first.id.value}')));
        await t.enterText(field('Name'), 'RMCD Service Tax');
        await t.enterText(
          field('Registration Number'),
          'Fictional Registration B',
        );
        await tap(t, find.byKey(const ValueKey('design-close')));
        await tap(t, find.byKey(const ValueKey('design-discard-changes')));
        expect(w.taxAgencies.single.toJson(), first.toJson());
        await tap(t, find.byKey(ValueKey('tax-agency-edit-${first.id.value}')));
        await t.enterText(field('Name'), 'RMCD Service Tax');
        await t.enterText(
          field('Registration Number'),
          'Fictional Registration B',
        );
        await tap(t, find.byKey(const ValueKey('design-review')));
        await tap(t, find.byKey(const ValueKey('design-review')));
        expect(w.taxAgencies.single.revision, 2);
        expect(w.taxRates.single.agencySnapshot!.toJson(), first.toJson());
        await tap(t, accountingCloseIcon());
        await tap(
          t,
          find.byKey(ValueKey('tax-rate-edit-${original.id.value}')),
        );
        expect(find.text('RMCD · Saved Revision 1'), findsOneWidget);
        await capture(t, 'Tax Code Retained Agency ${width.toInt()}');
        await tap(t, find.byKey(const ValueKey('design-review')));
        await tap(t, find.byKey(const ValueKey('design-review')));
        expect(w.taxRates.single.agencySnapshot!.toJson(), first.toJson());
        await tap(
          t,
          find.byKey(ValueKey('tax-rate-edit-${original.id.value}')),
        );
        await tap(t, field('Tax Agency'));
        await tap(t, find.text('RMCD Service Tax').last);
        await tap(t, find.byKey(const ValueKey('design-review')));
        await tap(t, find.byKey(const ValueKey('design-review')));
        final linked = w.taxRates.single;
        expect(linked.agencySnapshot!.revision, 2);
        expect(
          w.database
              .taxRateHistory(w.identity.businessId, original.id)
              .first
              .toJson(),
          original.toJson(),
        );
        final before = linked.toJson();
        await t.pumpWidget(const SizedBox.shrink());
        w.dispose();
        w = await AccountingWorkspace.open(path);
        expect(w.taxRates.single.toJson(), before);
        expect(w.taxAgencies.single.revision, 2);
        await host(t, w, proposal: false);
        expect(find.byKey(const ValueKey('tax-agencies-open')), findsNothing);
        await tap(t, find.byKey(ValueKey('tax-rate-edit-${linked.id.value}')));
        expect(field('Tax Agency'), findsNothing);
        await capture(t, 'Current Tax Rate Fields ${width.toInt()}');
        await tap(t, find.byKey(const ValueKey('design-close')));
        expect(w.taxRates.single.toJson(), before);
        expect(t.takeException(), isNull);
      },
    );
    testWidgets(
      'actual Tax Overview groups and source display frozen agency facts read-only at $width',
      (t) async {
        await prepare(t, width);
        final f = await salesReportFixture(seedInvoices: false);
        final w = f.workspace;
        addTearDown(w.dispose);
        final registration = w.saveTaxAgency(agency());
        final rate = w.saveTaxRate(code(registration, account: f.tax));
        post(f, rate, 'AGENCY-UI-1');
        final before = w.database.exportDataArchive(
          w.identity.businessId,
          DateTime.utc(2026, 10),
        );
        await t.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: MaterialApp(
              theme: AccountingTheme.light(),
              debugShowCheckedModeBanner: false,
              home: Scaffold(
                body: TaxOverviewPage(workspace: w, agencyProposal: true),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        await t.enterText(
          find.byKey(const ValueKey('tax-overview-from')),
          '01-09-2026',
        );
        await t.enterText(
          find.byKey(const ValueKey('tax-overview-through')),
          '30-09-2026',
        );
        await tap(t, find.byKey(const ValueKey('tax-overview-run')));
        expect(find.text('RMCD · Revision 1'), findsOneWidget);
        await capture(t, 'Tax Agency Activity ${width.toInt()}');
        final report = await w.taxActivity(
          from: DateTime.utc(2026, 9),
          through: DateTime.utc(2026, 9, 30),
        );
        final source = report.rows.single;
        await tap(
          t,
          find.byKey(
            ValueKey(
              'tax-source-view-${source.journalId.value}-${source.lineId}',
            ),
          ),
        );
        expect(find.text('Fictional Registration A'), findsOneWidget);
        expect(find.text(registration.id.value), findsOneWidget);
        expect(find.text('Save'), findsNothing);
        await capture(t, 'Tax Source Agency Details ${width.toInt()}');
        await tap(t, accountingCloseIcon());
        expect(
          w.database.exportDataArchive(
            w.identity.businessId,
            DateTime.utc(2026, 10),
          ),
          before,
        );
        await t.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: MaterialApp(
              theme: AccountingTheme.light(),
              debugShowCheckedModeBanner: false,
              home: Scaffold(
                body: TaxOverviewPage(
                  workspace: w,
                  agencyProposal: false,
                  taxPaymentsProposal: false,
                ),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(find.text('RMCD · Revision 1'), findsNothing);
        await capture(t, 'Current Tax Overview ${width.toInt()}');
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'stale agency review and invalid country preserve typed fields and reject writes',
    (t) async {
      await prepare(t, 720);
      final w = await AccountingWorkspace.open(':memory:');
      addTearDown(w.dispose);
      await host(t, w);
      await tap(t, find.byKey(const ValueKey('tax-agencies-open')));
      await tap(t, find.byKey(const ValueKey('tax-agency-add')));
      await t.enterText(field('Name'), 'RMCD');
      await t.enterText(field('Country Code'), 'MYS');
      await tap(t, find.byKey(const ValueKey('design-review')));
      await tap(t, find.byKey(const ValueKey('design-review')));
      expect(
        find.textContaining('valid tax agency and country code'),
        findsOneWidget,
      );
      expect(w.taxAgencies, isEmpty);
      await tap(t, find.byKey(const ValueKey('design-back')));
      await t.enterText(field('Country Code'), 'MY');
      await tap(t, find.byKey(const ValueKey('design-review')));
      await tap(t, find.byKey(const ValueKey('design-review')));
      final first = w.taxAgencies.single;
      await tap(t, find.byKey(ValueKey('tax-agency-edit-${first.id.value}')));
      await enterAccountingText(t, field('Notes'), 'Keep this draft note');
      w.saveTaxAgency(
        agency(
          id: first.id,
          revision: first.revision,
          registration: 'Fictional Registration B',
        ),
      );
      await t.pumpAndSettle();
      await tap(t, find.byKey(const ValueKey('design-review')));
      await tap(t, find.byKey(const ValueKey('design-review')));
      expect(find.textContaining('Tax agency changed'), findsOneWidget);
      expect(w.taxAgencies.single.notes, isEmpty);
      expect(find.text('Keep this draft note'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
}
