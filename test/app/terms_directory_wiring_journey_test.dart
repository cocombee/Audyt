import 'dart:io';

import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/app.dart';
import 'package:audyt/app/naming_setup.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/domain/payment_terms.dart';
import 'package:audyt/features/accounting/presentation/payment_terms_directory_dialog.dart';
import 'package:audyt/features/purchases/presentation/bills_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/accounting/data/bill_draft_persistence_test.dart'
    show setupBill;
import '../support/accounting_test_finders.dart' show accountingCloseIcon;
import '../support/accounting_text_input.dart' show enterAccountingText;
import 'claim_receipts_proposal_test.dart' show capture, prepare, tap;
import 'restored_page_routes_test.dart' show tables;

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(namingSettingsChannel, (call) async {
          if (call.method == 'load' || call.method == 'loadFolder') return null;
          throw StateError('Unexpected Settings mutation: ${call.method}');
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(namingSettingsChannel, null);
  });

  for (final width in [720.0, 1162.0]) {
    testWidgets(
      'Settings saves, searches and reopens exact named rules at $width',
      (tester) async {
        await prepare(tester, width);
        final root = Directory.systemTemp.createTempSync(
          'terms-directory-wiring-',
        );
        addTearDown(() => root.deleteSync(recursive: true));
        final path = '${root.path}/books.sqlite';
        var workspace = await AccountingWorkspace.open(path);
        addTearDown(() => workspace.dispose());

        Finder key(String name) => find.byKey(ValueKey(name)).last;
        Future<void> showDirectory() async {
          await tester.pumpWidget(
            RepaintBoundary(
              key: const ValueKey('workspace-capture'),
              child: AudytApp(workspace: workspace, showInitialSetup: false),
            ),
          );
          await tester.pumpAndSettle();
          await tap(tester, key('accounting-settings'));
          await tap(tester, key('settings-editor-Terms'));
          await tap(tester, key('settings-manage-terms'));
          expect(find.byType(PaymentTermsDirectoryDialog), findsOneWidget);
        }

        Future<void> fill(String label, String value) =>
            enterAccountingText(tester, key('design-field-$label'), value);
        Future<void> choose(String label, String value) async {
          await tap(tester, key('design-field-$label'));
          await tap(tester, find.text(value).last);
        }

        await showDirectory();
        expect(workspace.paymentTerms, isEmpty);
        expect(find.text('No terms have been saved yet.'), findsOneWidget);
        await capture(tester, 'Terms Workspace Empty ${width.toInt()}');

        await tap(tester, key('terms-new'));
        await fill('Name', '  Fictional Net 45  ');
        await fill('Due In Days', '45');
        await tap(tester, key('design-review'));
        expect(find.text('Fictional Net 45'), findsOneWidget);
        await capture(tester, 'Terms Fixed Review ${width.toInt()}');
        await tap(tester, key('design-review'));
        expect(workspace.paymentTerms, hasLength(1));
        final fixed = workspace.paymentTerms.single;
        expect(fixed.name, 'Fictional Net 45');
        expect(fixed.rule.kind, PaymentTermKind.daysAfterIssue);
        expect(fixed.rule.days, 45);
        expect(fixed.revision, 1);
        expect(fixed.active, isTrue);
        expect(
          find.byKey(ValueKey('terms-row-${fixed.id.value}')),
          findsOneWidget,
        );

        await tap(tester, key('terms-new'));
        await fill('Name', 'Fictional Monthly');
        await choose('Due Rule', 'Day Of Month');
        await fill('Monthly Due Day', '20');
        await fill('Rollover Within Days', '5');
        await capture(tester, 'Terms Monthly Form ${width.toInt()}');
        await tap(tester, key('design-review'));
        await tap(tester, key('design-back'));
        expect(
          tester
              .widget<TextFormField>(key('design-field-Monthly Due Day'))
              .controller!
              .text,
          '20',
        );
        await tap(tester, key('design-review'));
        await capture(tester, 'Terms Monthly Review ${width.toInt()}');
        await tap(tester, key('design-review'));
        final monthly = workspace.paymentTerms.singleWhere(
          (term) => term.name == 'Fictional Monthly',
        );
        expect(monthly.rule.kind, PaymentTermKind.dayOfMonth);
        expect(monthly.rule.dayOfMonth, 20);
        expect(monthly.rule.rolloverWithinDays, 5);
        expect(monthly.revision, 1);

        await tester.enterText(key('terms-search'), 'monthly');
        await tester.pumpAndSettle();
        expect(find.text('Fictional Monthly'), findsOneWidget);
        expect(find.text('Fictional Net 45'), findsNothing);
        await capture(tester, 'Terms Workspace Search ${width.toInt()}');
        await tester.enterText(key('terms-search'), '');
        await tester.pumpAndSettle();
        await tap(tester, key('terms-include-inactive'));
        expect(find.text('Fictional Net 45'), findsOneWidget);

        await tap(tester, key('terms-new'));
        await fill('Name', ' fictional net 45 ');
        await fill('Due In Days', '30');
        await tap(tester, key('design-review'));
        await tap(tester, key('design-review'));
        expect(find.textContaining('already exists'), findsOneWidget);
        expect(workspace.paymentTerms, hasLength(2));
        await capture(tester, 'Terms Duplicate Error ${width.toInt()}');
        await tap(tester, key('design-back'));
        expect(
          tester
              .widget<TextFormField>(key('design-field-Name'))
              .controller!
              .text,
          ' fictional net 45 ',
        );
        await tap(tester, accountingCloseIcon().last);
        await tap(tester, find.text('Discard').last);
        expect(workspace.paymentTerms, hasLength(2));

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        workspace.dispose();
        workspace = await AccountingWorkspace.open(path);
        expect(workspace.paymentTerms, hasLength(2));
        expect(
          workspace.paymentTerms
              .singleWhere((term) => term.id == fixed.id)
              .rule
              .toJson(),
          fixed.rule.toJson(),
        );
        expect(
          workspace.paymentTerms
              .singleWhere((term) => term.id == monthly.id)
              .rule
              .toJson(),
          monthly.rule.toJson(),
        );
        await showDirectory();
        expect(find.text('Fictional Net 45'), findsOneWidget);
        expect(find.text('Fictional Monthly'), findsOneWidget);
        await capture(tester, 'Terms Workspace Reopened ${width.toInt()}');
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Bill Add Term saves independently and cancellation retains parent at $width',
      (tester) async {
        await prepare(tester, width);
        final workspace = await AccountingWorkspace.open(':memory:');
        addTearDown(workspace.dispose);
        await setupBill(workspace);
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: MaterialApp(
              theme: AccountingTheme.light(),
              home: Scaffold(body: BillsPage(workspace: workspace)),
            ),
          ),
        );
        await tester.pumpAndSettle();
        Finder key(String name) => find.byKey(ValueKey(name)).last;
        await tap(tester, key('new-bill'));
        await enterAccountingText(
          tester,
          key('design-field-Reference'),
          'Bill reference retained',
        );
        final before = tables(workspace);
        Future<void> addTerm() async {
          await tap(tester, key('design-field-Payment Terms'));
          await tap(tester, find.text('Add Term'));
        }

        await addTerm();
        await enterAccountingText(
          tester,
          key('design-field-Name'),
          'Cancelled',
        );
        await tap(tester, accountingCloseIcon().last);
        await tap(tester, find.text('Discard').last);
        expect(workspace.paymentTerms, isEmpty);
        expect(tables(workspace), before);

        await addTerm();
        await enterAccountingText(
          tester,
          key('design-field-Name'),
          'Bill Only 12',
        );
        await enterAccountingText(
          tester,
          key('design-field-Due In Days'),
          '12',
        );
        await tap(tester, key('design-review'));
        await tap(tester, key('design-review'));
        expect(workspace.paymentTerms.single.name, 'Bill Only 12');
        expect(workspace.paymentTerms.single.rule.days, 12);
        expect(tables(workspace)['bill_drafts'], before['bill_drafts']);
        expect(
          tables(workspace)['bill_draft_history'],
          before['bill_draft_history'],
        );
        expect(
          tester
              .widget<TextFormField>(key('design-field-Reference'))
              .controller!
              .text,
          'Bill reference retained',
        );
        final selector = find
            .ancestor(
              of: key('design-field-Payment Terms'),
              matching: find.byType(AccountingSelector<String>),
            )
            .last;
        expect(
          tester.widget<AccountingSelector<String>>(selector).value,
          'Use Vendor Default',
        );
        await capture(tester, 'Bill Add Term Saved Return ${width.toInt()}');
        await tap(tester, accountingCloseIcon().last);
        await tap(tester, find.text('Discard').last);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
