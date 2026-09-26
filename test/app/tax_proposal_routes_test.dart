import 'dart:io';

import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/app.dart';
import 'package:audyt/app/accounting_icons.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/app/frontend_review.dart';
import 'package:audyt/features/accounting/presentation/tax_overview_page.dart';
import 'package:audyt/features/accounting/presentation/tax_rates_page.dart';
import 'package:audyt/features/accounting/presentation/tax_remittance_dialog.dart';
import 'package:audyt/features/purchases/presentation/claims_page.dart';
import 'package:audyt/features/purchases/presentation/claim_receipts_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixed_popout_host.dart';
import 'restored_page_routes_test.dart' show tables;
import 'journal_workspace_integration_test.dart' show captureUi;

Future<void> tap(WidgetTester t, Finder target) async {
  await t.ensureVisible(target);
  await t.pumpAndSettle();
  await t.tap(target);
  await t.pumpAndSettle();
}

Future<void> tab(WidgetTester t, String area, String label) async {
  final tabs = t.widget<AccountingTabs>(
    find.byKey(ValueKey('area-tabs-$area')),
  );
  final index = tabs.labels.indexOf(label);
  expect(index, greaterThanOrEqualTo(0));
  await tap(t, find.byKey(ValueKey('preview-tab-$area-$index')));
}

Future<void> close(WidgetTester t) async {
  await tap(t, find.byType(AccountingCloseIcon).last);
}

void main() {
  for (final width in [720.0, 1224.0]) {
    for (final proposed in [false, true]) {
      testWidgets('real tax and claim routes proposal=$proposed at $width', (
        t,
      ) async {
        t.view.physicalSize = Size(width, 1400);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        installFixedPopoutHost(t);
        final w = await createDemoWorkspace();
        addTearDown(w.dispose);
        final before = tables(w);
        if (Platform.environment['AUDYT_UI_CAPTURE_DIR'] != null) {
          await (FontLoader('Inter')
                ..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2')))
              .load();
          await (FontLoader('MaterialIcons')
                ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
              .load();
        }
        await t.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: proposed
                ? AudytApp(initialPath: '/taxes', workspace: w)
                : AudytApp(
                    taxWorkflowProposal: false,
                    initialPath: '/taxes',
                    workspace: w,
                  ),
          ),
        );
        Future<void> capture(String view) async {
          if (proposed) {
            await captureUi(t, 'Tax Proposal Route $view ${width.toInt()}');
          }
        }

        await t.pumpAndSettle();
        await tab(t, 'taxes', 'Tax Codes');
        expect(
          t.takeException(),
          isNull,
          reason: 'tax codes must fit actual app content width',
        );
        await capture('Tax Codes');
        final codes = t.widget<TaxRatesPage>(find.byType(TaxRatesPage));
        expect(codes.workspace, same(w));
        expect(codes.purchaseCostProposal, proposed);
        expect(codes.taxAgencyProposal, proposed);
        await tap(t, find.byKey(const ValueKey('tax-rate-add')));
        expect(
          t.takeException(),
          isNull,
          reason: 'tax code editor must fit actual app content width',
        );
        await capture('Tax Code Editor');
        final editor = t.widget<FrontendFormDialog>(
          find.byType(FrontendFormDialog),
        );
        expect(
          editor.form.fields.any((f) => f.label == 'Tax Agency'),
          proposed,
        );
        await close(t);
        await tab(t, 'taxes', 'Tax Overview');
        expect(
          t.takeException(),
          isNull,
          reason: 'tax overview must fit actual app content width',
        );
        await capture('Tax Overview');
        final overview = t.widget<TaxOverviewPage>(
          find.byType(TaxOverviewPage),
        );
        expect(overview.workspace, same(w));
        expect(overview.agencyProposal, proposed);
        expect(overview.taxPaymentsProposal, proposed);
        expect(
          find.text('Record Tax Payment'),
          proposed ? findsOneWidget : findsNothing,
        );
        if (proposed) {
          await tap(t, find.text('Record Tax Payment'));
          expect(find.byType(TaxRemittanceEditor), findsOneWidget);
          expect(
            find.text(
              'Add the agency, period, liability account and amount for each allocation.',
            ),
            findsNothing,
            reason: 'Allocation guidance belongs to title help, not a clipped empty list.',
          );
          final allocationHelp = t
              .widgetList<AccountingFieldHelp>(find.byType(AccountingFieldHelp))
              .singleWhere((help) => help.label == 'Tax Allocations');
          expect(allocationHelp.message, contains('liability account'));
          final allocationAdd = find.byKey(
            const ValueKey('tax-allocation-add'),
          );
          expect(
            t.getSize(allocationAdd),
            const Size.square(AccountingDismissIcon.controlExtent - 8),
            reason: 'The original compact token paints a 20px circle inside its 28px allocation.',
          );
          final allocationButton = t.widget<IconButton>(allocationAdd);
          expect(
            allocationButton.constraints,
            const BoxConstraints.tightFor(
              width: AccountingDismissIcon.controlExtent,
              height: AccountingDismissIcon.controlExtent,
            ),
          );
          expect(
            allocationButton.onPressed,
            isNull,
            reason:
                'The empty real-route workspace has no configured tax agency.',
          );
          expect(
            allocationButton.style!.backgroundColor!.resolve({
              WidgetState.disabled,
            }),
            AccountingTheme.of(t.element(allocationAdd)).primary
                .withValues(alpha: .4),
          );
          expect(find.text('Add Allocation'), findsNothing);
          expect(
            t.takeException(),
            isNull,
            reason: 'tax payment editor must fit actual app content width',
          );
          await capture('Payment Editor');
          await close(t);
        }
        await tap(
          t,
          find.byKey(const ValueKey('navigation-item-expenses-vendors')),
        );
        await tab(t, 'expenses-vendors', 'Claims');
        expect(
          t.takeException(),
          isNull,
          reason: 'claims must fit actual app content width',
        );
        await capture('Claims');
        final claims = t.widget<ClaimsPage>(find.byType(ClaimsPage));
        expect(claims.workspace, same(w));
        expect(claims.receiptTaxProposal, proposed);
        await tap(t, find.byKey(const ValueKey('claims-create')));
        expect(find.byType(ClaimEditorDialog), findsNothing);
        expect(find.text('Unavailable'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('record-claim-submit')),
          findsOneWidget,
        );
        expect(
          t
              .widget<FilledButton>(
                find.byKey(const ValueKey('record-claim-submit')),
              )
              .onPressed,
          isNull,
        );
        expect(
          t.takeException(),
          isNull,
          reason: 'claim editor must fit actual app content width',
        );
        await capture('Claim Creation Unavailable');
        expect(find.byType(ClaimReceiptsEditor), findsNothing);
        expect(
          tables(w),
          before,
          reason: 'Navigation and cancellation must not commit book changes.',
        );
        expect(t.takeException(), isNull);
      });
    }
  }
}
