import 'dart:io';

import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/domain/company_tax_rate.dart';
import 'package:audyt/features/accounting/presentation/record_expense_page.dart';
import 'package:audyt/features/accounting/presentation/tax_rates_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'journal_workspace_integration_test.dart' show captureUi;

Finder keyed(String key) => find.byKey(ValueKey(key));
Future<void> tap(WidgetTester t, Finder target) async {
  await t.ensureVisible(target);
  await t.pumpAndSettle();
  await t.tap(target);
  await t.pumpAndSettle();
}

Future<void> capture(WidgetTester t, String name) async {
  final shadows = debugDisableShadows;
  try {
    debugDisableShadows = false;
    for (final r in t.allRenderObjects) {
      r.markNeedsPaint();
    }
    await t.pump();
    await captureUi(t, name);
  } finally {
    debugDisableShadows = shadows;
  }
}

Future<void> prepare(WidgetTester t, double width) async {
  t.view.physicalSize = Size(width, 1100);
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

Future<void> host(WidgetTester t, AccountingWorkspace w) async {
  await t.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('workspace-capture'),
      child: MaterialApp(
        theme: AccountingTheme.light(),
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: TaxRatesPage(workspace: w, purchaseCostProposal: true),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  for (final width in [720.0, 1224.0]) {
    testWidgets(
      'legacy purchase master edit retains mapped account and original history at $width',
      (t) async {
        await prepare(t, width);
        final w = await AccountingWorkspace.open(':memory:');
        addTearDown(w.dispose);
        await w.createAccount(
          code: '2200',
          name: 'Saved Tax Account',
          type: AccountType.liability,
        );
        final account = (await w.accounts()).single.account.id;
        final original = w.saveTaxRate(
          CompanyTaxRate(
            id: EntityId.random(),
            name: 'SST',
            percent: '5',
            effectiveFrom: DateTime.utc(2026),
            application: TaxApplication.purchases,
            accountId: account,
          ),
        );
        await host(t, w);
        await tap(t, keyed('tax-rate-edit-${original.id.value}'));
        expect(keyed('design-field-Tax Account'), findsNothing);
        expect(
          find.textContaining('Saved account mapping is retained'),
          findsOneWidget,
        );
        await t.enterText(keyed('design-field-Rate (%)'), '6');
        await capture(t, 'Legacy Purchase Tax Mapping ${width.toInt()}');
        await tap(t, keyed('design-review'));
        await tap(t, keyed('design-review'));
        expect(w.taxRates.single.accountId, account);
        expect(w.taxRates.single.toJson()['version'], 1);
        expect(w.taxRates.single.revision, 2);
        expect(
          w.database
              .taxRateHistory(w.identity.businessId, original.id)
              .first
              .toJson(),
          original.toJson(),
        );
        expect(t.takeException(), isNull);
      },
    );
    testWidgets(
      'actual Tax Codes purchase cost selection/save/cancel/reopen reaches Expense at $width',
      (t) async {
        await prepare(t, width);
        final dir = Directory.systemTemp.createTempSync('tax-cost-proposal-');
        addTearDown(() => dir.deleteSync(recursive: true));
        final path = '${dir.path}/books.sqlite';
        var w = await AccountingWorkspace.open(path);
        addTearDown(() => w.dispose());
        await host(t, w);
        await tap(t, keyed('tax-rate-add'));
        await t.enterText(keyed('design-field-Name'), 'Service Tax');
        await t.enterText(keyed('design-field-Rate (%)'), '8');
        await t.enterText(keyed('design-field-Effective From'), '01-01-2026');
        await tap(t, keyed('design-field-Applies To'));
        await tap(t, find.text('Purchases').last);
        expect(keyed('design-field-Tax Account'), findsNothing);
        await capture(t, 'Purchase Tax Cost Editor ${width.toInt()}');
        await tap(t, keyed('design-review'));
        expect(find.textContaining('No separate tax account'), findsOneWidget);
        await capture(t, 'Purchase Tax Cost Review ${width.toInt()}');
        await tap(t, keyed('design-review'));
        expect(w.taxRates.single.accountId, isNull);
        expect(w.taxRates.single.toJson()['version'], 2);
        final saved = w.taxRates.single;
        await tap(t, keyed('tax-rate-edit-${saved.id.value}'));
        await t.enterText(keyed('design-field-Rate (%)'), '6');
        await tap(t, keyed('design-close'));
        expect(find.text('Discard Unsaved Changes?'), findsOneWidget);
        await tap(t, keyed('design-discard-changes'));
        expect(w.taxRates.single.toJson(), saved.toJson());
        await tap(t, keyed('tax-rate-edit-${saved.id.value}'));
        expect(keyed('design-field-Tax Account'), findsNothing);
        await t.enterText(keyed('design-field-Rate (%)'), '6');
        await tap(t, keyed('design-review'));
        await tap(t, keyed('design-review'));
        expect(w.taxRates.single.accountId, isNull);
        expect(w.taxRates.single.revision, 2);
        final facts = w.taxRates.single.toJson();
        await t.pumpWidget(const SizedBox.shrink());
        w.dispose();
        w = await AccountingWorkspace.open(path);
        expect(w.taxRates.single.toJson(), facts);
        await t.pumpWidget(
          MaterialApp(
            theme: AccountingTheme.light(),
            home: Scaffold(body: RecordExpensePage(settingsWorkspace: w)),
          ),
        );
        await t.pumpAndSettle();
        final picker = t
            .widgetList<AccountingSelector<String>>(
              find.byWidgetPredicate(
                (v) =>
                    v is AccountingSelector<String> &&
                    (v.triggerKey as ValueKey?)?.value.toString().endsWith(
                          '-tax',
                        ) ==
                        true,
              ),
            )
            .single;
        expect(
          picker.options.any(
            (o) =>
                o.value == w.taxRates.single.choice &&
                o.label == 'Service Tax · 6%',
          ),
          isTrue,
        );
        expect(t.takeException(), isNull);
      },
    );

    testWidgets(
      'purchase-to-sales basis change restores required account and preserves typed fields at $width',
      (t) async {
        await prepare(t, width);
        final w = await AccountingWorkspace.open(':memory:');
        addTearDown(w.dispose);
        await w.createAccount(
          code: '2200',
          name: 'Sales Tax Payable',
          type: AccountType.liability,
        );
        final account = (await w.accounts()).single.account;
        await host(t, w);
        await tap(t, keyed('tax-rate-add'));
        await t.enterText(keyed('design-field-Name'), 'SST');
        await t.enterText(keyed('design-field-Rate (%)'), '5');
        await tap(t, keyed('design-field-Applies To'));
        await tap(t, find.text('Purchases').last);
        expect(keyed('design-field-Tax Account'), findsNothing);
        await tap(t, keyed('design-field-Applies To'));
        await tap(t, find.text('Sales').last);
        expect(keyed('design-field-Tax Account'), findsOneWidget);
        await tap(t, keyed('design-review'));
        expect(
          find.text('Complete Tax Account before reviewing.'),
          findsOneWidget,
        );
        expect(w.taxRates, isEmpty);
        await tap(t, keyed('design-field-Tax Account'));
        await tap(t, find.text(account.displayName).last);
        await capture(t, 'Sales Tax Liability Editor ${width.toInt()}');
        await tap(t, keyed('design-field-Applies To'));
        await tap(t, find.text('Purchases').last);
        await tap(t, keyed('design-field-Applies To'));
        await tap(t, find.text('Sales & Purchases').last);
        await capture(t, 'Combined Tax Cost Editor ${width.toInt()}');
        await tap(t, keyed('design-review'));
        await tap(t, keyed('design-review'));
        expect(w.taxRates.single.application, TaxApplication.both);
        expect(w.taxRates.single.accountId, account.id);
        expect(w.taxRates.single.name, 'SST');
        expect(w.taxRates.single.percent, '5');
        expect(t.takeException(), isNull);
      },
    );
  }
}
