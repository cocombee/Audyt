import 'package:audyt/app/pay_bills_proposal.dart';
import 'package:audyt/features/sales/product_catalogue_page.dart';
import 'package:audyt/features/sales/invoice_form.dart';
import 'package:audyt/features/sales/domain/invoice.dart';
import 'package:audyt/features/sales/domain/sales_line_item.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/sales/domain/product_catalogue.dart';
import 'package:audyt/app/accounting_description_field.dart';
import 'package:audyt/features/accounting/domain/payee.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/presentation/banking_page.dart';
import 'package:audyt/features/accounting/presentation/statement_reconciliation_dialog.dart';
import 'package:audyt/features/accounting/domain/bank_statement_import.dart';
import 'package:audyt/features/accounting/domain/payment_account.dart';

import 'package:audyt/app/local_profile.dart';
import 'package:audyt/app/google_account_session.dart';
import 'package:audyt/app/password_change_dialog.dart';
import 'package:audyt/app/users_page.dart';
import 'package:audyt/app/user_directory.dart';
import 'package:audyt/app/accounting_icons.dart';
import 'package:audyt/features/accounting/presentation/chart_of_accounts_page.dart';
import 'package:audyt/features/accounting/presentation/audit_log_dialog.dart';
import 'package:audyt/features/accounting/presentation/recurring_transactions_dialog.dart';
import 'package:audyt/features/accounting/presentation/customer_page.dart';
import 'package:audyt/features/purchases/presentation/vendors_page.dart';
import 'package:audyt/features/sales/invoice_credit_editor.dart';
import 'package:audyt/features/accounting/presentation/journal_workspace_page.dart';
import 'package:audyt/features/accounting/presentation/expense_recurrence_dialog.dart';
import 'package:audyt/features/accounting/presentation/payment_account_dialog.dart';
import 'package:audyt/app/naming_setup.dart';

// Isolated review gallery. Catalog entries are explicitly distinguished from live owners.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/field_row_trial.dart';
import 'package:audyt/app/frontend_review.dart';
import 'package:audyt/app/live_settings_catalog.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/accounting/presentation/record_expense_page.dart';
import 'package:audyt/features/accounting/presentation/tax_rates_page.dart';
import 'package:audyt/features/purchases/presentation/claims_page.dart';
import 'package:audyt/features/purchases/presentation/payment_vouchers_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixed_popout_host.dart';

