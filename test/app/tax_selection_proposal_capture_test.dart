// Design proposal only. Reuses the production selector/alert/popout owners;
// it does not change transaction entry, persist data or establish route wiring.
import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/transaction_form_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'journal_workspace_integration_test.dart' show captureUi;

void main() {
  for (final width in [720.0, 1224.0]) {
    for (final historic in [false, true]) {
      testWidgets('tax selector proposal $width historical $historic', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await (FontLoader('Inter')
              ..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2')))
            .load();
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
                      key: const ValueKey('open-tax-proposal'),
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (context) {
                          String? tax;
                          return StatefulBuilder(
                            builder: (context, setState) => AccountingDialog.alert(
                              context,
                              title: historic
                                  ? 'Older Unresolved Tax · Proposed'
                                  : 'New Tax Entry · Proposed',
                              description: 'Select the applicable tax for this transaction.',
                              fixedContentWidth: 600,
                              maxContentWidth: 600,
                              actions: [],
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (historic && tax == null) ...[
                                    AccountingAlert.build(
                                      context,
                                      title: 'Tax Selection Required',
                                      description: 'This saved record has no resolved tax code. Select its applicable code before posting.',
                                      tone: AccountingAlertTone.warning,
                                    ),
                                    const SizedBox(
                                      height: accountingContentInset,
                                    ),
                                  ],
                                  accountingFieldLabel(context, 'Tax'),
                                  const SizedBox(
                                    height: accountingFieldLabelGap,
                                  ),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: AccountingSelector<String>(
                                      assignedWidth:
                                          AccountingTransactionGridTokens.selectionWidth(
                                            context,
                                            'Select Tax',
                                          ),
                                      triggerKey: const ValueKey(
                                        'proposal-tax-trigger',
                                      ),
                                      hintText: 'Select Tax',
                                      value: tax,
                                      options: const [
                                        AccountingSelectorOption(
                                          value: '0',
                                          label: 'No Tax',
                                        ),
                                        AccountingSelectorOption(
                                          value: 'sample-sst',
                                          label: 'SST · 6%',
                                        ),
                                        AccountingSelectorOption(
                                          value: 'sample-service',
                                          label: 'Service Tax · 8%',
                                        ),
                                      ],
                                      onChanged: (value) =>
                                          setState(() => tax = value),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                      child: const Text('Open Proposal'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open Proposal'));
        await tester.pumpAndSettle();
        expect(find.text('Review Needed'), findsNothing);
        expect(find.text('Select Tax'), findsOneWidget);
        final name = historic ? 'Historical' : 'New';
        await captureUi(tester, 'Tax Selector Proposed $name ${width.toInt()}');
        await tester.tap(find.byKey(const ValueKey('proposal-tax-trigger')));
        await tester.pumpAndSettle();
        await captureUi(
          tester,
          'Tax Selector Proposed $name Menu ${width.toInt()}',
        );
        expect(find.text('No Tax'), findsOneWidget);
        expect(find.text('Review Needed'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
