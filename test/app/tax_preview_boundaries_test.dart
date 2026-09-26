import 'dart:io';

import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/app.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/accounting/data/tax_remittance_wiring_test.dart'
    show setup, report;
import '../support/fixed_popout_host.dart';
import 'journal_workspace_integration_test.dart' show captureUi;
import 'restored_page_routes_test.dart' show tables;

Future<void> tap(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  await t.pumpAndSettle();
}

Future<void> tab(WidgetTester t, String area, String title) async {
  final tabs = t.widget<AccountingTabs>(
    find.byKey(ValueKey('area-tabs-$area')),
  );
  final index = tabs.labels.indexOf(title);
  expect(index, greaterThanOrEqualTo(0));
  await tap(t, find.byKey(ValueKey('preview-tab-$area-$index')));
}

void main() {
  for (final width in [720.0, 1224.0]) {
    testWidgets(
      'tax previews cannot file a return or alter recorded payments at $width',
      (t) async {
        t.view.physicalSize = Size(width, 1400);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        installFixedPopoutHost(t);
        final root = Directory.systemTemp.createTempSync(
          'audyt-tax-preview-boundary-',
        );
        addTearDown(() => root.deleteSync(recursive: true));
        final path = '${root.path}/books.sqlite';
        final f = await setup(path: path);
        var w = f.w;
        addTearDown(() => w.dispose());
        final payment = f.record(300);
        final before = tables(w);
        expect((await report(w)).remittedTax, BigInt.from(300));
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
            child: AudytApp(initialPath: '/taxes', workspace: w),
          ),
        );
        await t.pumpAndSettle();
        await tab(t, 'taxes', 'Returns & Payments');
        expect(find.text('Preview Fields'), findsOneWidget);
        expect(find.text('Record Tax Return Or Payment'), findsNothing);
        expect(
          find.textContaining('No tax return or payment is recorded'),
          findsOneWidget,
        );
        await captureUi(t, 'Tax Returns Preview Boundary ${width.toInt()}');
        await tap(t, find.byKey(const ValueKey('design-open-form')));
        await tap(t, find.byKey(const ValueKey('design-field-Return Status')));
        await tap(t, find.text('Submitted').last);
        await t.enterText(
          find.byKey(const ValueKey('design-field-Submission Reference')),
          'FICTIONAL-NOT-FILED',
        );
        await tap(t, find.byKey(const ValueKey('design-review')));
        expect(find.text('Keep Preview'), findsOneWidget);
        expect(find.text('Save'), findsNothing);
        await captureUi(t, 'Tax Return Submitted Preview ${width.toInt()}');
        await tap(t, find.byKey(const ValueKey('design-review')));
        expect(find.text('Edit Preview'), findsOneWidget);
        expect(tables(w), before);
        await tap(t, find.byKey(const ValueKey('navigation-item-reports')));
        await tab(t, 'reports', 'Tax Reconciliation');
        final card = find.byKey(
          const ValueKey('report-preview-table-Tax Reconciliation'),
        );
        expect(
          find.descendant(
            of: card,
            matching: find.text('Tax-return comparison unavailable.'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: card, matching: find.text('—')),
          findsNWidgets(6),
        );
        expect(
          find.textContaining('Book tax activity and remittance evidence'),
          findsOneWidget,
        );
        expect(
          find.textContaining('tax payments are not connected'),
          findsNothing,
        );
        await captureUi(
          t,
          'Tax Return Reconciliation Unavailable ${width.toInt()}',
        );
        expect(t.takeException(), isNull);
        expect(tables(w), before);
        await t.pumpWidget(const SizedBox.shrink());
        w.dispose();
        w = await AccountingWorkspace.open(path);
        expect(
          tables(w),
          before,
          reason: 'Neither Submitted preview nor report navigation may mutate durable evidence.',
        );
        expect(w.taxRemittances().single.id, payment.id);
        expect((await report(w)).remittedTax, BigInt.from(300));
      },
    );
  }
}