void main() {
  test('trial equality, fitting and ordered minimum fallback', () {
    expect(trialRows(620, [130, 140, 130, 135]).single.widths, [
      140,
      140,
      140,
      140,
    ]);
    expect(trialRows(620, [160, 120, 110, 100]).single.widths, [
      177.5,
      137.5,
      127.5,
      117.5,
    ]);
    expect(trialRows(620, [280, 290]).single.widths, [300, 300]);
    expect(
      trialRows(620, [170, 180, 175]).single.widths,
      List.filled(3, 580 / 3),
    );
    expect(trialRows(619, [300, 300]).length, 2);
    expect(trialRows(620, [700]).single.mode, 'Does not fit');
    expect(trialRows(620, [130]).single.widths, [300]);
    expect(trialRows(620, [170]).single.widths, [300]);
    expect(trialRows(620, [250]).single.widths, [300]);
    expect(trialRows(620, [350]).single.widths, [620]);
    // Wrapped tails use their own row's usable space, not their original index.
    expect(trialRows(620, [250, 250, 120]).map((r) => r.widths).toList(), [
      [300, 300],
      [300],
    ]);
    expect(trialRows(620, [250, 250, 350]).map((r) => r.widths).toList(), [
      [300, 300],
      [620],
    ]);
    expect(trialRows(620, [250, 250, 150, 150]).map((r) => r.widths).toList(), [
      [300, 300],
      [300, 300],
    ]);
    expect(trialRows(400, [250, 250, 150, 150]).map((r) => r.widths).toList(), [
      [400],
      [400],
      [190, 190],
    ]);
    expect(
      trialRows(620, [170, 170, 110], preferEqual: true).single.widths,
      List.filled(3, 580 / 3),
    );
    expect(
      trialRows(620, [
        120,
        120,
        120,
        120,
        120,
      ], preferEqual: true).map((r) => r.widths.length),
      [3, 2],
    );
    // An opt-in never squeezes a control beneath its minimum.
    expect(
      trialRows(620, [230, 170, 110], preferEqual: true).single.mode,
      'Content fit',
    );
    expect(trialRows(620, [170, 170, 110]).single.mode, 'Content fit');
  });
  final output = Platform.environment['AUDYT_ROW_TRIAL_DIR'];
  if (output == null) return;
  Directory(output).createSync(recursive: true);
  final inventory = <Map<String, Object?>>[];
  var serial = 0;
  for (final width in [720.0, 1224.0]) {
    testWidgets('complete field-owner inventory at $width', (tester) async {
      tester.view.physicalSize = Size(width, 5200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      installFixedPopoutHost(tester);
      for (final font in [
        ('Inter', 'assets/fonts/Inter-Variable.woff2'),
        ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
      ]) {
        await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
      }
      // Register the established filename preview font for rendered evidence.
      final mono = File('/System/Library/Fonts/Menlo.ttc');
      await (FontLoader('monospace')..addFont(
            mono.existsSync()
                ? Future.value(ByteData.sublistView(mono.readAsBytesSync()))
                : rootBundle.load('assets/fonts/Inter-Variable.woff2'),
          ))
          .load();
      final w = await createDemoWorkspace(includeRowReview: true);
      addTearDown(w.dispose);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        namingSettingsChannel,
        (_) async => null,
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        LocalProfile.channel,
        (call) async => call.method == 'load'
            ? <String, String>{
                'name': 'Fictional User',
                'email': 'user@example.test',
              }
            : null,
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          namingSettingsChannel,
          null,
        );
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          LocalProfile.channel,
          null,
        );
      });
      Future<void> render(
        String category,
        String title,
        Widget? dialog, {
        void Function(BuildContext)? opener,
        DesignForm? form,
        Widget? ownerPage,
        List<Finder> entrypoints = const [],
        String? settingsSection,
        SetupKind? fileSetupKind,
        String note = 'Existing owner, locked layout',
      }) async {
        tester.view.physicalSize = Size(width, 5200);
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('trial-capture'),
            child: MaterialApp(
              key: UniqueKey(),
              debugShowCheckedModeBanner: false,
              theme: AccountingTheme.light(),
              home: Scaffold(
                body:
                    ownerPage ??
                    Builder(
                      builder: (context) => TextButton(
                        onPressed: () {
                          if (opener != null) {
                            opener(context);
                          } else {
                            showDialog<void>(
                              context: context,
                              builder: (_) => dialog!,
                            );
                          }
                        },
                        child: const Text('Open'),
                      ),
                    ),
              ),
            ),
          ),
        );
        if (ownerPage == null) {
          await tester.tap(find.text('Open'));
        } else {
          await tester.pumpAndSettle();
          for (final entrypoint in entrypoints) {
            await tester.ensureVisible(entrypoint);
            await tester.tap(entrypoint);
            await tester.pumpAndSettle();
          }
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$title at $width');
        if (const [
          'Bills',
          'Supplier Credits',
          'Purchase Orders',
        ].contains(title)) {
          expect(
            find.byKey(const ValueKey('design-field-Tax Mode')),
            findsOneWidget,
            reason: 'One document-wide Amounts Are owner at $width',
          );
        }
        if (settingsSection != null || fileSetupKind != null) {
          final section = find.byKey(
            ValueKey(
              settingsSection != null
                  ? 'settings-editor-$settingsSection'
                  : 'settings-section-${fileSetupKind!.id}',
            ),
          );
          await tester.ensureVisible(section);
          await tester.tap(
            find
                .descendant(of: section, matching: find.byType(ExpansionTile))
                .first,
          );
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: '$title expanded at $width',
          );
          if (settingsSection != null &&
              liveSettingsForms({})
                  .any((form) => form.title == settingsSection)) {
            final form = tester.widget<FrontendFormDialog>(
              find.descendant(
                of: section,
                matching: find.byType(FrontendFormDialog),
              ),
            );
            expect(
              form.fieldLayoutOwner,
              AccountingFieldLayoutOwner.sharedPopup,
            );
          }
        }
        if (const [
          'Add Claimant',
          'Add Merchant',
          'Add Payee',
        ].contains(title)) {
          final addKey = title == 'Add Payee'
              ? 'voucher-add-payee'
              : title == 'Add Claimant'
              ? 'claim-add-claimant'
              : 'claim-add-merchant';
          final searchKey = title == 'Add Payee'
              ? 'voucher-payee'
              : title == 'Add Claimant'
              ? 'claim-claimant'
              : 'claim-payee';
          await tester.ensureVisible(find.byKey(ValueKey(searchKey)));
          await tester.enterText(find.byKey(ValueKey(searchKey)), 'new');
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.byKey(ValueKey(addKey)));
          await tester.tap(find.byKey(ValueKey(addKey)));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final key = title == 'Add Payee'
              ? 'voucher-add-payee-name'
              : title == 'Add Claimant'
              ? 'claim-add-claimant-name'
              : 'claim-add-merchant-name';
          final frame = tester.getRect(find.byKey(ValueKey(key)));
          expect(frame.width, closeTo(232, .01));
          expect(find.byType(AccountingOrdinaryFields), findsWidgets);
          if (title != 'Add Payee') {
            final type = tester.getRect(
              find.byKey(const ValueKey('claim-add-payee-type')),
            );
            expect(type.width, closeTo(frame.width, .01));
            expect(type.left, frame.left);
            expect(type.top, greaterThan(frame.bottom));
          }
          await tester.enterText(find.byKey(ValueKey(key)), 'Fictional Payee');
          await tester.pumpAndSettle();
          expect(find.text('Fictional Payee'), findsOneWidget);
        }
        if (title == 'Prepare Closing') {
          final date = tester.getRect(
            find.byKey(const ValueKey('closing-date-frame')),
          );
          final account = tester.getRect(
            find.byKey(const ValueKey('closing-equity')),
          );
          expect(date.width, 320);
          expect(account.width, date.width);
          expect(account.left, date.left);
          expect(account.top, greaterThan(date.bottom));
          expect(find.byType(AccountingOrdinaryFields), findsOneWidget);
        }
        if (title == 'Link Ledger Account') {
          final selector = tester.getRect(
            find.byKey(const ValueKey('banking-ledger-selector')),
          );
          expect(selector.width, 460);
          expect(find.byType(AccountingOrdinaryFields), findsOneWidget);
          expect(
            find.byKey(const ValueKey('banking-confirm-link')),
            findsOneWidget,
          );
        }
        if (title == 'Claim') {
          final amount = tester.getRect(
            find.byKey(const ValueKey('claim-amount')),
          );
          final date = tester.getRect(find.byKey(const ValueKey('claim-date')));
          expect(date.top, amount.top);
          expect(date.width, greaterThan(0));
          expect(amount.width, greaterThan(0));
          expect(find.byType(AccountingOrdinaryFields), findsWidgets);
          final claimant = tester.getRect(
            find.byKey(const ValueKey('claim-claimant')),
          );
          final merchant = tester.getRect(
            find.byKey(const ValueKey('claim-payee')),
          );
          final category = tester.getRect(
            find.byKey(const ValueKey('claim-category')),
          );
          expect(claimant.top, closeTo(category.top, .01));
          expect(claimant.width, closeTo(category.width, .01));
          expect(merchant.top, greaterThan(claimant.bottom));
          expect(merchant.top, closeTo(date.top, .01));
          final input = tester.widget<TextField>(
            find.descendant(
              of: find.byKey(const ValueKey('claim-amount')),
              matching: find.byType(TextField),
            ),
          );
          expect(input.decoration!.prefixIcon, isNull);
          expect(
            find.byKey(const ValueKey('claim-label-amount-rm')),
            findsOneWidget,
          );
          expect(claimant.width, greaterThan(0));
          expect(merchant.width, greaterThan(0));
          expect(
            find.byKey(const ValueKey('claim-add-claimant')),
            findsNothing,
          );
          expect(
            find.byKey(const ValueKey('claim-add-merchant')),
            findsNothing,
          );
        }
        if (title == 'Payment Voucher') {
          final amount = tester.getRect(
            find.byKey(const ValueKey('voucher-amount')),
          );
          final date = tester.getRect(
            find.byKey(const ValueKey('voucher-date')),
          );
          expect(date.top, amount.top);
          expect(date.width, amount.width);
          expect(find.byType(AccountingOrdinaryFields), findsNWidgets(2));
        }
        if (title == 'Edit Profile') {
          final name = tester.getRect(
            find.byKey(const ValueKey('profile-name')),
          );
          final email = tester.getRect(
            find.byKey(const ValueKey('profile-email')),
          );
          final phone = tester.getRect(
            find.byKey(const ValueKey('profile-phone')),
          );
          expect(email.top, name.top);
          expect(phone.top, name.top);
          final owner = find.byType(AccountingOrdinaryFields);
          final fields = tester.widget<AccountingOrdinaryFields>(owner).fields;
          final minima = [
            for (final field in fields.take(3))
              field.minimumWidth(tester.element(owner)),
          ];
          final frames = [name, email, phone];
          final equal = frames.every(
            (frame) => (frame.width - frames.first.width).abs() < .01,
          );
          for (var i = 0; i < frames.length; i++) {
            expect(frames[i].width, greaterThanOrEqualTo(minima[i]));
            expect(
              equal ? frames[i].width : frames[i].width - minima[i],
              closeTo(
                equal ? frames.first.width : frames.first.width - minima.first,
                .01,
              ),
            );
          }
        }
        if (title == 'New Ledger Account') {
          final code = tester.getRect(
            find.byKey(const ValueKey('ledger-account-code')),
          );
          final name = tester.getRect(
            find.byKey(const ValueKey('ledger-account-name')),
          );
          expect(name.top, code.top);
          expect(name.left - code.right, closeTo(20, .01));
          expect(name.width, greaterThanOrEqualTo(code.width));
          expect(find.byType(AccountingOrdinaryFields), findsOneWidget);
          final ledgerRow = tester.getRect(
            find.byType(AccountingOrdinaryFields),
          );
          expect(name.width, greaterThanOrEqualTo((ledgerRow.width - 20) / 2));
        }
        if (title == 'Payment Account') {
          await tester.tap(find.byKey(const ValueKey('payment-account-bank')));
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('payment-account-bank-option-maybank')),
          );
          await tester.pumpAndSettle();
          expect(find.byType(AccountingOrdinaryFields), findsOneWidget);
          final number = tester.getRect(
            find.byKey(const ValueKey('payment-account-number')),
          );
          final holder = tester.getRect(
            find.byKey(const ValueKey('payment-account-holder')),
          );
          final name = tester.getRect(
            find.byKey(const ValueKey('payment-account-name')),
          );
          expect(holder.top, greaterThanOrEqualTo(number.top));
          expect(name.top, greaterThanOrEqualTo(holder.top));
          final owner = find.byType(AccountingOrdinaryFields);
          final slots = tester
              .widget<AccountingOrdinaryFields>(owner)
              .fields
              .skip(3)
              .toList();
          final context = tester.element(owner);
          final frames = [number, holder, name];
          final minima = [for (final slot in slots) slot.minimumWidth(context)];
          for (var i = 0; i < frames.length; i++) {
            expect(frames[i].width, greaterThanOrEqualTo(minima[i]));
            final peers = [
              for (var j = 0; j < frames.length; j++)
                if ((frames[j].top - frames[i].top).abs() < .01) j,
            ];
            for (final j in peers) {
              if ((frames[j].width - frames[i].width).abs() >= .01) {
                expect(
                  frames[j].width - minima[j],
                  closeTo(frames[i].width - minima[i], .01),
                );
              }
            }
          }
          final row = tester.getRect(owner);
          for (final frame in frames) {
            expect(frame.left, greaterThanOrEqualTo(row.left));
            expect(frame.right, lessThanOrEqualTo(row.right + .01));
          }
          expect(holder.width, greaterThanOrEqualTo((row.width - 20) / 2));
          expect(name.width, greaterThanOrEqualTo((row.width - 20) / 2));
          expect(tester.takeException(), isNull);
        }

        if (title == 'Statement Reconciliation') {
          final start = tester.getRect(
            find.byKey(const ValueKey('reconciliation-start')),
          );
          final end = tester.getRect(
            find.byKey(const ValueKey('reconciliation-end')),
          );
          expect(end.top, start.top);
          expect(end.width, closeTo(start.width, .01));
          expect(end.left - start.right, closeTo(20, .01));
          // Money geometry keeps its existing stacked owner at this 480px width.
          final opening = tester.getRect(
            find.byKey(const ValueKey('reconciliation-opening')),
          );
          final closing = tester.getRect(
            find.byKey(const ValueKey('reconciliation-closing')),
          );
          expect(opening.width, greaterThan(start.width * 2));
          expect(closing.top, greaterThan(opening.top));
          expect(closing.width, opening.width);
        }
        if (title == 'Change Employee Role' ||
            title == 'Approve Employee Role') {
          expect(find.byType(AccountingOrdinaryFields), findsOneWidget);
          final selector = tester.getRect(
            find.byKey(const ValueKey('user-role-selector')),
          );
          expect(selector.width, closeTo(400, .01));
          expect(
            find.byKey(const ValueKey('accounting-form-dialog-footer')),
            findsOneWidget,
          );
        }
        if (title == 'Receive Payment') {
          expect(find.text('Amount Received (RM)'), findsOneWidget);
          for (final old in [
            'Amount Applied to Document',
            'Credit To Apply',
            'Payment Not Applied',
          ]) {
            expect(find.byKey(ValueKey('design-field-$old')), findsNothing);
          }
          expect(
            tester
                .widget<TextField>(
                  find.descendant(
                    of: find.byKey(const ValueKey('design-field-Amount')),
                    matching: find.byType(TextField),
                  ),
                )
                .decoration!
                .prefixIcon,
            isNull,
          );
          expect(find.text('250.00'), findsOneWidget);
          await tester.enterText(
            find.byKey(const ValueKey('design-field-Amount')),
            '400.00',
          );
          await tester.pumpAndSettle();
          expect(find.text('Check Amounts'), findsNWidgets(3));
          await tester.enterText(
            find.byKey(const ValueKey('design-field-Amount')),
            '750.00',
          );
          await tester.pumpAndSettle();
          await tester.ensureVisible(
            find.byKey(const ValueKey('receipt-select-credit')),
          );
          await tester.tap(find.byKey(const ValueKey('receipt-select-credit')));
          await tester.pumpAndSettle();
          expect(find.text('100.00'), findsOneWidget);
          expect(find.text('250.00'), findsOneWidget);
          await tester.tap(find.byKey(const ValueKey('receipt-select-credit')));
          await tester.pumpAndSettle();
          final date = tester.getRect(
            find.byKey(const ValueKey('design-field-Payment Date')),
          );
          final method = tester.getRect(
            find.byKey(const ValueKey('design-field-Payment Method')),
          );
          final reference = tester.getRect(
            find.byKey(const ValueKey('design-field-Reference')),
          );
          expect(method.top, greaterThanOrEqualTo(date.top));
          expect(reference.top, greaterThanOrEqualTo(method.top));
        }
        if (title == 'Sales Receipts') {
          expect(
            find.byKey(const ValueKey('design-field-Payment Terms')),
            findsNothing,
          );
          expect(
            find.byKey(const ValueKey('design-field-Payment Method')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('design-field-Payment Account')),
            findsOneWidget,
          );
        }
        if (title == 'Claim · receipts') {
          final scroll = tester.widget<SingleChildScrollView>(
            find.byKey(const ValueKey('claim-editor-scroll')),
          );
          scroll.controller!.jumpTo(
            scroll.controller!.position.maxScrollExtent,
          );
          await tester.pumpAndSettle();
        }
        if (title == 'Expense · advanced fields') {
          await tester.tap(
            find.byKey(const ValueKey('expense-advanced-details')),
          );
          await tester.pumpAndSettle();
        }

        if (form?.lines == true && trialOrdinaryGroups.containsKey(title)) {
          final fields = trialOrdinaryGroups[title]!
              .where(
                (label) =>
                    label != 'Due Date' &&
                    find
                        .byKey(ValueKey('design-field-$label'))
                        .evaluate()
                        .isNotEmpty,
              )
              .toList();
          expect(
            find.byKey(const ValueKey('design-field-Due Date')),
            findsNothing,
          );
          final frames = [
            for (final label in fields)
              tester.getRect(find.byKey(ValueKey('design-field-$label'))),
          ];
          for (var i = 1; i < frames.length; i++) {
            expect(
              frames[i].top,
              greaterThanOrEqualTo(frames[i - 1].top),
              reason: '$title keeps field order as groups reflow at $width',
            );
            expect(frames[i].width, greaterThan(100));
          }
        }

        final surface = find.byType(AlertDialog).evaluate().isNotEmpty
            ? find.byType(AlertDialog).last
            : find.byType(Dialog).last;
        final material = find
            .descendant(of: surface, matching: find.byType(Material))
            .first;
        final rect = tester.getRect(material);
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('trial-capture')),
        );
        final filename =
            'Field Trial ${(serial++).toString().padLeft(3, '0')}.png';
        await tester.runAsync(() async {
          final full = await boundary.toImage();
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder);
          canvas.drawImageRect(
            full,
            rect,
            Rect.fromLTWH(0, 0, rect.width, rect.height),
            Paint(),
          );
          final picture = recorder.endRecording();
          final crop = await picture.toImage(
            rect.width.ceil(),
            rect.height.ceil(),
          );
          final bytes = await crop.toByteData(format: ui.ImageByteFormat.png);
          await File('$output/$filename')
              .writeAsBytes(bytes!.buffer.asUint8List());
          crop.dispose();
          full.dispose();
          picture.dispose();
        });
        // Observe the actual popup subtree, excluding its underlying page/parent dialog.
        String? fieldKey(Element element) {
          if (element.widget.key != null) return element.widget.key.toString();
          String? key;
          element.visitAncestorElements((ancestor) {
            if (ancestor.widget is TextFormField ||
                ancestor.widget is Autocomplete ||
                ancestor.widget is AccountingDescriptionField) {
              key = ancestor.widget.key?.toString();
              return false;
            }
            return true;
          });
          return key;
        }

        Map<String, Object?> geometry(Element element) {
          final bounds = tester.getRect(find.byWidget(element.widget));
          return {
            'left': bounds.left,
            'top': bounds.top,
            'width': bounds.width,
            'height': bounds.height,
            'overlapsCapture': rect.overlaps(bounds),
            'fullyInsideCapture':
                rect.contains(bounds.topLeft) &&
                rect.contains(bounds.bottomRight - const Offset(.001, .001)),
          };
        }

        final actualControls = <Map<String, Object?>>[];
        final observed = find.descendant(
          of: surface,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is AccountingSelector ||
                widget is TextField ||
                widget is Autocomplete ||
                widget is AccountingDescriptionField ||
                widget is AccountingSwitchListTile,
          ),
        );
        for (final element in observed.evaluate()) {
          final widget = element.widget;
          final common = {
            'key': fieldKey(element),
            'geometry': geometry(element),
          };
          if (widget is AccountingSelector) {
            actualControls.add({
              ...common,
              'kind': 'selector',
              'key': (widget.triggerKey ?? widget.controlKey ?? widget.key)
                  ?.toString(),
              'hint': widget.hintText,
              'semanticsLabel': widget.semanticsLabel,
              'enabled': widget.enabled,
              'searchable': widget.searchable,
              'selectedLabel': widget.options
                  .where((option) => option.value == widget.value)
                  .firstOrNull
                  ?.label,
              'options': [
                for (final option in widget.options)
                  {'label': option.label, 'enabled': option.enabled},
              ],
            });
          } else if (widget is Autocomplete<Payee>) {
            final options = await widget.optionsBuilder(
              const TextEditingValue(),
            );
            actualControls.add({
              ...common,
              'kind': 'autocomplete',
              'options': [
                for (final option in options)
                  {
                    'label': widget.displayStringForOption(option),
                    'roleLabel': option.typeLabel,
                  },
              ],
            });
          } else if (widget is Autocomplete) {
            actualControls.add({
              ...common,
              'kind': 'autocomplete',
              'optionsAudit':
                  'Typed option adapter required; no label inference.',
            });
          } else if (widget is TextField) {
            actualControls.add({
              ...common,
              'kind': 'textInput',
              'label': widget.decoration?.labelText,
              'hint': widget.decoration?.hintText,
              'readOnly': widget.readOnly,
              'enabled': widget.enabled ?? true,
              'obscured': widget.obscureText,
              'maxLines': widget.maxLines,
              'currencyPrefixPresent':
                  widget.decoration?.prefixIcon != null ||
                  widget.decoration?.prefixText != null,
            });
          } else if (widget is AccountingDescriptionField) {
            actualControls.add({
              ...common,
              'kind': 'description',
              'role': widget.role.name,
              'readOnly': widget.readOnly,
              'enabled': widget.enabled,
            });
          } else if (widget is AccountingSwitchListTile) {
            actualControls.add({
              ...common,
              'kind': 'toggle',
              'value': widget.value,
              'enabled': widget.onChanged != null,
            });
          }
        }
        final labels = find
            .descendant(of: surface, matching: find.byType(Text))
            .evaluate()
            .map(
              (e) =>
                  (e.widget as Text).data ??
                  (e.widget as Text).textSpan?.toPlainText() ??
                  '',
            )
            .where((text) => text.isNotEmpty)
            .toSet()
            .toList();
        inventory.add({
          'category': category,
          'title': title,
          'width': width,
          'actualWindow': tester.view.physicalSize.width,
          'file': filename,
          'note': note,
          'renderedControls': actualControls,
          'renderedTextLabels': labels,
          'fieldEvidence': 'Actual popup subtree at this captured state; definitions are separate. Off-scroll mounted controls carry visibility geometry. Input values and secrets are not recorded.',
          'definitionFields': [
            for (final f in form?.fields ?? <DesignField>[])
              {
                'label': f.label,
                'options': f.choiceLabels?.values.toList() ?? f.options,
                'multiline': f.multiline,
                'toggle': f.toggle,
                'required': f.required,
              },
          ],
          'fields': [
            for (final control in actualControls) {...control},
          ],
          'controls': [
            for (final e
                in find
                    .byWidgetPredicate((v) => v is AccountingSelector<String>)
                    .evaluate())
              {
                'key': (e.widget as AccountingSelector<String>).triggerKey
                    .toString(),
                'width': tester.getSize(find.byWidget(e.widget)).width,
              },
          ],
        });
        if (ownerPage != null ||
            category == 'Settings popout' ||
            category == 'Profile and access popout') {
          await tester.tap(find.byType(AccountingCloseIcon).last);
          await tester.pumpAndSettle();
        }
      }

      for (final entry in frontendAreas.entries) {
        if (entry.key == 'reports') continue;
        for (final form in entry.value) {
          if (const {
            'Tax Overview',
            'Tax Reconciliation',
            'Returns & Payments',
            'Customer Statements',
            'Accounting Review Queue',
            'For Review',
            'Linked Documents',
            'Filing History',
          }.contains(form.title)) {
            continue;
          }
          if (form.title == 'Pay Bills') {
            await render(
              'Catalogue · ${entry.key}',
              form.title,
              const PayBillsProposal(),
              note: 'QuickBooks Malaysia screenshot and current International help checked. Payment Account / Payment Date / optional Reference use shared ordinary fitting. Selected bills contain custom fluid Payment and Credit Applied amounts; total is calculated. No separate Vendor or duplicate total inputs. Fictional credit/card choices only; live durable credit and card settlement require migration. Main Pay Bills page and actual posting route are unchanged.',
            );
            continue;
          }
          await render(
            'Catalogue · ${entry.key}',
            form.title,
            FrontendFormDialog(
              form: form,
              initial: {
                if (form.title == 'Receive Payment') ...{
                  'Counterparty': 'Fictional Customer',
                  'Payment Date': '02-10-2026',
                  'Payment Method': 'Bank Transfer',
                  'Reference': 'DEMO-001',
                  'Amount': '750.00',
                  '_receiptExamples': true,
                  '_receiptSelected': [0],
                  '_receiptAllocation0': '500.00',
                },
                'Country': 'Malaysia',
                'Tax Details Needed': true,
                'Date Range': 'Custom',
                'Transaction Approval': 'Above Threshold',
              },
            ),
            form: form,
            note: 'Catalogue proposal only; not proof of live fields or supported save. Existing groups remain locked.',
          );
        }
      }
      // Actual catalogue popup owners with isolated preview variants. No real
      // catalogue/settings persistence is invoked by their preview actions.
      await render(
        'Code name proposal',
        'Add Category · Code Name',
        const CatalogueNameDialog(
          title: 'Add Category',
          preview: true,
          initialName: 'Video',
          initialCode: 'VID',
        ),
        note: 'Actual inline category owner: required Category and Code Name, shared fitting and the established grey footer. Keep Preview returns session values only; no catalogue write. The inline QuickBooks capture has a name input; its managed category hierarchy is presented separately.',
      );
      const categoryBranches = [
        CatalogueCategoryBranch(id: 'video', name: 'Video'),
        CatalogueCategoryBranch(
          id: 'commercial',
          name: 'Commercial',
          parentId: 'video',
        ),
        CatalogueCategoryBranch(
          id: 'campaign',
          name: 'Regional Campaigns',
          parentId: 'commercial',
        ),
        CatalogueCategoryBranch(id: 'photo', name: 'Photography'),
      ];
      await render(
        'Code name proposal',
        'Add Category · Managed',
        const CatalogueNameDialog(
          title: 'Add Category',
          preview: true,
          hierarchyPreview: true,
          initialName: 'Events',
          initialCode: 'EVT',
          parentChoices: categoryBranches,
        ),
        note: 'Actual managed-category owner variant. Category and required Code Name reuse shared fields; the established checkbox optionally reveals Parent Category. Current Intuit International documentation supports this separate managed flow. Keep Preview and Cancel never write catalogue records. Durable tree/reporting migration remains open.',
      );
      await render(
        'Code name proposal',
        'Add Category · Sub-category',
        const CatalogueNameDialog(
          title: 'Add Category',
          preview: true,
          hierarchyPreview: true,
          initialName: 'Social Campaigns',
          initialCode: 'SOC',
          initialParentId: 'commercial',
          parentChoices: categoryBranches,
        ),
        note: 'Managed creation with Sub-category selected. Parent Category uses complete category paths, shared one-line menu sizing and ordinary field fitting. The popup reserves its conditional control requirement before opening it. Keep Preview retains only session values; no catalogue, settings or file writes.',
      );
      await render(
        'Code name proposal',
        'Edit Category · Sub-category',
        const CatalogueNameDialog(
          title: 'Edit Category',
          preview: true,
          hierarchyPreview: true,
          categoryId: 'commercial',
          initialName: 'Commercial',
          initialCode: 'COM',
          initialParentId: 'video',
          parentChoices: categoryBranches,
        ),
        note: 'Managed Edit preserves category identity and excludes itself, descendants and invalid ancestry from Parent Category. Switching the checkbox off removes the parent from kept values; switching it back restores the session choice. Existing checkbox, selector, alert and grey footer owners are reused. Category persistence and historic snapshots remain pending.',
      );
      final previewCategory =
          w.catalogueCategories.where((c) => c.name == 'Video').firstOrNull ??
          w.saveCatalogueCategory(
            CatalogueCategory(id: EntityId.random(), name: 'Video'),
          );
      final postingAccounts = (await w.accounts())
          .map((r) => r.account)
          .where((a) => a.status == AccountStatus.active && !a.isParent)
          .toList();
      final paymentRecord = w.postedInvoices().firstWhere(
        (record) => record.documentNumber == 'DEMO-INV-001',
      );
      final paymentChoices = {
        for (final p in w.paymentAccounts.where(
          (p) =>
              p.type != PaymentAccountType.card &&
              p.currency.code == paymentRecord.sourceDraft.total.currency &&
              postingAccounts.any(
                (a) =>
                    a.type == AccountType.asset &&
                    a.id ==
                        w.database.paymentLedgerAccount(
                          w.identity.businessId,
                          p.id,
                        ),
              ),
        ))
          p.id: p.displayLabel,
      };
      final paymentForm = invoicePaymentReviewForm(
        invoice: paymentRecord.sourceDraft,
        paymentAccounts: paymentChoices,
        paidMinor: paymentRecord.paidMinor,
        creditedMinor: paymentRecord.creditedMinor,
        proposal: true,
      );
      await render(
        'Payment popout',
        'Receive Invoice Payment · Proposed',
        FrontendFormDialog(
          form: paymentForm,
          informationRows: [
            ('Customer', paymentRecord.customerSnapshot.displayName),
            ('Invoice', paymentRecord.documentNumber),
            (
              'Outstanding',
              invoiceMoney(
                Money.fromMinor(
                  paymentRecord.sourceDraft.total.minorUnits -
                      paymentRecord.paidMinor -
                      paymentRecord.creditedMinor,
                  paymentRecord.sourceDraft.total.currency,
                ),
              ),
            ),
          ],
          initial: {
            'Payment Date': '02-10-2026',
            'Reference': 'BANK-2026-001',
            'Payment Method': 'Bank Transfer',
            'Deposit To': paymentChoices.keys.first,
            'Amount Received': '750.00',
            'Memo': 'Payment for the selected invoice.',
          },
        ),
        form: paymentForm,
        note: 'Actual invoice shortcut form source with an isolated proposed extension: Payment Method, Deposit To and Memo beside one Amount Received (RM). Customer and invoice remain fixed read-only context. Ordinary fields reuse shared popup fitting; Amount and Memo retain custom owners. Preview has no commit callback. Method/Memo persistence, attachments and unified customer-payment allocation wiring remain pending.',
      );
      final savedDraft = w
          .invoiceDrafts()
          .firstWhere(
            (record) => record.invoice.documentNumber == 'DEMO-INV-003',
          )
          .invoice;
      final proposedTaxAccount = Account.create(
        id: EntityId.random(),
        code: '2200',
        name: 'Service Tax Payable',
        type: AccountType.liability,
      );
      final taxedPostingDraft = Invoice.draft(
        id: EntityId.random(),
        customerId: savedDraft.customerId,
        documentNumber: 'DEMO-INV-004',
        issueDate: savedDraft.issueDate,
        terms: savedDraft.terms,
        lines: [
          SalesLineItem.category(
            id: EntityId.random(),
            categoryId: postingAccounts.firstWhere((a) => a.code == '4000').id,
            description: 'Consulting session',
            quantity: SalesQuantity.fromInt(1),
            rate: Money.fromMinor(32000, 'MYR'),
            taxRatePercent: '8',
          ),
        ],
      );
      for (final withTax in [false, true]) {
        final postingDraft = withTax ? taxedPostingDraft : savedDraft;
        final postingForm = invoicePostingReviewForm(
          hasTax: postingDraft.lines.any((line) => line.tax.minorUnits > 0),
          accounts: [...postingAccounts, if (withTax) proposedTaxAccount],
        );
        await render(
          'Accounting popout',
          withTax ? 'Post Invoice · With Tax' : 'Post Invoice · No Tax',
          FrontendFormDialog(
            form: postingForm,
            initial: {
              'Document Number': postingDraft.documentNumber,
              'Receivable Account': postingAccounts
                  .firstWhere((a) => a.code == '1100')
                  .id
                  .value,
              if (withTax) 'Tax Account': proposedTaxAccount.id.value,
            },
            informationRows: [
              (
                'Customer',
                w
                    .customers()
                    .firstWhere((c) => c.id == postingDraft.customerId)
                    .displayName,
              ),
              if (withTax)
                ('Subtotal', invoiceMoney(postingDraft.lines.single.subtotal)),
              if (withTax)
                (
                  'Service Tax · 8%',
                  invoiceMoney(postingDraft.lines.single.tax),
                ),
              ('Total', invoiceMoney(postingDraft.total)),
            ],
          ),
          form: postingForm,
          note: 'Actual posting review definition and shared form renderer, with no commit callback. Document Number and receivable/conditional tax account selectors fit from their real active-account choices; information rows stay custom. The taxed example uses an isolated 8% Service Tax fixture and Service Tax Payable choice, with RM 320.00 subtotal, RM 25.60 tax and RM 345.60 total; neither the invoice nor sample account is saved. Broad asset/liability eligibility and a future default-first review are explicitly still open. This is a field-state proposal, not a posted invoice or an accepted accounting mapping.',
        );
      }
      final income = (await w.accounts())
          .firstWhere((r) => r.account.code == '4000')
          .account;
      final previewService =
          w.catalogueItems
              .where((i) => i.name == 'Corporate Video')
              .firstOrNull ??
          w.saveCatalogueItem(
            CatalogueItem(
              id: EntityId.random(),
              categoryId: previewCategory.id,
              name: 'Corporate Video',
              type: CatalogueItemType.service,
              incomeAccountId: income.id,
              description: 'Complete production package.\nIncludes filming, editing and delivery.',
            ),
          );
      final previewProduct =
          w.catalogueItems
              .where((i) => i.name == 'Video Production Kit')
              .firstOrNull ??
          w.saveCatalogueItem(
            CatalogueItem(
              id: EntityId.random(),
              categoryId: previewCategory.id,
              name: 'Video Production Kit',
              type: CatalogueItemType.product,
              incomeAccountId: income.id,
              description: 'A non-inventory production kit.',
            ),
          );
      await render(
        'Code name proposal',
        'Add Item · Code Name',
        CatalogueItemDialog(
          workspace: w,
          preview: const CatalogueItemPreview(code: 'CV'),
        ),
        note: 'Full actual Add Item owner proposal: editable Name, Type, required Code Name, Category, optional SKU and explicit active Income Account use shared ordinary fitting. Price / Rate (RM) stays custom and Description stays tall nontransactional. Document-level sales tax follows the user rule. Keep Preview never saves catalogue records. Classification/purchasing/lifecycle branches remain open.',
      );
      for (final sample in [
        (previewService, 'Edit Service · Full Item', 'CV'),
        (previewProduct, 'Edit Product · Full Item', 'KIT'),
      ]) {
        await render(
          'Code name proposal',
          sample.$2,
          CatalogueItemDialog(
            workspace: w,
            initial: sample.$1,
            preview: CatalogueItemPreview(
              code: sample.$3,
              sku: 'VID-001',
              rate: '1250.00',
            ),
          ),
          note: 'Actual populated Edit Item owner with isolated session values. Editing Name retains source identity. Required filing Code Name is distinct from optional SKU; Income Account reflects the saved source mapping. Only ordinary fields use the shared planner; Rate and Description retain their owners. Keep Preview validates and writes no catalogue data. Dedicated filing/rate/SKU storage and remaining conditional branches are pending.',
        );
      }
      await render(
        'Settings popout',
        'Product / Service Settings · Item Preview',
        null,
        ownerPage: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => CatalogueItemDialog(
                workspace: w,
                preview: const CatalogueItemPreview(code: 'CV'),
              ),
            ),
            child: const Text('Open Item Preview'),
          ),
        ),
        entrypoints: [
          find.text('Open Item Preview'),
          find.byKey(const ValueKey('catalogue-preview-settings-shortcut')),
        ],
        note: 'Actual catalogue footer Settings shortcut opens the existing live-settings Income Account field through FrontendFormDialog with no commit callback. Keep Preview affects only a new Item preview default; existing item mappings and company preferences remain unchanged. Shared popup fitting, grey footer and configured active income choices retain their owners.',
      );
      for (final sample in [
        ('Invoice', 'INV'),
        ('Quotation', 'QT'),
        ('Expense', 'EXP'),
        ('Bill', 'BILL'),
        ('Claim', 'CLM'),
        ('Payment Voucher', 'PV'),
      ]) {
        final kind = switch (sample.$1) {
          'Invoice' || 'Quotation' => SetupKind.invoice,
          'Claim' => SetupKind.claims,
          'Payment Voucher' => SetupKind.voucher,
          _ => SetupKind.expense,
        };
        await render(
          'Code name proposal',
          '${sample.$1} Settings · Code Name',
          NamingSetupDialog(
            kind: kind,
            demo: true,
            proposalCodeName: sample.$2,
            proposalTitle: '${sample.$1} Settings · File Setup',
          ),
          note: 'Code Name is required, before Save Location in a custom 30:70 inline row (after the existing gap). The first Filename Format box defaults to Code Name and shows its resolved value. Choosing Code Name on any naming box resolves the same document-family setting. Preview only; saving writes no settings or files. Per-family persistence and existing-record migration remain pending.',
        );
      }
      for (final form in liveSettingsForms({})) {
        await render(
          'Live settings owner',
          form.title,
          FrontendFormDialog(
            form: form,
            settingsWorkspace: w,
            initial: {
              ...w.preferences.sections[form.title] ?? {},
              'Date Range': 'Custom',
              'Transaction Approval': 'Above Threshold',
            },
          ),
          form: form,
          note: trialOrdinaryGroups.containsKey(form.title)
              ? 'Settings tab form schema for reference only; entire existing layout locked, not part of this trial.'
              : 'Durable settings field schema; existing layout locked.',
        );
      }
      for (final section in [
        'Sign-In & Sessions',
        'Users & Accountant Access',
      ]) {
        await render(
          'Settings popout',
          'Settings · $section',
          null,
          opener: (context) =>
              openAccountingSettings(context, workspace: w, proposalOnly: true),
          settingsSection: section,
          note: 'Actual expanded action-only Settings section. Account/session and access actions retain their original owner; fixture callbacks and availability are recorded, not permission changes.',
        );
      }
      for (final kind in SetupKind.values) {
        await render(
          'Settings popout',
          'Settings · ${kind.label} File Setup',
          null,
          opener: (context) => openAccountingSettings(
            context,
            proposalOnly: true,
            workspace: w,
            proposalCodeNames: {
              kind: switch (kind) {
                SetupKind.expense => 'EXP',
                SetupKind.invoice => 'INV',
                SetupKind.voucher => 'PV',
                SetupKind.claims => 'CLM',
              },
            },
          ),
          fileSetupKind: kind,
          note: 'Expanded Settings File Setup with proposed required Code Name before Save Location (custom 30:70), default/resolved filename Code Name token. Code settings and naming changes are demo-only, with no native writes; ordinary row planning is excluded.',
        );
      }
      for (final form in [customerForm, vendorForm]) {
        await render(
          'Live field owner',
          form.title,
          FrontendFormDialog(
            form: form,
            settingsWorkspace: w,
            initial: {
              'Country': 'Malaysia',
              'Tax Details Needed': true,
              'Payment Terms': 'Day Of Month',
            },
          ),
          form: form,
        );
      }
      await render(
        'Live field owner',
        'Credit Note',
        InvoiceCreditEditor(
          workspace: w,
          invoice: w.postedInvoices().first.sourceDraft,
        ),
      );
      await render(
        'Live field owner',
        'Manual Journal',
        null,
        opener: (context) async =>
            showJournalEditor(context, w, await w.accounts()),
      );
      await render(
        'Live field owner',
        'Expense Recurrence',
        null,
        opener: (context) => showExpenseRecurrenceDialog(
          context,
          startsOn: DateTime(2026, 10, 1),
        ),
      );
      await render(
        'Live field owner',
        'Payment Account',
        null,
        opener: (context) => showPaymentAccountDialog(
          context,
          preferredCurrencyCode: 'MYR',
          newId: () => EntityId.random().value,
          buildLabel: (context, label, required) =>
              accountingFieldLabel(context, label, alignToField: true),
        ),
      );
      w.savePaymentAccount(
        PaymentAccount.create(
          id: 'layout-bank',
          name: 'Fictional Bank',
          type: PaymentAccountType.bank,
          currencyCode: 'MYR',
        ),
      );
      final statement = w.database.importBankStatement(
        id: EntityId.random(),
        businessId: w.identity.businessId,
        paymentAccountId: 'layout-bank',
        importedAt: DateTime(2026, 10, 2),
        statement: BankStatementImport.csv(
          filename: 'Fictional Statement.csv',
          currency: 'MYR',
          bytes: Uint8List.fromList(
            utf8.encode(
              'Date,Description,Amount\n2026-10-01,Fictional movement,-10.00',
            ),
          ),
        ),
      );
      await render(
        'Accounting popout',
        'Statement Reconciliation',
        StatementReconciliationDialog(
          workspace: w,
          statementId: statement,
          currency: 'MYR',
        ),
        note: 'Actual popout owner; dates use shared measured rows. Amount and embedded-page layouts retain their own owners. Fictional bank statement only.',
      );
      await render(
        'Accounting popout',
        'Prepare Closing',
        null,
        ownerPage: JournalReviewPage(workspace: w),
        entrypoints: [find.byKey(const ValueKey('prepare-closing'))],
        note: 'Actual closing-draft owner. Existing 320px content width retained; no period lock or journal saved.',
      );
      await render(
        'Accounting popout',
        'Link Ledger Account',
        null,
        ownerPage: BankingPage(workspace: w, compact: false),
        entrypoints: [
          find.byKey(const ValueKey('banking-account-switcher')),
          find.byKey(const ValueKey('banking-account-option-layout-bank')),
          find.byKey(const ValueKey('imported-account-more')),
          find.byKey(const ValueKey('menu-Link Ledger Account')),
        ],
        note: 'Actual ledger-link owner; selector fills existing 460px content. Link confirmation is not executed.',
      );
      for (final kind in SetupKind.values) {
        await render(
          'Custom · locked',
          '${kind.name} Naming And Folder',
          NamingSetupDialog(kind: kind, demo: true),
        );
      }
      final tax = await taxRateEditor(w);
      await render('Live field owner', 'Add Tax Rate', tax, form: tax.form);
      await render(
        'Live field owner',
        'Claim',
        ClaimEditorDialog(
          id: EntityId.random(),
          onSaveDraft: (_) {},
          onSubmit: (_) {},
        ),
      );
      await render(
        'Live field owner',
        'Payment Voucher',
        PaymentVoucherEditorDialog(
          id: EntityId.random().value,
          onSaveDraft: (_) {},
          onSubmit: (_) {},
        ),
      );
      for (final title in ['Add Claimant', 'Add Merchant']) {
        await render(
          'Live field owner',
          title,
          ClaimEditorDialog(
            id: EntityId.random(),
            onSaveDraft: (_) {},
            onSubmit: (_) {},
          ),
          note: 'Actual nested payee creation owner; saves are not exercised in captures.',
        );
      }
      await render(
        'Live field owner',
        'Add Payee',
        PaymentVoucherEditorDialog(
          id: EntityId.random().value,
          onSaveDraft: (_) {},
          onSubmit: (_) {},
        ),
        note: 'Actual nested voucher payee owner; directory persistence is separate.',
      );
      await render(
        'Live field owner',
        'Expense',
        RecordExpensePage(
          settingsWorkspace: w,
          onSave: (_) async {},
          includeTopSafeArea: false,
          onCancel: () {},
        ),
        note: 'Isolated Currency / Amounts Are / Make Recurring trial; custom lines remain locked.',
      );
      await render(
        'Live field owner',
        'Claim · receipts',
        ClaimEditorDialog(
          id: EntityId.random(),
          onSaveDraft: (_) {},
          onSubmit: (_) {},
        ),
        note: 'Actual Claim continuation using shared Expense uploader and file-list tokens; header and currency correction verified separately from receipt transaction rows.',
      );
      await render(
        'Live field owner',
        'Expense · advanced fields',
        RecordExpensePage(
          settingsWorkspace: w,
          includeTopSafeArea: false,
          onSave: (_) async {},
          onCancel: () {},
        ),
        note: 'Full expanded advanced field group; the transaction grid and advanced layout are locked.',
      );
      await render(
        'Settings popout',
        'Settings · all sections',
        null,
        opener: (context) =>
            openAccountingSettings(context, workspace: w, proposalOnly: true),
        note: 'Actual Settings shell in explicit no-write proposal mode. Ordinary popup sections inherit the shared fitter; custom filename and action owners retain their layout.',
      );
      for (final form in liveSettingsForms({})) {
        await render(
          'Settings popout',
          'Settings · ${form.title}',
          null,
          opener: (context) =>
              openAccountingSettings(context, workspace: w, proposalOnly: true),
          settingsSection: form.title,
          note: 'Actual expanded Settings popup section in explicit no-write proposal mode. Ordinary fields opt into the shared planner; narrative, money, switches and file setup keep their owners. Preview only.',
        );
      }
      for (final family in [
        'Invoices',
        'Quotations',
        'Bills',
        'Record Expense',
        'Products & Services',
      ]) {
        final sections = transactionSettingsFields(family);
        final kinds = switch (family) {
          'Invoices' || 'Quotations' => const {SetupKind.invoice},
          'Bills' || 'Record Expense' => const {SetupKind.expense},
          _ => const <SetupKind>{},
        };
        for (final section in sections.keys) {
          await render(
            'Settings popout',
            '$family Settings · $section',
            null,
            opener: (context) => openAccountingSettings(
              context,
              proposalOnly: true,
              workspace: w,
              fields: sections,
              setupKinds: kinds,
              title: '$family Settings',
            ),
            settingsSection: section,
            note: 'Actual filtered footer settings snippet. Same source schema and row owner as Settings; only existing family fields are exposed. Explicit proposal mode removes company commits and external actions; Preview / Continue Editing retain session values only.',
          );
        }
        if (kinds.isNotEmpty) {
          await render(
            'Settings popout',
            '$family Settings · File Setup',
            null,
            opener: (context) => openAccountingSettings(
              context,
              proposalOnly: true,
              workspace: w,
              fields: sections,
              setupKinds: kinds,
              title: '$family Settings',
              proposalCodeNames: {
                kinds.single: switch (family) {
                  'Quotations' => 'QT',
                  'Invoices' => 'INV',
                  'Bills' => 'BILL',
                  _ => 'EXP',
                },
              },
            ),
            fileSetupKind: kinds.single,
            note: 'Expanded footer File Setup with proposed required Code Name before Save Location (custom 30:70) and default/resolved filename Code Name token. Demo-only naming changes, no native writes. Invoice/Quotation and Bill/Expense codes are separate despite shared roots. Ordinary rows are excluded.',
          );
        }
      }
      await render(
        'Settings popout',
        'Audit Log',
        AuditLogDialog(workspace: w),
      );
      await render(
        'Settings popout',
        'Recurring Transactions',
        RecurringTransactionsDialog(workspace: w),
      );
      final session = GoogleAccountSession();
      addTearDown(session.dispose);
      await render(
        'Profile and access popout',
        'Change Password',
        null,
        opener: (context) => showPasswordChange(context, session),
      );
      await render(
        'Profile and access popout',
        'Edit Profile',
        null,
        ownerPage: const Align(
          alignment: Alignment.topRight,
          child: LocalProfileMenu(),
        ),
        entrypoints: [
          find.byKey(const ValueKey('global-profile')),
          find.byKey(const ValueKey('profile-menu-profile')),
        ],
      );
      final directory = PreviewUserDirectory();
      addTearDown(directory.dispose);
      await render(
        'Profile and access popout',
        'Change Employee Role',
        null,
        ownerPage: UsersPage(directory: directory),
        entrypoints: [
          find.byKey(const ValueKey('change-role-demo-accountant')),
        ],
      );
      await render(
        'Profile and access popout',
        'Approve Employee Role',
        null,
        ownerPage: UsersPage(directory: directory),
        entrypoints: [
          find.byKey(const ValueKey('approve-user-demo-registration')),
        ],
      );
      await render(
        'Accounting popout',
        'New Ledger Account',
        null,
        ownerPage: ChartOfAccountsPage(workspace: w),
        entrypoints: [find.byKey(const ValueKey('new-ledger-account'))],
      );
      await tester.runAsync(() async {
        await File(
          '$output/Field Trial Inventory.json',
        ).writeAsString(const JsonEncoder.withIndent('  ').convert(inventory));
      });
    });
  }
}
