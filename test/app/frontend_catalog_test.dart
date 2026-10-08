import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/accounting_description_field.dart';
import 'package:audyt/app/app.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/app/user_directory.dart';
import 'package:audyt/features/accounting/domain/payee.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/domain/company_tax_rate.dart';
import 'package:audyt/core/ids/entity_id.dart';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as rich;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audyt/app/frontend_review.dart';
import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/transaction_form_layout.dart';

import 'journal_workspace_integration_test.dart'
    show captureUi, loadJournalLayoutFonts, paintedTextTop;
import '../support/fixed_popout_host.dart';
import '../support/accounting_text_input.dart';

import 'package:audyt/features/accounting/presentation/customer_page.dart';

Future<void> openForm(WidgetTester tester, DesignForm form) async {
  installFixedPopoutHost(tester);
  await (FontLoader(
    'MaterialIcons',
  )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  await tester.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('workspace-capture'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AccountingTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => openFrontendForm(context, form),
              child: const Text('Open Form'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open Form'));
  await tester.pumpAndSettle();
}

void expectHeaderChoicesReadable(WidgetTester tester) {
  for (final element in find.byType(AccountingSelector<String>).evaluate()) {
    final selector = element.widget as AccountingSelector<String>;
    if (selector.triggerKey == null) continue;
    final text = find
        .descendant(
          of: find.byKey(selector.triggerKey!),
          matching: find.byType(Text),
        )
        .first;
    expect(
      tester.renderObject<RenderParagraph>(text).didExceedMaxLines,
      isFalse,
      reason:
          '${selector.triggerKey}: empty and selected header labels must fit',
    );
  }
}

void main() {
  for (final width in [720.0, 1224.0]) {
    for (final savedPreview in [false, true]) {
      testWidgets(
        'actual Card Credit ${savedPreview ? 'View' : 'New'} inline Customer identity and cancellation at $width',
        (tester) async {
          tester.view.physicalSize = Size(width, 1200);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          installFixedPopoutHost(tester);
          await loadJournalLayoutFonts();
          final workspace = await createDemoWorkspace();
          addTearDown(workspace.dispose);
          final customerCount = workspace.customers().length;
          final payeeIds = workspace.payees.all.map((p) => p.id).toSet();
          await tester.pumpWidget(
            RepaintBoundary(
              key: const ValueKey('workspace-capture'),
              child: DemoCompany(
                child: AudytApp(workspace: workspace, showInitialSetup: false),
              ),
            ),
          );
          await tester.pumpAndSettle();
          Future<void> tap(Finder target) async {
            await tester.ensureVisible(target);
            await tester.tap(target);
            await tester.pumpAndSettle();
          }

          Finder field(String label) =>
              find.byKey(ValueKey('design-field-$label'));
          AccountingSelector<String> payee() => tester.widget(
            find.byWidgetPredicate(
              (w) =>
                  w is AccountingSelector<String> &&
                  w.triggerKey == const ValueKey('design-field-Payee'),
            ),
          );
          await tap(find.byKey(const ValueKey('navigation-item-banking')));
          await tap(find.text('Credit Card Credits').first);
          final view = find
              .byWidgetPredicate(
                (w) =>
                    w.key is ValueKey<String> &&
                    (w.key! as ValueKey<String>).value.startsWith(
                      'view-record-',
                    ),
              )
              .first;
          await tap(
            savedPreview
                ? view
                : find.byKey(const ValueKey('design-open-form')),
          );
          final originalSelection = payee().value;
          final state = savedPreview ? 'View' : 'New';
          final captureName = 'Card Credit $state Inline Customer';
          await tap(field('Payee'));
          await tap(find.text('Add Payee').last);
          await tester.enterText(
            find.byKey(const ValueKey('payee-name-field')),
            'Inline Customer $state ${width.toInt()}',
          );
          Future<void> customerBranch() async {
            await tap(find.byKey(const ValueKey('payee-type-field')));
            final type = tester.widget<AccountingSelector<String>>(
              find.byWidgetPredicate(
                (w) =>
                    w is AccountingSelector<String> &&
                    w.triggerKey == const ValueKey('payee-type-field'),
              ),
            );
            expect(type.options.map((o) => o.label), contains('Customer'));
            expect(
              type.options.map((o) => o.label),
              isNot(contains('Employee')),
            );
            await tap(find.text('Customer').last);
            expect(
              tester
                  .widget<FrontendFormDialog>(
                    find.byType(FrontendFormDialog).last,
                  )
                  .form,
              same(customerForm),
            );
            expect(
              tester.widget<TextFormField>(field('Name').last).controller!.text,
              'Inline Customer $state ${width.toInt()}',
            );
          }

          await customerBranch();
          await captureUi(
            tester,
            '$captureName Canonical Form ${width.toInt()}',
          );
          await enterAccountingText(
            tester,
            field('Email').last,
            'unsaved@example.test',
          );
          await tester.pumpAndSettle();
          await tap(find.byKey(const ValueKey('design-close')).last);
          await tap(find.text('Keep Editing'));
          expect(find.text('unsaved@example.test'), findsOneWidget);
          await tap(find.byKey(const ValueKey('design-close')).last);
          await captureUi(
            tester,
            '$captureName Discard Warning ${width.toInt()}',
          );
          await tap(find.text('Discard'));
          expect(workspace.customers().length, customerCount);
          expect(payee().value, originalSelection);
          expect(
            find.text('Inline Customer $state ${width.toInt()}'),
            findsOneWidget,
          );
          expect(
            tester
                .widget<AccountingSelector<String>>(
                  find.byWidgetPredicate(
                    (w) =>
                        w is AccountingSelector<String> &&
                        w.triggerKey == const ValueKey('payee-type-field'),
                  ),
                )
                .value,
            PayeeType.other.name,
          );
          await captureUi(
            tester,
            '$captureName Payee Retained ${width.toInt()}',
          );
          await customerBranch();
          expect(
            tester.widget<TextFormField>(field('Email').last).controller!.text,
            isEmpty,
          );
          await enterAccountingText(
            tester,
            field('Email').last,
            'saved@example.test',
          );
          await tester.pumpAndSettle();
          await tap(find.byKey(const ValueKey('design-review')).last);
          await tap(find.byKey(const ValueKey('design-review')).last);
          final customer = workspace.customers().singleWhere(
            (c) => c.displayName == 'Inline Customer $state ${width.toInt()}',
          );
          expect(workspace.customers().length, customerCount + 1);
          expect(customer.contact.email, 'saved@example.test');
          expect(payee().value, 'customer:${customer.id.value}');
          expect(
            payee().options.singleWhere((o) => o.value == payee().value).label,
            '${customer.displayName} · Customer',
          );
          expect(workspace.payees.all.map((p) => p.id).toSet(), payeeIds);
          expect(find.byKey(const ValueKey('payee-name-field')), findsNothing);
          await captureUi(
            tester,
            '$captureName Maintained ID Selected ${width.toInt()}',
          );
          await tap(find.byKey(const ValueKey('design-close')));
          await tap(find.text('Discard'));
          expect(workspace.customers().length, customerCount + 1);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
  for (final title in ['Credit Card Credits']) {
    for (final width in [720.0, 1224.0]) {
      testWidgets(
        'actual $title maintained payees and registration search at $width',
        (tester) async {
          tester.view.physicalSize = Size(width, 1200);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          installFixedPopoutHost(tester);
          await loadJournalLayoutFonts();
          final workspace = await createDemoWorkspace();
          addTearDown(workspace.dispose);
          workspace.payees.save(
            const Payee(
              id: 'legacy-staff',
              name: 'Legacy Staff',
              type: PayeeType.staff,
            ),
          );
          workspace.payees.save(
            const Payee(
              id: 'inspection-supplier',
              name: 'Inspection Supplier',
              type: PayeeType.supplier,
            ),
          );
          final directory = _CardPayeeDirectory();
          addTearDown(directory.dispose);
          await tester.pumpWidget(
            RepaintBoundary(
              key: const ValueKey('workspace-capture'),
              child: AudytApp(
                workspace: workspace,
                userDirectory: directory,
                showInitialSetup: false,
              ),
            ),
          );
          await tester.pumpAndSettle();
          Future<void> tap(Finder target) async {
            await tester.ensureVisible(target);
            await tester.tap(target);
            await tester.pumpAndSettle();
          }

          Finder field(String label) =>
              find.byKey(ValueKey('design-field-$label'));
          AccountingSelector<String> payee() => tester.widget(
            find.byWidgetPredicate(
              (w) =>
                  w is AccountingSelector<String> &&
                  w.triggerKey == const ValueKey('design-field-Payee'),
            ),
          );
          await tap(find.byKey(const ValueKey('navigation-item-banking')));
          await tap(find.text(title).first);
          await tap(find.byKey(const ValueKey('design-open-form')));
          expect(
            find.text(
              'Employee choices could not be loaded. Search again to retry.',
            ),
            findsOneWidget,
          );
          expect(payee().options.first.label, 'Add Payee');
          expect(
            payee().options.any((o) => o.value == 'legacy-staff'),
            isFalse,
          );
          final customer = workspace.customers().firstWhere((c) => c.isActive);
          final customerId = 'customer:${customer.id.value}';
          expect(payee().options.any((o) => o.value == customerId), isTrue);
          final supplier = workspace.payees.all.firstWhere(
            (p) => p.type == PayeeType.supplier,
          );
          expect(payee().options.any((o) => o.value == supplier.id), isTrue);
          await captureUi(
            tester,
            '$title Closed Lookup Error ${width.toInt()}',
          );
          await tap(field('Payee'));
          await captureUi(
            tester,
            '$title Payee Lookup Failure ${width.toInt()}',
          );
          final search = find.descendant(
            of: field('Payee'),
            matching: find.byType(TextField),
          );
          await tester.enterText(search, 'Registered');
          await tester.pumpAndSettle();
          expect(directory.queries, contains('Registered'));
          expect(
            payee().options.any(
              (o) => o.value == 'registered-employee-inspection',
            ),
            isTrue,
          );
          expect(payee().errorText, isNull);
          await captureUi(
            tester,
            '$title Registered Employee Search ${width.toInt()}',
          );
          await tap(find.text('Registered Employee · Employee').last);
          expect(payee().value, 'registered-employee-inspection');
          await tap(field('Payee'));
          await tap(find.text('Add Payee').last);
          expect(find.text('Employee'), findsNothing);
          await tap(find.byKey(const ValueKey('payee-close')));
          expect(payee().value, 'registered-employee-inspection');
          await tap(field('Payee'));
          await tester.enterText(search, customer.displayName);
          await tester.pumpAndSettle();
          await tap(find.text('${customer.displayName} · Customer').last);
          expect(payee().value, customerId);
          expect(
            workspace.payees.all.any((p) => p.id == customerId),
            isFalse,
            reason:
                'Selecting a customer must not duplicate its master as a Payee',
          );
          await captureUi(
            tester,
            '$title Maintained Customer Selected ${width.toInt()}',
          );
          await tap(find.byKey(const ValueKey('design-close')));
          await tap(find.text('Discard'));
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
  for (final width in [720.0, 1224.0]) {
    testWidgets(
      'actual Card Credit caller preserves line and account owners at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        installFixedPopoutHost(tester);
        await loadJournalLayoutFonts();
        final workspace = await createDemoWorkspace();
        addTearDown(workspace.dispose);
        await workspace.createAccount(
          code: '2200',
          name: 'Demo Card',
          type: AccountType.liability,
          profile: const AccountProfile(
            reportingType: ReportingAccountType.creditCard,
            detailType: 'Credit Card',
          ),
        );
        workspace.saveTaxRate(
          CompanyTaxRate(
            id: EntityId.random(),
            name: 'Purchase Inspection',
            percent: '6',
            effectiveFrom: DateTime(2020),
            application: TaxApplication.purchases,
          ),
        );
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: AudytApp(workspace: workspace, showInitialSetup: false),
          ),
        );
        await tester.pumpAndSettle();
        Future<void> tap(Finder target) async {
          await tester.ensureVisible(target);
          await tester.tap(target);
          await tester.pumpAndSettle();
        }

        Finder field(String label) =>
            find.byKey(ValueKey('design-field-$label'));
        Finder lineSelector(String label) => find.byWidgetPredicate(
          (w) =>
              w is AccountingSelector<String> &&
              '${w.triggerKey}'.contains('-$label') &&
              !'${w.triggerKey}'.contains('design-field'),
        );
        await tap(find.byKey(const ValueKey('navigation-item-banking')));
        await tap(find.text('Credit Card Credits').first);
        await tap(find.byKey(const ValueKey('design-open-form')));
        expect(find.byType(AccountingTransactionGrid), findsOneWidget);
        expect(
          field('Amount'),
          findsNothing,
          reason: 'Amount is derived from the existing lines, never a second editable amount.',
        );
        expect(find.byKey(const ValueKey('design-add-line')), findsOneWidget);
        expect(field('Funding Bank Account'), findsNothing);
        await captureUi(
          tester,
          'Card Credit Actual Owner Empty ${width.toInt()}',
        );
        await tap(field('Credit Card Account'));
        await tap(find.text('Add Account').last);
        expect(
          tester
              .widget<AccountingSelector<ReportingAccountType>>(
                find.byWidgetPredicate(
                  (w) => w is AccountingSelector<ReportingAccountType>,
                ),
              )
              .options
              .map((o) => o.value),
          [ReportingAccountType.creditCard],
        );
        await captureUi(
          tester,
          'Card Credit Canonical Destination ${width.toInt()}',
        );
        await tap(find.byKey(const ValueKey('ledger-account-close')));
        await tap(field('Credit Card Account'));
        await tap(find.text('Demo Card').last);
        await tap(lineSelector('Account').first);
        await tap(find.text('Add Account').last);
        expect(
          tester
              .widget<AccountingSelector<ReportingAccountType>>(
                find.byWidgetPredicate(
                  (w) => w is AccountingSelector<ReportingAccountType>,
                ),
              )
              .options
              .length,
          15,
        );
        final nestedTax = tester.getRect(
          find.byKey(const ValueKey('ledger-default-tax')),
        );
        final nestedDetail = tester.getRect(
          find.byKey(const ValueKey('ledger-detail-type')),
        );
        expect(nestedTax.top, greaterThanOrEqualTo(nestedDetail.top));
        expect(
          nestedTax.width,
          lessThanOrEqualTo(AccountingPopoutTokens.normalContentWidth / 2),
        );
        if ((nestedTax.top - nestedDetail.top).abs() < .5) {
          expect(nestedTax.left, greaterThan(nestedDetail.right));
        } else {
          expect(
            nestedTax.left,
            closeTo(
              tester
                  .getRect(find.byKey(const ValueKey('ledger-account-code')))
                  .left,
              .5,
            ),
          );
        }
        await tap(find.byKey(const ValueKey('ledger-account-close')));
        final lineAmount = find.byWidgetPredicate(
          (w) => w is TextFormField && '${w.key}'.contains('-Amount'),
        );
        await tester.enterText(lineAmount.first, '100');
        await tester.pumpAndSettle();
        await tap(lineSelector('Tax Rate (%)').first);
        expect(find.text('Purchase Inspection · 6%'), findsWidgets);
        await tap(find.text('Purchase Inspection · 6%').last);
        expect(find.text('106.00'), findsOneWidget);
        await tap(field('Tax Mode'));
        await tap(find.text('Tax Inclusive').last);
        expect(find.text('106.00'), findsWidgets);
        await captureUi(
          tester,
          'Card Credit Purchase Tax Amount ${width.toInt()}',
        );
        await tap(find.byKey(const ValueKey('design-add-line')));
        expect(
          find.byKey(const ValueKey('design-remove-line-1')),
          findsOneWidget,
        );
        await tap(find.byKey(const ValueKey('design-remove-line-1')));
        await tap(field('Tax Mode'));
        await tap(find.text('Out Of Scope').last);
        expect(lineSelector('Tax Rate (%)'), findsNothing);
        final originalDate = tester
            .widget<TextFormField>(field('Payment Date'))
            .controller!
            .text;
        await tester.enterText(field('Reference'), 'CREDIT-INSPECTION');
        await tester.pumpAndSettle();
        await tap(field('Make Recurring'));
        await tap(find.text('Unscheduled').last);
        expect(field('Payment Date'), findsNothing);
        expect(field('Reference'), findsNothing);
        expect(field('Permit Number'), findsOneWidget);
        expect(field('Template Name'), findsOneWidget);
        expect(field('Start Date'), findsNothing);
        expect(field('Interval'), findsNothing);
        await captureUi(
          tester,
          'Card Credit Unscheduled Out Of Scope ${width.toInt()}',
        );
        await tap(field('Make Recurring'));
        await tap(find.text('Scheduled').last);
        expect(field('Payment Date'), findsNothing);
        expect(field('Reference'), findsNothing);
        expect(field('Start Date'), findsOneWidget);
        expect(field('Days In Advance'), findsOneWidget);
        await tap(field('Interval'));
        await tap(find.text('Daily').last);
        expect(field('Every'), findsOneWidget);
        expect(field('Day Of Week'), findsNothing);
        await captureUi(tester, 'Card Credit Scheduled Daily ${width.toInt()}');
        await tap(field('Make Recurring'));
        await tap(find.text('Reminder').last);
        expect(field('Days Before'), findsOneWidget);
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is AccountingFieldHelp &&
                widget.label.replaceAll(' *', '') == 'Days Before',
          ),
          findsOneWidget,
        );
        expect(field('Days In Advance'), findsNothing);
        await tap(field('Interval'));
        await tap(find.text('Weekly').last);
        expect(field('Day Of Week'), findsOneWidget);
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is AccountingFieldHelp &&
                widget.label.replaceAll(' *', '') == 'Day Of Week',
          ),
          findsOneWidget,
        );
        await tap(field('End'));
        await tap(find.text('By').last);
        expect(field('End Date'), findsOneWidget);
        await captureUi(
          tester,
          'Card Credit Reminder Weekly By ${width.toInt()}',
        );
        await tap(field('Interval'));
        await tap(find.text('Yearly').last);
        expect(field('Month Of Year'), findsOneWidget);
        expect(field('Day Of Month'), findsOneWidget);
        expect(field('Every'), findsNothing);
        await tap(field('End'));
        await tap(find.text('After').last);
        expect(field('Occurrences'), findsOneWidget);
        expect(field('End Date'), findsNothing);
        await captureUi(
          tester,
          'Card Credit Reminder Yearly After ${width.toInt()}',
        );
        await tap(field('Make Recurring'));
        await tap(find.text('No').last);
        expect(field('Template Name'), findsNothing);
        expect(field('Start Date'), findsNothing);
        expect(
          tester.widget<TextFormField>(field('Payment Date')).controller!.text,
          originalDate,
        );
        expect(
          tester.widget<TextFormField>(field('Reference')).controller!.text,
          'CREDIT-INSPECTION',
        );
        await captureUi(
          tester,
          'Card Credit Restored Transaction Header ${width.toInt()}',
        );
        await tap(field('Payee'));
        await tap(find.text('Add Payee').last);
        expect(
          tester
              .widget<AccountingSelector<dynamic>>(
                find.byWidgetPredicate(
                  (w) =>
                      w is AccountingSelector &&
                      w.triggerKey == const ValueKey('payee-type-field'),
                ),
              )
              .options
              .map((o) => o.label),
          isNot(contains('Employee')),
        );
        await tap(find.byKey(const ValueKey('payee-close')));
        await tap(field('Memo'));
        final editor = tester.widget<rich.QuillEditor>(
          find.descendant(
            of: field('Memo'),
            matching: find.byType(rich.QuillEditor),
          ),
        );
        editor.controller.replaceText(
          0,
          0,
          'Retain card credit memo',
          const TextSelection.collapsed(offset: 23),
        );
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        await tap(find.text('Keep Editing'));
        expect(
          tester
              .widget<AccountingDescriptionField>(field('Memo'))
              .controller!
              .text,
          'Retain card credit memo',
        );
        await tap(find.byKey(const ValueKey('design-close')));
        await tap(find.text('Discard'));
        await tap(find.byKey(const ValueKey('design-open-form')));
        expect(find.text('Retain card credit memo'), findsNothing);
        await tap(find.byKey(const ValueKey('design-close')));
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final width in [720.0, 1224.0]) {
    testWidgets('actual Card Payment caller uses canonical owners at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      installFixedPopoutHost(tester);
      await loadJournalLayoutFonts();
      final workspace = await createDemoWorkspace();
      addTearDown(workspace.dispose);
      final cardId = await workspace.createAccount(
        code: '2200',
        name: 'Demo Card',
        type: AccountType.liability,
        profile: const AccountProfile(
          reportingType: ReportingAccountType.creditCard,
          detailType: 'Credit Card',
        ),
      );
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('workspace-capture'),
          child: AudytApp(workspace: workspace, showInitialSetup: false),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> tap(Finder target) async {
        await tester.ensureVisible(target);
        await tester.tap(target);
        await tester.pumpAndSettle();
      }

      AccountingSelector<String> selector(String label) => tester.widget(
        find.byWidgetPredicate(
          (w) =>
              w is AccountingSelector<String> &&
              w.triggerKey == ValueKey('design-field-$label'),
        ),
      );
      Finder field(String label) => find.byKey(ValueKey('design-field-$label'));
      await tap(find.byKey(const ValueKey('navigation-item-banking')));
      await tap(find.text('Credit Card Payments').first);
      await tap(find.byKey(const ValueKey('design-open-form')));
      expect(selector('Credit Card Account').options.map((o) => o.label), [
        'Add Account',
        'Demo Card',
      ]);
      expect(selector('Funding Bank Account').options.map((o) => o.label), [
        'Add Account',
        'Demo Bank',
        'Demo Savings',
      ]);
      expect(selector('Payee').options.first.label, 'Add Payee');
      expect(field('Paid By Cheque'), findsNothing);
      expect(field('Cheque Number'), findsNothing);
      expect(find.byType(AccountingTransactionGrid), findsNothing);
      expect(find.text('Total Paid (RM)'), findsOneWidget);
      final emptyAmountWidth = tester.getSize(field('Amount')).width;
      expect(
        emptyAmountWidth,
        closeTo(tester.getSize(field('Funding Bank Account')).width, .1),
        reason: 'The solitary Amount uses the ordinary half-row track',
      );
      await captureUi(
        tester,
        'Card Payment Actual Owner Empty ${width.toInt()}',
      );
      await tap(field('Credit Card Account'));
      await tap(find.text('Add Account').last);
      final types = tester.widget<AccountingSelector<ReportingAccountType>>(
        find.byWidgetPredicate(
          (w) => w is AccountingSelector<ReportingAccountType>,
        ),
      );
      expect(types.options.map((o) => o.value), [
        ReportingAccountType.creditCard,
      ]);
      await captureUi(
        tester,
        'Card Payment Canonical Card Account ${width.toInt()}',
      );
      await tap(find.byKey(const ValueKey('ledger-account-close')));
      await tap(field('Credit Card Account'));
      await tap(find.text('Demo Card').last);
      expect(selector('Credit Card Account').value, cardId.value);
      await tap(field('Funding Bank Account'));
      await tap(find.text('Add Account').last);
      final banks = tester.widget<AccountingSelector<ReportingAccountType>>(
        find.byWidgetPredicate(
          (w) => w is AccountingSelector<ReportingAccountType>,
        ),
      );
      expect(banks.options.map((o) => o.value), [
        ReportingAccountType.cashAndCashEquivalents,
      ]);
      await tap(find.byKey(const ValueKey('ledger-account-close')));
      await tap(field('Funding Bank Account'));
      await tap(find.text('Demo Bank').last);
      await tap(field('Paid By Cheque'));
      await tester.enterText(field('Cheque Number'), 'CHEQUE-1');
      await tester.enterText(field('Amount'), '123456789012.34');
      await tester.pumpAndSettle();
      final amount = tester.widget<TextField>(
        find.descendant(of: field('Amount'), matching: find.byType(TextField)),
      );
      expect(amount.textAlign, TextAlign.right);
      final editable = tester
          .state<EditableTextState>(
            find.descendant(
              of: field('Amount'),
              matching: find.byType(EditableText),
            ),
          )
          .renderEditable;
      expect(
        editable.offset.pixels,
        closeTo(0, 0.1),
        reason: 'Focused long amounts must remain fully visible',
      );
      expect(
        tester.getSize(field('Amount')).width,
        closeTo(emptyAmountWidth, .1),
        reason: 'Entering a long amount must not grow an independent field',
      );
      await captureUi(
        tester,
        'Card Payment Cheque Long Amount ${width.toInt()}',
      );
      await tap(field('Paid By Cheque'));
      expect(field('Cheque Number'), findsNothing);
      await tap(field('Paid By Cheque'));
      expect(find.text('CHEQUE-1'), findsOneWidget);
      await tap(field('Payee'));
      await tap(find.text('Add Payee').last);
      final payeeType = tester.widget<AccountingSelector<dynamic>>(
        find.byWidgetPredicate(
          (w) =>
              w is AccountingSelector &&
              w.triggerKey == const ValueKey('payee-type-field'),
        ),
      );
      expect(
        payeeType.options.map((o) => o.label),
        isNot(contains('Employee')),
      );
      expect(
        payeeType.options.map((o) => o.label),
        isNot(contains('Customer')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('payee-name-field')),
        'Unsaved Payee',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tap(find.text('Keep Editing'));
      expect(find.text('Unsaved Payee'), findsOneWidget);
      await captureUi(
        tester,
        'Card Payment Shared Payee Retained ${width.toInt()}',
      );
      await tap(find.byKey(const ValueKey('payee-close')));
      await tap(find.text('Discard'));
      expect(find.text('CHEQUE-1'), findsOneWidget);
      expect(
        find.descendant(
          of: field('Amount'),
          matching: find.text('123,456,789,012.34'),
        ),
        findsOneWidget,
      );
      expect(
        workspace.payees.all.any((p) => p.name == 'Unsaved Payee'),
        isFalse,
      );
      await tap(find.byKey(const ValueKey('design-close')));
      await tap(find.text('Discard'));
      await tap(find.byKey(const ValueKey('design-open-form')));
      expect(selector('Funding Bank Account').value, anyOf(isNull, ''));
      expect(field('Cheque Number'), findsNothing);
      expect(find.text('CHEQUE-1'), findsNothing);
      await tap(find.byKey(const ValueKey('design-close')));
      expect(tester.takeException(), isNull);
    });
  }
  for (final width in [720.0, 1224.0]) {
    testWidgets('actual Cheque bank caller restricts accounts at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      installFixedPopoutHost(tester);
      await loadJournalLayoutFonts();
      final workspace = await createDemoWorkspace();
      addTearDown(workspace.dispose);
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('workspace-capture'),
          child: AudytApp(workspace: workspace, showInitialSetup: false),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> tap(Finder target) async {
        await tester.ensureVisible(target);
        await tester.tap(target);
        await tester.pumpAndSettle();
      }

      await tap(find.byKey(const ValueKey('navigation-item-banking')));
      await tap(find.text('Cheques').first);
      await tap(find.byKey(const ValueKey('design-open-form')));
      final bankField = find.byKey(const ValueKey('design-field-Bank Account'));
      final bank = tester.widget<AccountingSelector<String>>(
        find.byWidgetPredicate(
          (widget) =>
              widget is AccountingSelector<String> &&
              widget.triggerKey == const ValueKey('design-field-Bank Account'),
        ),
      );
      expect(bank.options.first.label, 'Add Account');
      expect(
        bank.options
            .where((option) => option.onPressed == null)
            .map((option) => option.label),
        ['Demo Bank', 'Demo Savings'],
      );
      expect(find.byType(AccountingTransactionGrid), findsNothing);
      expect(
        find.byKey(const ValueKey('design-field-Direction')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('design-field-Cheque Status')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('design-field-Cheque Date')),
        findsOneWidget,
      );
      await captureUi(tester, 'Cheque Bank Caller Empty ${width.toInt()}');
      expect(
        find.text('Track physical cheques and link their payments.'),
        findsOneWidget,
      );
      final statusHelp = find.byWidgetPredicate(
        (widget) =>
            widget is AccountingFieldHelp && widget.label == 'Cheque Status',
      );
      final statusMessage = tester
          .widget<AccountingFieldHelp>(statusHelp)
          .message;
      expect(find.text(statusMessage), findsNothing);
      await tap(statusHelp);
      expect(find.text(statusMessage), findsOneWidget);
      await captureUi(tester, 'Cheque Status Field Helper ${width.toInt()}');
      Tooltip.dismissAllToolTips();
      await tester.pumpAndSettle();
      expect(find.text(statusMessage), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('design-field-Cheque Number')),
        'INSPECTION-1',
      );
      await tap(bankField);
      await tap(find.text('Demo Bank').last);
      expect(find.textContaining('Balance:'), findsOneWidget);
      await tap(bankField);
      await tap(find.text('Add Account').last);
      final type = tester.widget<AccountingSelector<ReportingAccountType>>(
        find.byWidgetPredicate(
          (widget) => widget is AccountingSelector<ReportingAccountType>,
        ),
      );
      expect(type.options.map((option) => option.value), [
        ReportingAccountType.cashAndCashEquivalents,
      ]);
      await captureUi(tester, 'Cheque Canonical Bank Account ${width.toInt()}');
      await tester.enterText(
        find.byKey(const ValueKey('ledger-account-name')),
        'Unsaved Bank',
      );
      await tap(find.byKey(const ValueKey('ledger-account-close')));
      await tap(find.text('Keep Editing'));
      expect(find.text('Unsaved Bank'), findsOneWidget);
      await tap(find.byKey(const ValueKey('ledger-account-close')));
      await tap(find.text('Discard'));
      expect(find.text('INSPECTION-1'), findsOneWidget);
      expect(find.text('Demo Bank'), findsOneWidget);
      await captureUi(tester, 'Cheque Parent Retained ${width.toInt()}');
      await tap(find.byKey(const ValueKey('design-close')));
      await tap(find.text('Discard'));
      await tap(find.byKey(const ValueKey('design-open-form')));
      expect(find.text('INSPECTION-1'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  for (final width in [720.0, 1224.0]) {
    testWidgets('actual Banking Deposit funds and nested callers at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      installFixedPopoutHost(tester);
      await loadJournalLayoutFonts();
      final directory = Directory.systemTemp.createTempSync('deposit-design-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final workspace = await createDemoWorkspace(
        databasePath: '${directory.path}/ledger.sqlite',
      );
      addTearDown(workspace.dispose);
      workspace.saveTaxRate(
        CompanyTaxRate(
          id: EntityId.random(),
          name: 'Demo Deposit Tax',
          percent: '6',
          effectiveFrom: DateTime(2020),
          application: TaxApplication.sales,
          accountId: (await workspace.accounts())
              .map((record) => record.account)
              .firstWhere((a) => a.type == AccountType.liability && !a.isParent)
              .id,
        ),
      );
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('workspace-capture'),
          child: AudytApp(workspace: workspace, showInitialSetup: false),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> tap(Finder target) async {
        await tester.ensureVisible(target);
        await tester.tap(target);
        await tester.pumpAndSettle();
      }

      Finder input(String label) => find.byKey(ValueKey('design-field-$label'));
      Finder lineSelector(String field) => find.byWidgetPredicate(
        (widget) =>
            widget is AccountingSelector<String> &&
            '${widget.triggerKey}'.contains('-$field') &&
            !'${widget.triggerKey}'.contains('design-field'),
      );
      Future<void> choose(String label, String choice) async {
        await tap(input(label));
        await tap(find.text(choice).last);
      }

      await tap(find.byKey(const ValueKey('navigation-item-banking')));
      await tap(find.text('Deposits').first);
      await tap(find.byKey(const ValueKey('design-open-form')));
      expect(find.byType(AccountingTransactionGrid), findsOneWidget);
      expect(input('Amount'), findsNothing);
      expect(find.text('0.00'), findsWidgets);
      final account = tester.widget<AccountingSelector<String>>(
        find.byWidgetPredicate(
          (widget) =>
              widget is AccountingSelector<String> &&
              widget.triggerKey ==
                  const ValueKey('design-field-Deposit Account'),
        ),
      );
      expect(account.options.first.label, 'Add Account');
      await captureUi(tester, 'Deposit Actual Owner Empty ${width.toInt()}');
      await choose('Deposit Account', 'Demo Bank');
      expect(find.textContaining('Balance:'), findsOneWidget);
      await tap(input('Deposit Account'));
      await tap(find.text('Add Account').last);
      final type = tester.widget<AccountingSelector<ReportingAccountType>>(
        find.byWidgetPredicate(
          (widget) => widget is AccountingSelector<ReportingAccountType>,
        ),
      );
      expect(type.options.map((option) => option.value), [
        ReportingAccountType.cashAndCashEquivalents,
      ]);
      await captureUi(
        tester,
        'Deposit Canonical Bank Account ${width.toInt()}',
      );
      await tap(find.byKey(const ValueKey('ledger-account-close')));
      await tap(lineSelector('Account').first);
      await tap(find.text('Add Account').last);
      expect(
        tester
            .widget<AccountingSelector<ReportingAccountType>>(
              find.byWidgetPredicate(
                (widget) => widget is AccountingSelector<ReportingAccountType>,
              ),
            )
            .options
            .length,
        15,
      );
      final detailRect = tester.getRect(
        find.byKey(const ValueKey('ledger-detail-type')),
      );
      final taxRect = tester.getRect(
        find.byKey(const ValueKey('ledger-default-tax')),
      );
      expect(taxRect.top, greaterThanOrEqualTo(detailRect.top));
      expect(
        taxRect.width,
        lessThanOrEqualTo(AccountingPopoutTokens.normalContentWidth / 2),
      );
      if ((taxRect.top - detailRect.top).abs() < .5) {
        expect(taxRect.left, greaterThan(detailRect.right));
      } else {
        expect(
          taxRect.left,
          closeTo(
            tester
                .getRect(find.byKey(const ValueKey('ledger-account-code')))
                .left,
            .5,
          ),
        );
      }
      await captureUi(
        tester,
        'Deposit Canonical Line Account ${width.toInt()}',
      );
      await tap(find.byKey(const ValueKey('ledger-account-close')));
      await tap(lineSelector('Received From').first);
      await tap(find.text('Add Customer').last);
      expect(find.text('Customers'), findsWidgets);
      await captureUi(
        tester,
        'Deposit Canonical Received From ${width.toInt()}',
      );
      await tap(find.byKey(const ValueKey('design-close')).last);
      await tap(lineSelector('Payment Method').first);
      await tap(find.text('Add Payment Method').last);
      expect(find.text('New Payment Method'), findsOneWidget);
      expect(find.byType(AccountingLeadingCheckbox), findsOneWidget);
      await tester.enterText(input('Name'), 'Inspection Method');
      await tap(input('This Is A Credit Card'));
      await captureUi(tester, 'Deposit New Payment Method ${width.toInt()}');
      await tap(find.byKey(const ValueKey('design-close')).last);
      await tap(find.text('Keep Editing'));
      expect(find.text('Inspection Method'), findsOneWidget);
      await tap(find.byKey(const ValueKey('design-close')).last);
      await tap(find.text('Discard'));
      expect(find.text('New Payment Method'), findsNothing);
      // Read the stable line ID from the actual grid selector, not its position.
      String lineId(int row) =>
          (tester
                      .widget<AccountingSelector<String>>(
                        lineSelector('Account').at(row),
                      )
                      .triggerKey
                  as ValueKey<String>)
              .value
              .replaceFirst(RegExp(r'-Account$'), '');
      Finder amount(int row) => find.byWidgetPredicate(
        (widget) =>
            widget is TextFormField &&
            widget.key is ValueKey<String> &&
            (widget.key as ValueKey<String>).value.startsWith(
              '${lineId(row)}-',
            ) &&
            (widget.key as ValueKey<String>).value.endsWith('-Amount'),
      );
      await tester.ensureVisible(amount(0));
      await tester.enterText(amount(0), '100.00');
      await tester.pumpAndSettle();
      await tap(find.byKey(const ValueKey('design-add-line')));
      expect(lineSelector('Account'), findsNWidgets(2));
      await tester.ensureVisible(amount(1));
      await tester.enterText(amount(1), '25.00');
      await tester.pumpAndSettle();
      await tester.enterText(input('Cash Back Amount'), '10.00');
      await tester.pumpAndSettle();
      expect(find.text('115.00'), findsOneWidget);
      expect(
        tester.getRect(input('Tax Mode')).top,
        closeTo(tester.getRect(input('Make Recurring')).top, .1),
      );
      await captureUi(tester, 'Deposit Funds And Cash Back ${width.toInt()}');
      await tap(input('Cash Back Account'));
      await tap(find.text('Add Account').last);
      expect(
        tester
            .widget<AccountingSelector<ReportingAccountType>>(
              find.byWidgetPredicate(
                (widget) => widget is AccountingSelector<ReportingAccountType>,
              ),
            )
            .options
            .length,
        5,
      );
      await captureUi(
        tester,
        'Deposit Canonical Cash Back Account ${width.toInt()}',
      );
      await tap(find.byKey(const ValueKey('ledger-account-close')));
      expect(find.text('115.00'), findsOneWidget);
      await tester.enterText(input('Cash Back Amount'), '126.00');
      await tester.pumpAndSettle();
      expect(find.text('-1.00'), findsOneWidget);
      await captureUi(
        tester,
        'Deposit Cash Back Exceeds Funds ${width.toInt()}',
      );
      await tester.enterText(input('Cash Back Amount'), '10.00');
      await tester.pumpAndSettle();
      await tap(find.byKey(const ValueKey('design-remove-line-1')));
      expect(lineSelector('Account'), findsOneWidget);
      expect(find.text('90.00'), findsOneWidget);
      await tap(lineSelector('Tax Rate (%)').first);
      await tap(find.text('Demo Deposit Tax · 6%').last);
      expect(find.text('96.00'), findsOneWidget);
      await captureUi(
        tester,
        'Deposit Tax Exclusive Cash Back ${width.toInt()}',
      );
      await choose('Tax Mode', 'Tax Inclusive');
      expect(tester.widget<TextFormField>(amount(0)).initialValue, '106.00');
      expect(find.text('96.00'), findsOneWidget);
      await captureUi(
        tester,
        'Deposit Tax Inclusive Cash Back ${width.toInt()}',
      );
      await choose('Tax Mode', 'Tax Exclusive');
      expect(tester.widget<TextFormField>(amount(0)).initialValue, '100.00');
      expect(find.text('96.00'), findsOneWidget);
      await choose('Tax Mode', 'Out Of Scope');
      expect(lineSelector('Tax Rate (%)'), findsNothing);
      expect(tester.widget<TextFormField>(amount(0)).initialValue, '100.00');
      expect(find.text('90.00'), findsOneWidget);
      await captureUi(tester, 'Deposit Out Of Scope ${width.toInt()}');
      await choose('Tax Mode', 'Tax Exclusive');
      expect(
        tester
            .widget<AccountingSelector<String>>(
              lineSelector('Tax Rate (%)').first,
            )
            .value,
        isEmpty,
      );
      await captureUi(
        tester,
        'Deposit Tax Choice Required Again ${width.toInt()}',
      );
      await tap(lineSelector('Tax Rate (%)').first);
      await tap(find.text('No Tax').last);
      expect(find.text('90.00'), findsOneWidget);
      await choose('Make Recurring', 'Scheduled');
      expect(input('Template Name'), findsOneWidget);
      expect(input('Days In Advance'), findsOneWidget);
      await tester.enterText(input('Template Name'), 'Bank Deposit Schedule');
      await tester.pumpAndSettle();
      await captureUi(tester, 'Deposit Scheduled Monthly ${width.toInt()}');
      await choose('Make Recurring', 'Unscheduled');
      expect(input('Start Date'), findsNothing);
      expect(input('Template Name'), findsOneWidget);
      expect(find.text('Bank Deposit Schedule'), findsOneWidget);
      await captureUi(tester, 'Deposit Unscheduled Retained ${width.toInt()}');
      await tap(find.byKey(const ValueKey('design-close')));
      expect(find.text('Discard Unsaved Changes?'), findsOneWidget);
      await tap(find.text('Keep Editing'));
      expect(tester.widget<TextFormField>(amount(0)).initialValue, '100.00');
      await tap(find.byKey(const ValueKey('design-close')));
      await tap(find.text('Discard'));
      expect(find.byType(FrontendFormDialog), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  for (final width in [720.0, 1224.0]) {
    testWidgets(
      'actual Banking Transfer recurrence and nested account at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        installFixedPopoutHost(tester);
        await loadJournalLayoutFonts();
        final directory = Directory.systemTemp.createTempSync(
          'transfer-design-',
        );
        addTearDown(() => directory.deleteSync(recursive: true));
        final workspace = await createDemoWorkspace(
          databasePath: '${directory.path}/ledger.sqlite',
        );
        addTearDown(workspace.dispose);
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: AudytApp(workspace: workspace, showInitialSetup: false),
          ),
        );
        await tester.pumpAndSettle();
        Future<void> tap(Finder target) async {
          await tester.ensureVisible(target);
          await tester.tap(target);
          await tester.pumpAndSettle();
        }

        Finder input(String label) =>
            find.byKey(ValueKey('design-field-$label'));
        Future<void> choose(String label, String choice) async {
          await tap(input(label));
          await tap(find.text(choice).last);
        }

        await tap(find.byKey(const ValueKey('navigation-item-banking')));
        await tap(find.text('Transfers').first);
        await tap(find.byKey(const ValueKey('design-open-form')));
        Finder selector(String label) => find.byWidgetPredicate(
          (widget) =>
              widget is AccountingSelector<String> &&
              widget.triggerKey == ValueKey('design-field-$label'),
        );
        final from = tester.widget<AccountingSelector<String>>(
          selector('From Account'),
        );
        expect(from.options.first.label, 'Add Account');
        expect(from.options.any((option) => option.label == 'Rent'), isFalse);
        await captureUi(tester, 'Transfer Actual Owner Empty ${width.toInt()}');
        await choose('From Account', 'Demo Bank');
        expect(find.textContaining('Balance:'), findsOneWidget);
        await tester.enterText(input('Amount'), '1234567.89');
        await tester.pumpAndSettle();
        await tap(input('To Account'));
        await tap(find.text('Add Account').last);
        expect(
          find.byKey(const ValueKey('ledger-account-code')),
          findsOneWidget,
        );
        await captureUi(
          tester,
          'Transfer Canonical Add Account ${width.toInt()}',
        );
        final accountType = tester
            .widget<AccountingSelector<ReportingAccountType>>(
              find.byWidgetPredicate(
                (widget) => widget is AccountingSelector<ReportingAccountType>,
              ),
            );
        expect(accountType.options.length, 8);
        expect(
          accountType.options.any(
            (option) => option.value == ReportingAccountType.income,
          ),
          isFalse,
        );
        await tap(find.byKey(const ValueKey('ledger-account-type')));
        await captureUi(
          tester,
          'Transfer Add Account Type Menu ${width.toInt()}',
        );
        await tester.ensureVisible(find.textContaining('Equity').last);
        await tester.pumpAndSettle();
        await captureUi(
          tester,
          'Transfer Add Account Last Type ${width.toInt()}',
        );
        await tap(find.text('Current Assets').last);

        await tap(find.byKey(const ValueKey('ledger-account-close')));
        expect(find.text('Discard Unsaved Changes?'), findsOneWidget);
        await captureUi(
          tester,
          'Transfer Nested Account Discard ${width.toInt()}',
        );
        await tap(find.text('Discard').last);
        expect(find.text('1,234,567.89'), findsOneWidget);
        await choose('Make Recurring', 'Scheduled');
        expect(input('Template Name'), findsOneWidget);
        expect(input('Days In Advance'), findsOneWidget);
        expect(input('Days Before'), findsNothing);
        await tester.enterText(input('Template Name'), 'Bank Movement');
        await tester.enterText(input('Days In Advance'), '2');
        await tester.enterText(input('Start Date'), '01-11-2026');
        await choose('End', 'After');
        expect(input('Occurrences'), findsOneWidget);
        expect(input('End Date'), findsNothing);
        final day = tester.widget<AccountingSelector<String>>(
          selector('Day Of Month'),
        );
        expect(day.options.last.label, 'Last');
        expect(day.options.any((option) => option.label == '29'), isFalse);
        await tester.enterText(input('Occurrences'), '6');
        await tester.ensureVisible(input('Make Recurring'));
        await tester.pumpAndSettle();
        await captureUi(tester, 'Transfer Scheduled Monthly ${width.toInt()}');
        await choose('Make Recurring', 'Reminder');
        expect(input('Days In Advance'), findsNothing);
        expect(input('Days Before'), findsOneWidget);
        await choose('Interval', 'Weekly');
        expect(input('Day Of Week'), findsOneWidget);
        expect(input('Week Of Month'), findsNothing);
        await captureUi(tester, 'Transfer Reminder Weekly ${width.toInt()}');
        await choose('Make Recurring', 'Unscheduled');
        expect(input('Template Name'), findsOneWidget);
        for (final label in [
          'Interval',
          'Every',
          'Start Date',
          'End',
          'Days Before',
          'Occurrences',
        ]) {
          expect(input(label), findsNothing);
        }
        await captureUi(tester, 'Transfer Unscheduled ${width.toInt()}');
        await choose('Make Recurring', 'Scheduled');
        await choose('Interval', 'Yearly');
        expect(input('Every'), findsNothing);
        expect(input('Month Of Year'), findsOneWidget);
        await choose('End', 'By');
        expect(input('End Date'), findsOneWidget);
        expect(input('Occurrences'), findsNothing);
        await captureUi(tester, 'Transfer Yearly End Date ${width.toInt()}');
        await choose('Interval', 'Daily');
        expect(input('Every'), findsOneWidget);
        expect(input('Month Of Year'), findsNothing);
        await choose('End', 'None');
        expect(input('End Date'), findsNothing);
        await captureUi(tester, 'Transfer Daily No End ${width.toInt()}');
        await choose('Interval', 'Monthly');
        await choose('Week Of Month', 'First');
        expect(input('Day Of Week'), findsOneWidget);
        expect(input('Day Of Month'), findsNothing);
        await captureUi(tester, 'Transfer Monthly Weekday ${width.toInt()}');

        expect(find.text('Bank Movement'), findsOneWidget);
        expect(find.text('01-11-2026'), findsOneWidget);
        await tester.enterText(input('Amount'), '125.00');
        await tester.pumpAndSettle();
        await tester.ensureVisible(input('Make Recurring'));
        await tester.pumpAndSettle();
        await captureUi(tester, 'Transfer Scheduled Retained ${width.toInt()}');
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final width in [720.0, 1224.0]) {
    for (final title in [
      'Sales Receipts',
      'Purchase Orders',
      'Supplier Credits',
    ]) {
      testWidgets('empty $title totals use monetary zero at $width', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(Size(width, 1100));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final form = frontendAreas.values
            .expand((forms) => forms)
            .firstWhere((form) => form.title == title);
        await loadJournalLayoutFonts();
        await openForm(tester, form);
        for (final row in ['subtotal', 'tax', 'total']) {
          final summary = find.byKey(ValueKey('design-line-$row'));
          await tester.ensureVisible(summary);
          await tester.pumpAndSettle();
          expect(
            find.descendant(of: summary, matching: find.text('0.00')),
            findsOneWidget,
          );
          expect(
            find.descendant(of: summary, matching: find.text('—')),
            findsNothing,
          );
        }
        final memoSummary = find.byType(AccountingMemoSummary);
        final summaryOwner = tester.widget<AccountingMemoSummary>(memoSummary);
        final firstLabel = find.descendant(
          of: memoSummary,
          matching: find.text(summaryOwner.rows.first.$1),
        );
        final memoLabel = find.descendant(
          of: memoSummary,
          matching: find.text(summaryOwner.memoLabel),
        );
        expect(
          await paintedTextTop(tester, tester.getRect(firstLabel)),
          closeTo(await paintedTextTop(tester, tester.getRect(memoLabel)), 1),
          reason: 'The painted first total aligns with the painted title',
        );
        await captureUi(
          tester,
          '$title Empty Monetary Totals ${width.toInt()}',
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
    'transaction routes retain paired identity fields and shared memo summary',
    (tester) async {
      tester.view.physicalSize = const Size(1224, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await (FontLoader(
        'Inter',
      )..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2'))).load();
      for (final form in [
        frontendAreas['sales-customers']!.first,
        frontendAreas['expenses-vendors']!.first,
      ]) {
        await openForm(tester, form);
        final customer = tester.getRect(
          find.byKey(const ValueKey('design-field-Counterparty')),
        );
        final document = tester.getRect(
          find.byKey(const ValueKey('design-field-Document Number')),
        );
        final memo = tester.getRect(
          find.byKey(const ValueKey('design-field-Memo')),
        );
        expect(customer.top, document.top);
        expect(document.width, customer.width);
        expect(document.left - customer.right, 20);
        expect(memo.left, customer.left);
        expect(find.byType(AccountingMemoSummary), findsOneWidget);
        final summary = tester.getRect(
          find.byType(AccountingTransactionSummary),
        );
        final grid = tester.getRect(find.byType(AccountingTransactionGrid));
        expect(summary.right, closeTo(grid.right, 0.1));
        expect(summary.left - memo.right, closeTo(20, 0.1));
        expect(memo.width, greaterThan(180));
        tester.state<NavigatorState>(find.byType(Navigator)).pop();
        await tester.pumpAndSettle();
      }
    },
  );

  for (final width in [720.0, 1224.0]) {
    testWidgets(
      'purchase order retains its filled date and terms-controlled timing at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        await (FontLoader('Inter')
              ..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2')))
            .load();
        final form = frontendAreas['expenses-vendors']!.singleWhere(
          (form) => form.title == 'Purchase Orders',
        );
        await openForm(tester, form);

        final date = tester.widget<TextFormField>(
          find.byKey(const ValueKey('design-field-Date')),
        );
        expect(date.controller!.text, matches(RegExp(r'^\d{2}-\d{2}-\d{4}$')));
        final originalDate = date.controller!.text;
        expectHeaderChoicesReadable(tester);
        expect(
          find.byKey(const ValueKey('design-field-Due Date')),
          findsNothing,
        );
        await captureUi(
          tester,
          'Purchase Order Default Timing ${width.toInt()}',
        );
        final terms = find.byKey(const ValueKey('design-field-Payment Terms'));
        await tester.ensureVisible(terms);
        await tester.tap(terms);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Days After Issue').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Days After Issue').last);
        await tester.pumpAndSettle();
        final days = find.byKey(const ValueKey('design-field-Number Of Days'));
        expect(days, findsOneWidget);
        await tester.enterText(days, '45');
        await tester.pumpAndSettle();
        expect(date.controller!.text, originalDate);
        expect(tester.widget<TextFormField>(days).controller!.text, '45');
        expectHeaderChoicesReadable(tester);
        await captureUi(
          tester,
          'Purchase Order Days After Issue ${width.toInt()}',
        );
        await tester.ensureVisible(terms);
        await tester.tap(terms);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Net 30').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Net 30').last);
        await tester.pumpAndSettle();
        expect(days, findsNothing);
        expect(date.controller!.text, originalDate);
        await captureUi(
          tester,
          'Purchase Order Restored Net 30 ${width.toInt()}',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  // 720px is the supported desktop minimum; 430px is only an extra stress check.
  for (final width in [1224.0, 720.0, 430.0]) {
    testWidgets('all frontend forms and selections render at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      installFixedPopoutHost(tester);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      if (Platform.environment['AUDYT_UI_CAPTURE_DIR'] != null) {
        await (FontLoader('Inter')
              ..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2')))
            .load();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
        await (FontLoader('Arial')..addFont(
              Future.value(
                ByteData.sublistView(
                  File('/System/Library/Fonts/Supplemental/Arial.ttf')
                      .readAsBytesSync(),
                ),
              ),
            ))
            .load();
      }
      for (final form in [
        ...settingsForms,
        ...frontendAreas.values.expand((forms) => forms),
      ]) {
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: MaterialApp(
              theme: AccountingTheme.light(),
              debugShowCheckedModeBanner: false,
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () {
                      Widget builder(BuildContext _) => FrontendFormDialog(
                        key: ValueKey(form.title),
                        form: form,
                        initial: const {"Tax Details Needed": true},
                      );
                      // Catalogue previews retain their form body; transaction
                      // previews also acquire the actual fixed-popout width owner.
                      if (form.lines) {
                        AccountingDialog.showFixed<void>(
                          context: context,
                          contentWidth: frontendTransactionContentWidth(
                            context,
                            form,
                          ),
                          builder: builder,
                        );
                      } else {
                        showDialog<void>(context: context, builder: builder);
                      }
                    },
                    child: const Text('Open Form'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open Form'));
        await tester.pumpAndSettle();
        expect(find.byType(FrontendFormDialog), findsOneWidget);
        expect(
          tester
              .widget<FrontendFormDialog>(find.byType(FrontendFormDialog))
              .form
              .title,
          form.title,
          reason: 'Each catalogue iteration must open its own form',
        );
        expect(tester.takeException(), isNull, reason: form.title);
        if ([
          'Business Profile',
          'Tax Settings',
          'Invoices',
          'Deadlines',
          'For Review',
        ].contains(form.title)) {
          await captureUi(tester, 'Frontend ${form.title} ${width.toInt()}');
        }
        final selectors = find
            .byType(AccountingSelector<String>)
            .evaluate()
            .map((element) => element.widget as AccountingSelector<String>)
            .where(
              (selector) =>
                  selector.triggerKey != null &&
                  selector.options.any((option) => option.enabled),
            )
            .toList();
        for (final selector in selectors) {
          final trigger = find.byKey(selector.triggerKey!);
          expect(
            trigger,
            findsOneWidget,
            reason: '${form.title}/${selector.triggerKey}',
          );
          await tester.ensureVisible(trigger);
          await tester.pumpAndSettle();
          await tester.tap(trigger);
          await tester.pumpAndSettle();
          final first = selector.options.firstWhere((option) => option.enabled);
          final optionLabel = first.label;
          final candidates = find.text(optionLabel);
          expect(
            candidates,
            findsWidgets,
            reason: '${form.title}/${selector.triggerKey}: $optionLabel',
          );
          final option = candidates.last;
          await tester.ensureVisible(option);
          await tester.pumpAndSettle();
          await tester.tap(option);
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: '${form.title}/${selector.triggerKey}',
          );
          final selected = find.byWidgetPredicate(
            (widget) =>
                widget is AccountingSelector<String> &&
                widget.triggerKey == selector.triggerKey,
          );
          expect(
            tester.widget<AccountingSelector<String>>(selected).value,
            first.value,
            reason: '${form.title}: selection must retain its ID',
          );
        }
        // The accepted popup uses its corner Close and guarded dismissal;
        // the former duplicated footer Cancel is no longer an entry point.
        await tester.tap(find.byKey(const ValueKey('design-close')));
        await tester.pumpAndSettle();
        if (find
            .byKey(const ValueKey('design-discard-changes'))
            .evaluate()
            .isNotEmpty) {
          await tester.tap(
            find.byKey(const ValueKey('design-discard-changes')),
          );
          await tester.pumpAndSettle();
        }
        expect(find.byType(FrontendFormDialog), findsNothing);
        expect(tester.takeException(), isNull, reason: form.title);
      }
    });
  }
}

class _CardPayeeDirectory extends PreviewUserDirectory {
  final queries = <String>[];
  @override
  Future<List<Payee>> findEmployeePayees(String search) async {
    queries.add(search);
    if (queries.length == 1) throw StateError('Inspection lookup failure');
    return search.isEmpty ||
            'Registered Employee'.toLowerCase().contains(search.toLowerCase())
        ? const [
            Payee(
              id: 'registered-employee-inspection',
              name: 'Registered Employee',
              type: PayeeType.staff,
            ),
          ]
        : const [];
  }
}
