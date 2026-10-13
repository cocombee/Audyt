import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/app.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/app/responsive.dart';
import 'package:audyt/features/accounting/presentation/widgets/accounting_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';

import 'journal_workspace_integration_test.dart'
    show captureUi, loadJournalLayoutFonts;

void main() {
  for (final width in [720.0, 1100.0, 1920.0]) {
    testWidgets('actual page filter/action family at $width', (t) async {
      await t.binding.setSurfaceSize(Size(width, 1100));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await loadJournalLayoutFonts();
      await (FontLoader(
        'Rubik',
      )..addFont(rootBundle.load('assets/fonts/Rubik-Medium.ttf'))).load();
      final w = await createDemoWorkspace(includeRowReview: true);
      addTearDown(w.dispose);
      final visited = <String>{};
      const affected = {
        'Expenses',
        'Bills',
        'Claims',
        'Payment Vouchers',
        'Invoices',
        'Quotations',
        'Tax Overview',
        'Tax Codes',
      };
      for (final area in ['expenses-vendors', 'sales-customers', 'taxes']) {
        await t.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: DemoCompany(
              child: AudytApp(
                key: ValueKey(area),
                workspace: w,
                initialPath: '/$area',
                showInitialSetup: false,
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        final tabs = t.widget<AccountingTabs>(
          find.byKey(ValueKey('area-tabs-$area')),
        );
        for (var i = 0; i < tabs.labels.length; i++) {
          final label = tabs.labels[i];
          if (!affected.contains(label)) continue;
          visited.add(label);
          final tab = find.byKey(ValueKey('preview-tab-$area-$i'));
          await t.ensureVisible(tab);
          await t.tap(tab);
          await t.pumpAndSettle();
          final barFinder = find.byType(AccountingPageFilterBar);
          expect(barFinder, findsOneWidget, reason: label);
          final bar = t.widget<AccountingPageFilterBar>(barFinder);
          final bounds = t.getRect(barFinder);
          for (final action in bar.actions) {
            final f = find.byWidget(action);
            final button = find.descendant(
              of: f,
              matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
            );
            expect(button, findsOneWidget, reason: label);
            expect(t.widget(button), isA<OutlinedButton>(), reason: label);
            final r = t.getRect(button);
            expect(r.height, accountingControlHeight, reason: label);
            expect(r.width, lessThan(bounds.width), reason: label);
          }
          if (bar.children.isNotEmpty && bar.actions.isNotEmpty) {
            final lastField = t.getRect(find.byWidget(bar.children.last));
            final firstAction = t.getRect(find.byWidget(bar.actions.first));
            expect(
              firstAction.bottom,
              closeTo(lastField.bottom, .1),
              reason: label,
            );
            expect(
              firstAction.left - lastField.right,
              closeTo(accountingContentInset, .1),
              reason: label,
            );
          }
          expect(t.takeException(), isNull, reason: label);
          await captureUi(t, 'Page Contract $label ${width.toInt()}');
        }
      }
      expect(visited, affected);
    });
  }
  testWidgets('neutral page actions do not alter primary commands or popouts', (
    t,
  ) async {
    await t.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: Scaffold(
          body: AccountingPageControlScope(
            child: Builder(
              builder: (context) => Column(
                children: [
                  AccountingPageFilterBar(
                    actions: [
                      AccountingButton.secondary(
                        context,
                        key: const ValueKey('page-neutral'),
                        onPressed: () {},
                        child: const Text('Refresh'),
                      ),
                    ],
                    children: [
                      AccountingButton.primary(
                        context,
                        key: const ValueKey('page-run'),
                        onPressed: () {},
                        child: const Text('Run Report'),
                      ),
                    ],
                  ),
                  AccountingButton.primary(
                    context,
                    key: const ValueKey('open-popup'),
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (context) => Dialog(
                        child: AccountingPageFilterBar(
                          actions: [
                            AccountingButton.primary(
                              context,
                              key: const ValueKey('popup-primary'),
                              onPressed: () {},
                              child: const Text('Save'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    child: const Text('Open'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(
      t.widget(find.byKey(const ValueKey('page-neutral'))),
      isA<OutlinedButton>(),
    );
    expect(
      t.widget(find.byKey(const ValueKey('page-run'))),
      isA<FilledButton>(),
    );
    await t.tap(find.byKey(const ValueKey('open-popup')));
    await t.pumpAndSettle();
    expect(
      t.widget(find.byKey(const ValueKey('popup-primary'))),
      isA<FilledButton>(),
    );
    expect(t.takeException(), isNull);
  });
}
