import 'dart:io';
import 'dart:ui' show SemanticsAction;

import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/frontend_review.dart';
import 'package:audyt/app/local_profile.dart';
import 'package:audyt/app/naming_setup.dart';
import 'package:audyt/app/transaction_form_layout.dart';
import 'package:audyt/features/purchases/presentation/claims_page.dart';
import 'package:audyt/features/sales/invoice_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'claim_receipts_proposal_test.dart' show fixture, prepare;
import 'journal_workspace_integration_test.dart' show captureUi;
import '../support/fixed_popout_host.dart';

const sampleHelp = 'Use sample values to check your format before saving.';
const recurrenceHelp = 'Manage the saved schedule in Recurring.';
const personalHelp =
    'Required for reimbursement. Use Record Expense when a company account paid the merchant.';

Future<void> host(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('workspace-capture'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AccountingTheme.light(),
        home: Scaffold(body: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> revealHelp(
  WidgetTester tester,
  String message,
  String captureName,
) async {
  expect(find.text(message), findsNothing);
  final help = find
      .byWidgetPredicate(
        (widget) => widget is AccountingFieldHelp && widget.message == message,
      )
      .first;
  await tester.ensureVisible(help);
  await tester.pumpAndSettle();
  await tester.tap(help);
  await tester.pumpAndSettle();
  expect(find.text(message), findsOneWidget);
  await captureUi(tester, captureName);
  Tooltip.dismissAllToolTips();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('accessible field help replaces the previously opened guidance', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      addTearDown(Tooltip.dismissAllToolTips);
      await host(
        tester,
        const Row(
          children: [
            AccountingFieldHelp(
              label: 'Days Before',
              message: 'Days before the transaction date to show its reminder.',
            ),
            AccountingFieldHelp(
              label: 'Day Of Week',
              message: 'Choose the weekday on which the template occurs.',
            ),
          ],
        ),
      );
      final buttons = find.descendant(
        of: find.byType(AccountingFieldHelp),
        matching: find.byType(IconButton),
      );
      // Native AX activation emits a semantic action without a PointerDownEvent.
      // A pointer-only test would dismiss the prior tooltip in the framework and
      // miss the installed accessibility failure.
      var node = tester.getSemantics(buttons.at(0));
      node.owner!.performAction(node.id, SemanticsAction.tap);
      await tester.pumpAndSettle();
      expect(
        find.text('Days before the transaction date to show its reminder.'),
        findsOneWidget,
      );
      node = tester.getSemantics(buttons.at(1));
      node.owner!.performAction(node.id, SemanticsAction.tap);
      await tester.pumpAndSettle();
      expect(
        find.text('Choose the weekday on which the template occurs.'),
        findsOneWidget,
      );
      expect(
        find.text('Days before the transaction date to show its reminder.'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  for (final width in [720.0, 1224.0]) {
    testWidgets('profile help preserves approval status at $width', (
      tester,
    ) async {
      await prepare(tester, width);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        LocalProfile.channel,
        (call) async => call.method == 'load'
            ? <String, String>{
                'name': 'Fictional Applicant',
                'email': 'fictional@example.test',
                'role': 'Employee',
              }
            : null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          LocalProfile.channel,
          null,
        ),
      );
      await host(
        tester,
        LocalProfileMenu(
          approvalStatus: 'pending',
          submitRegistration: (_) async {},
        ),
      );
      await tester.tap(find.byKey(const ValueKey('global-profile')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('profile-menu-profile')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('profile-save')));
      await tester.pumpAndSettle();
      expect(
        find.text('Business access: Awaiting Director approval.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('profile-role')), findsOneWidget);
      final nameRect = tester.getRect(
        find.byKey(const ValueKey('profile-name')),
      );
      final emailRect = tester.getRect(
        find.byKey(const ValueKey('profile-email')),
      );
      expect(nameRect.top, emailRect.top);
      expect(nameRect.width, closeTo(emailRect.width, .1));
      expect(emailRect.left - nameRect.right, closeTo(20, .1));
      await captureUi(tester, 'Profile Title Guidance ${width.toInt()}');
      await revealHelp(
        tester,
        'Contact email can be changed without changing your sign-in email.',
        'Profile Contact Help ${width.toInt()}',
      );
      await tester.tap(find.bySemanticsLabel('Close').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('filename preview help leaves custom tokens intact at $width', (
      tester,
    ) async {
      await prepare(tester, width);
      await (FontLoader('monospace')..addFont(
            Future.value(
              ByteData.sublistView(
                File('/System/Library/Fonts/Menlo.ttc').readAsBytesSync(),
              ),
            ),
          ))
          .load();
      await host(
        tester,
        const NamingSetupDialog(
          saved: '[{"type":"custom","text":"CUSTOM TEXT"}]',
        ),
      );
      final input = find.byKey(const ValueKey('naming-inline-0'));
      expect(tester.widget<TextField>(input).controller!.text, 'CUSTOM TEXT');
      await tester.enterText(input, 'SAMPLE REFERENCE');
      await tester.pumpAndSettle();
      await captureUi(tester, 'Filename Preview Guidance ${width.toInt()}');
      await revealHelp(
        tester,
        sampleHelp,
        'Filename Preview Help ${width.toInt()}',
      );
      expect(
        tester.widget<TextField>(input).controller!.text,
        'SAMPLE REFERENCE',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('personal claim help retains claimant identity at $width', (
      tester,
    ) async {
      await prepare(tester, width);
      final f = await fixture();
      addTearDown(f.w.dispose);
      final original = f.claim();
      final before = original.toJson();
      await host(
        tester,
        ClaimEditorDialog(
          id: original.id,
          initial: original,
          onSaveDraft: (_) {},
          onSubmit: (_) {},
        ),
      );
      final personal = find.byKey(const ValueKey('claim-personal-payment'));
      await tester.ensureVisible(personal);
      await tester.pumpAndSettle();
      await captureUi(
        tester,
        'Legacy Claim Personal Guidance ${width.toInt()}',
      );
      await revealHelp(
        tester,
        personalHelp,
        'Legacy Claim Personal Help ${width.toInt()}',
      );
      expect(original.toJson(), before);
      expect(tester.takeException(), isNull);
    });

    testWidgets('managed invoice recurrence remains locked at $width', (
      tester,
    ) async {
      await prepare(tester, width);
      final f = await fixture();
      addTearDown(f.w.dispose);
      installFixedPopoutHost(tester);
      final form = invoiceForm(
        {'customer': 'Fictional Customer'},
        {'sales': '4000 · Fictional Sales'},
        preferences: f.w.preferences,
        itemChoices: {'item': 'Fictional Item'},
      );
      await host(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => AccountingDialog.showFixed<void>(
              context: context,
              contentWidth: frontendTransactionContentWidth(context, form),
              builder: (_) => FrontendFormDialog(
                settingsWorkspace: f.w,
                form: form,
                initial: const {
                  '_recurrenceManaged': true,
                  'Make Recurring': 'Monthly',
                  'Currency': 'MYR',
                  'Counterparty': 'customer',
                },
              ),
            ),
            child: const Text('Open Managed Invoice'),
          ),
        ),
      );
      await tester.tap(find.text('Open Managed Invoice'));
      await tester.pumpAndSettle();
      final recurring = find.byWidgetPredicate(
        (widget) =>
            widget is AccountingSelector<String> &&
            widget.triggerKey == const ValueKey('design-field-Make Recurring'),
      );
      expect(
        tester.widget<AccountingSelector<String>>(recurring).enabled,
        false,
      );
      expect(find.byType(AccountingTransactionGrid), findsOneWidget);
      expect(find.text('Supporting Documents'), findsOneWidget);
      await tester.ensureVisible(recurring);
      await tester.pumpAndSettle();
      await captureUi(tester, 'Managed Recurrence Guidance ${width.toInt()}');
      await revealHelp(
        tester,
        recurrenceHelp,
        'Managed Recurrence Help ${width.toInt()}',
      );
      expect(
        tester.widget<AccountingSelector<String>>(recurring).enabled,
        false,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
