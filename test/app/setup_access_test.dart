import 'dart:io';

import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/domain/recurrence_rule.dart';
import 'package:audyt/features/accounting/presentation/record_expense_page.dart';

import '../features/accounting/data/expense_intake_test.dart' show draft;

import 'dart:convert';

import 'package:audyt/app/app.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/app/naming_setup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final formats = <String, String>{};
  final folders = <String, String>{};
  final calls = <String>[];
  setUp(() {
    formats.clear();
    folders.clear();
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(namingSettingsChannel, (call) async {
          final args = call.arguments as Map;
          final kind = args['kind'] as String;
          calls.add('${call.method}:$kind');
          switch (call.method) {
            case 'load':
              return formats[kind];
            case 'loadFolder':
              return folders[kind];
            case 'chooseFolder':
              return '/Example/$kind';
            case 'commitSetup':
              folders[kind] = '/Example/$kind';
              formats[kind] = args['format'] as String;
              return folders[kind];
            case 'save':
              formats[kind] = args['format'] as String;
              return null;
          }
          return null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(namingSettingsChannel, null),
  );
  Future<void> mount(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1224, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const AudytApp(showInitialSetup: true));
    await tester.pumpAndSettle();
  }

  testWidgets('Settings is bottom left with four collapsible setups', (
    tester,
  ) async {
    await mount(tester);
    expect(find.text('Expense Setup'), findsNothing);
    final button = find.byKey(const ValueKey('accounting-settings'));
    expect(tester.getRect(button).left, 0);
    expect(tester.getRect(button).bottom, greaterThan(900));
    await tester.tap(button);
    await tester.pumpAndSettle();
    for (final kind in SetupKind.values) {
      expect(find.text(kind.label), findsOneWidget);
    }
    await tester.ensureVisible(find.text('Invoice Setup'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Invoice Setup'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('naming-folder-picker')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('naming-folder-picker')));
    await tester.pumpAndSettle();
    expect(calls, contains('chooseFolder:invoice'));
    expect(calls, isNot(contains('chooseFolder:expense')));
    await tester.ensureVisible(find.text('Invoice Setup'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Invoice Setup'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('naming-folder-picker')), findsNothing);
  });
  testWidgets(
    'Record Expense opens solo setup then continues and skips it on repeat',
    (tester) async {
      await mount(tester);
      await tester.tap(
        find.byKey(const ValueKey('home-record-expense-action')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Expense Setup'), findsOneWidget);
      expect(find.text('Invoice Setup'), findsNothing);
      await tester.ensureVisible(
        find.byKey(const ValueKey('naming-folder-picker')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('naming-folder-picker')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('naming-type-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('naming-option-day')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('naming-save')));
      await tester.pumpAndSettle();
      expect(find.byType(RecordExpensePage), findsOneWidget);
      expect(jsonDecode(formats['expense']!), [
        {'type': 'day', 'text': ''},
      ]);
      expect(formats.containsKey('claims'), isFalse);
      await tester.tap(find.byKey(const ValueKey('record-expense-cancel')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('navigation-item-home')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('home-record-expense-action')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Expense Setup'), findsNothing);
    },
  );
  testWidgets('cancelled first use does not open the expense form', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.byKey(const ValueKey('home-record-expense-action')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('naming-cancel')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('page-title-record-expense')),
      findsNothing,
    );
    expect(formats, isEmpty);
  });
  testWidgets('New Claim opens only Claims Setup', (tester) async {
    await mount(tester);
    await tester.tap(
      find.byKey(const ValueKey('navigation-item-expenses-vendors')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(Tab, 'Claims'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New Claim'));
    await tester.pumpAndSettle();
    expect(find.text('Claims Setup'), findsOneWidget);
    expect(find.text('Expense Setup'), findsNothing);
  });
  testWidgets('Demo Company opens a voucher form without a real folder setup', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1224, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const DemoCompany(child: AudytApp(showInitialSetup: true)),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('navigation-item-expenses-vendors')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(Tab, 'Payment Vouchers'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New Voucher'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('payment-voucher-editor-dialog')),
      findsOneWidget,
    );
    expect(find.text('Payment Voucher Setup'), findsNothing);
    expect(calls.where((call) => call.startsWith('loadFolder:')), isEmpty);
  });
  testWidgets(
    'recurring review obeys solo setup cancel and save continuation',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1224, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final dir = Directory.systemTemp.createTempSync('recurring-setup-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final workspace = await AccountingWorkspace.open(
        '${dir.path}/ledger.sqlite',
      );
      addTearDown(workspace.dispose);
      await workspace.saveExpenseIntake(
        draft(
          recurrence: RecurrenceRule(
            startsOn: DateTime.utc(2090, 9, 13),
            unit: RecurrenceUnit.months,
          ),
        ),
      );
      final template = workspace.database
          .recurringExpenseTemplates(workspace.identity.businessId)
          .single;
      workspace.database.prepareRecurringExpenseOccurrence(
        workspace.identity.businessId,
        template.id,
        expectedRevision: 1,
        index: 1,
      );
      await tester.pumpWidget(
        AudytApp(
          workspace: workspace,
          initialPath: '/expenses-vendors',
          showInitialSetup: true,
        ),
      );
      await tester.pumpAndSettle();
      final expense = (await workspace.expenses()).single;
      final openExpense = find.byKey(
        ValueKey('open-expense-${expense.id.value}'),
      );
      await tester.ensureVisible(openExpense);
      await tester.tap(openExpense);
      await tester.pumpAndSettle();
      final manage = find.byKey(const ValueKey('expense-manage-recurrences'));
      await tester.ensureVisible(manage);
      await tester.tap(manage);
      await tester.pumpAndSettle();
      Future<void> review() async {
        await tester.tap(
          find.byKey(const ValueKey('recurring-saved-suggestions')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Review Expense'));
        await tester.pumpAndSettle();
      }

      await review();
      expect(find.text('Expense Setup'), findsOneWidget);
      expect(find.text('Invoice Setup'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('naming-cancel')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('page-title-record-expense')),
        findsNothing,
      );
      expect(await workspace.expenses(), hasLength(1));
      expect(
        workspace.database
            .recurringExpenseSuggestions(workspace.identity.businessId)
            .single
            .savedExpenseId,
        isNull,
      );
      await review();
      await tester.ensureVisible(
        find.byKey(const ValueKey('naming-folder-picker')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('naming-folder-picker')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('naming-type-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('naming-option-day')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('naming-save')));
      await tester.pumpAndSettle();
      expect(find.byType(RecordExpensePage), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('expense-field-date')),
            )
            .controller!
            .text,
        '13-10-2090',
      );
      expect(formats.keys, ['expense']);
      expect(await workspace.expenses(), hasLength(1));
      await tester.pumpWidget(const SizedBox());
    },
  );
}
