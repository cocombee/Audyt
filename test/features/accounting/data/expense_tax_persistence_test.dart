import 'dart:io';

import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/application/journal_entry_repository.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/domain/company_tax_rate.dart';
import 'package:audyt/features/accounting/domain/expense_draft.dart';
import 'package:audyt/features/accounting/domain/journal_entry.dart';
import 'package:audyt/features/accounting/domain/payment_account.dart';
import 'package:audyt/features/accounting/domain/recurrence_rule.dart';
import 'package:audyt/features/accounting/domain/recurring_expense_template.dart';
import 'package:flutter_test/flutter_test.dart';

import 'expense_intake_test.dart' show draft;

Future<List<CompanyTaxRate>> configureExpenseTaxes(
  AccountingWorkspace w,
) async {
  await w.createAccount(
    code: '2200',
    name: 'Fictional Tax Account',
    type: AccountType.liability,
  );
  final account = (await w.accounts())
      .singleWhere((r) => r.account.code == '2200')
      .account
      .id;
  w.savePaymentAccount(
    PaymentAccount.create(
      id: 'cash',
      name: 'Cash',
      type: PaymentAccountType.cash,
      currencyCode: 'MYR',
    ),
  );
  return [
    for (final percent in ['8', '10', '0'])
      w.saveTaxRate(
        CompanyTaxRate(
          id: EntityId.random(),
          name: switch (percent) {
            '8' => 'Service Tax',
            '10' => 'SST',
            _ => 'Exempt',
          },
          percent: percent,
          effectiveFrom: DateTime.utc(2026),
          effectiveThrough: DateTime.utc(2026, 12, 31),
          application: TaxApplication.purchases,
          accountId: account,
        ),
      ),
  ];
}

RecordExpenseDraft taxedExpense(List<CompanyTaxRate> codes, String basis) =>
    RecordExpenseDraft.fromJson({
      ...draft(amount: '183.00', paymentAccountId: 'cash').toJson(),
      'version': 2,
      'taxMode': basis,
      'tax': 'Multiple Taxes',
      'lines': [
        ExpenseDraftLine(
          id: 'first',
          category: 'Office Operations',
          description: 'Receipt item one',
          tax: codes[0].choice,
          taxSnapshot: codes[0],
          amount: basis == 'Inclusive' ? '108.00' : '100.00',
          quantity: '3',
          rate: basis == 'Inclusive' ? '36.00' : '33.34',
          pricingAdjustment: basis == 'Inclusive' ? '0' : '-0.02',
        ).toJson(),
        ExpenseDraftLine(
          id: 'second',
          category: 'Office Operations',
          description: 'Receipt item two',
          tax: codes[1].choice,
          taxSnapshot: codes[1],
          amount: basis == 'Inclusive' ? '55.00' : '50.00',
        ).toJson(),
        const ExpenseDraftLine(
          id: 'third',
          category: 'Office Operations',
          description: 'Untaxed item',
          tax: '0',
          amount: '20.00',
        ).toJson(),
      ],
    });

void main() {
  for (final basis in ['Exclusive', 'Inclusive']) {
    test(
      '$basis posting matches evidenced gross and does not charge tax twice',
      () async {
        final w = await AccountingWorkspace.open(':memory:');
        addTearDown(w.dispose);
        final codes = await configureExpenseTaxes(w);
        final intake = taxedExpense(codes, basis);
        final id = await w.saveExpenseIntake(intake);
        await w.createAccount(
          code: '1000',
          name: 'Cash Ledger',
          type: AccountType.asset,
        );
        await w.createAccount(
          code: '5000',
          name: 'Gross Purchase Cost',
          type: AccountType.expense,
        );
        final accounts = await w.accounts();
        final cash = accounts
            .singleWhere((a) => a.account.code == '1000')
            .account
            .id;
        final cost = accounts
            .singleWhere((a) => a.account.code == '5000')
            .account
            .id;
        Future<void> prepare(String amount) => w.saveJournal(
          date: DateTime.utc(2026, 9, 13),
          memo: 'Reviewed purchase cost',
          lines: [
            JournalLine.debit(
              accountId: cost,
              amount: Money.fromDecimal(amount, 'MYR'),
            ),
            JournalLine.credit(
              accountId: cash,
              amount: Money.fromDecimal(amount, 'MYR'),
            ),
          ],
        );
        await prepare('170.00');
        final wrong = (await w.journals()).single;
        JournalApproval approval(EntityId journal) => JournalApproval(
          requestId: EntityId.random(),
          businessId: w.identity.businessId,
          journalId: journal,
          expectedRevision: 1,
          actorId: w.identity.ownerId,
          approvedAt: DateTime.now().toUtc().add(const Duration(seconds: 1)),
          expenseIntakeId: id,
        );
        await expectLater(
          w.approveJournal(approval(wrong.entry.id)),
          throwsStateError,
        );
        expect((await w.expense(id))!.summary.isPosted, isFalse);
        await prepare('183.00');
        final correct = (await w.journals()).singleWhere(
          (j) => j.entry.id != wrong.entry.id,
        );
        final posted = await w.approveJournal(approval(correct.entry.id));
        expect(
          posted.entry.lines
              .where((l) => l.isDebit)
              .fold(0, (int a, l) => a + l.amount.minorUnits),
          18300,
        );
        final report = await w.report(
          from: DateTime.utc(2026, 9),
          through: DateTime.utc(2026, 9, 30),
        );
        expect(report.revenue, BigInt.zero);
        expect(report.expenses, BigInt.from(18300));
        expect(report.periodProfit, BigInt.from(-18300));
        expect(
          report.liabilities,
          BigInt.zero,
          reason: 'Purchase tax stays in gross cost; no sales liability or input recovery is invented.',
        );
        expect(report.isBalanced, isTrue);
        final activity = await w.taxActivity(
          from: DateTime.utc(2026, 9),
          through: DateTime.utc(2026, 9, 30),
        );
        expect(activity.rows, hasLength(3));
        expect(activity.salesTax, BigInt.zero);
        expect(activity.purchaseTaxInCost, BigInt.from(1300));
        expect(activity.rows.map((r) => r.taxLabel), contains('No Tax'));
        expect(activity.unresolved, isEmpty);
        expect(
          report.pendingDrafts,
          1,
          reason: 'Rejected net-only draft does not enter P&L.',
        );
        final saved = (await w.expense(id))!;
        expect(saved.summary.isPosted, isTrue);
        expect(saved.draft.taxTotals!.tax.minorUnits, 1300);
        expect(saved.draft.toJson(), intake.toJson());
        expect(
          w.database.expenseRemovalRestriction(w.identity.businessId, id),
          contains('Posted'),
        );
      },
    );
    test(
      '$basis mixed codes, exact totals, amendments, restart and archive recovery',
      () async {
        final dir = Directory.systemTemp.createTempSync('expense-tax-');
        addTearDown(() => dir.deleteSync(recursive: true));
        final path = '${dir.path}/books.sqlite';
        var w = await AccountingWorkspace.open(path);
        addTearDown(() => w.dispose());
        final codes = await configureExpenseTaxes(w);
        final intake = taxedExpense(codes, basis);
        expect(intake.taxTotals!.net.minorUnits, 17000);
        expect(intake.taxTotals!.tax.minorUnits, 1300);
        expect(intake.taxTotals!.total.minorUnits, 18300);
        final id = await w.saveExpenseIntake(intake);
        expect(await w.saveExpenseIntake(intake), id);
        final first = (await w.expense(id))!;
        expect(first.summary.amount.minorUnits, 18300);
        expect(
          first.draft.lines.first.amount,
          basis == 'Inclusive' ? '108.00' : '100.00',
        );
        w.saveTaxRate(
          CompanyTaxRate.fromJson({
            ...codes[0].toJson(),
            'percent': '9',
            'active': false,
          }),
        );
        final amended = RecordExpenseDraft.fromJson({
          ...intake.toJson(),
          'notes': 'Memo amendment',
        });
        await w.updateExpenseIntake(
          id: id,
          expected: intake,
          replacement: amended,
          expectedRevision: first.summary.revision,
        );
        final staleNew = RecordExpenseDraft.fromJson({
          ...intake.toJson(),
          'submissionId': 'new-with-old-rate',
        });
        await expectLater(w.saveExpenseIntake(staleNew), throwsStateError);
        w.dispose();
        w = await AccountingWorkspace.open(path);
        final saved = (await w.expense(id))!;
        expect(saved.draft.toJson(), amended.toJson());
        expect(saved.draft.taxTotals!.tax.minorUnits, 1300);
        expect(saved.summary.revision, 2);
        final archive = w.database.exportDataArchive(
          w.identity.businessId,
          DateTime.now().toUtc(),
        );
        final recovered = await AccountingWorkspace.emptyRestore(
          '${dir.path}/recovered.sqlite',
          archive,
        );
        addTearDown(recovered.dispose);
        expect((await recovered.expense(id))!.draft.toJson(), amended.toJson());
        expect(await recovered.journals(), isEmpty);
        expect(await w.expenses(), hasLength(1));
      },
    );
  }

  test('foreign, fabricated, expired and unreviewed purchase tax reject without intake writes', () async {
    final w = await AccountingWorkspace.open(':memory:');
    addTearDown(w.dispose);
    final codes = await configureExpenseTaxes(w);
    final valid = taxedExpense(codes, 'Exclusive');
    final other = await AccountingWorkspace.open(':memory:');
    addTearDown(other.dispose);
    final foreign = await configureExpenseTaxes(other);
    final fabricated = CompanyTaxRate.fromJson({
      ...codes[0].toJson(),
      'name': 'Fabricated history',
    });
    final baseLine = Map<String, dynamic>.from(
      (valid.toJson()['lines'] as List).first as Map,
    );
    final invalid = [
      taxedExpense(foreign, 'Exclusive'),
      RecordExpenseDraft.fromJson({...valid.toJson(), 'date': '01-01-2027'}),
      RecordExpenseDraft.fromJson({
        ...valid.toJson(),
        'taxReviewRequired': true,
      }),
      RecordExpenseDraft.fromJson({
        ...valid.toJson(),
        'lines': [
          {...baseLine, 'taxSnapshot': fabricated.toJson()},
          ...valid.lines.skip(1).map((l) => l.toJson()),
        ],
      }),
    ];
    for (final intake in invalid) {
      await expectLater(w.saveExpenseIntake(intake), throwsStateError);
      expect(await w.expenses(), isEmpty);
      expect(await w.journals(), isEmpty);
    }
    expect(
      () =>
          RecordExpenseDraft.fromJson({...valid.toJson(), 'amount': '170.00'}),
      throwsFormatException,
    );
    expect(
      () => RecordExpenseDraft.fromJson({
        ...valid.toJson(),
        'lines': [
          {...baseLine, 'tax': 'Sales tax'},
          ...valid.lines.skip(1).map((l) => l.toJson()),
        ],
      }),
      throwsFormatException,
    );
    expect(
      () => RecordExpenseDraft.fromJson({
        ...valid.toJson(),
        'taxMode': 'Withholding Tax',
      }),
      throwsFormatException,
    );
  });

  test('No Tax and configured zero code differ; legacy labels stay unresolved; recurrence requires fresh review', () async {
    final w = await AccountingWorkspace.open(':memory:');
    addTearDown(w.dispose);
    final codes = await configureExpenseTaxes(w);
    final old = draft(amount: '10.00', paymentAccountId: 'cash');
    final legacy = RecordExpenseDraft.fromJson(old.toJson());
    expect(legacy.toJson(), old.toJson());
    expect(legacy.taxMode, isNull);
    expect(legacy.taxTotals, isNull);
    for (final configured in [false, true]) {
      final zero = RecordExpenseDraft.fromJson({
        ...old.toJson(),
        'version': 2,
        'taxMode': 'Inclusive',
        'submissionId': 'zero-$configured',
        'lines': [
          ExpenseDraftLine(
            id: 'zero',
            category: old.category,
            description: '',
            tax: configured ? codes[2].choice : '0',
            taxSnapshot: configured ? codes[2] : null,
            amount: '10.00',
          ).toJson(),
        ],
      });
      final id = await w.saveExpenseIntake(zero);
      final saved = (await w.expense(id))!.draft;
      expect(saved.taxTotals!.tax.minorUnits, 0);
      expect(saved.lines.single.taxSnapshot != null, configured);
    }
    final priced = taxedExpense(codes, 'Exclusive');
    final template = RecurringExpenseTemplate(
      id: 'recurring-tax',
      revision: 1,
      sourceExpenseId: 'source',
      schedule: RecurrenceRule(
        startsOn: DateTime.utc(2027),
        unit: RecurrenceUnit.months,
        every: 1,
      ),
      defaults: priced,
    );
    final pending = template.occurrenceAt(0)!.suggestion;
    expect(pending.taxReviewRequired, isTrue);
    expect(pending.lines.first.taxSnapshot!.choice, codes[0].choice);
    expect(pending.taxTotals!.total.minorUnits, 18300);
    await expectLater(
      w.saveExpenseIntake(
        RecordExpenseDraft.fromJson({
          ...pending.toJson(),
          'submissionId': 'unreviewed-schedule',
        }),
      ),
      throwsStateError,
    );
    expect(await w.expenses(), hasLength(2));
  });
}
