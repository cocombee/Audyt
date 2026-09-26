import 'package:flutter/material.dart';

import '../../../app/accounting_components.dart';
import '../../../app/accounting_theme.dart';
import '../../../core/dates/accounting_date.dart';
import '../../accounting/application/accounting_workspace.dart';
import '../../accounting/domain/claimant_statement.dart';
import '../../accounting/presentation/widgets/accounting_formatters.dart';

class ClaimantStatementsDialog extends StatefulWidget {
  const ClaimantStatementsDialog({super.key, required this.workspace});
  final AccountingWorkspace workspace;
  @override
  State<ClaimantStatementsDialog> createState() =>
      _ClaimantStatementsDialogState();
}

class _ClaimantStatementsDialogState extends State<ClaimantStatementsDialog> {
  final _from = TextEditingController(
    text: formatAccountingInputDate(DateTime(DateTime.now().year)),
  );
  final _through = TextEditingController(
    text: formatAccountingInputDate(DateTime.now()),
  );
  ClaimantStatementReport? _report;
  String? _error;
  bool _busy = false;
  int _generation = 0;
  late DateTime _appliedFrom, _appliedThrough;
  @override
  void initState() {
    super.initState();
    _appliedFrom = parseAccountingInputDate(_from.text)!;
    _appliedThrough = parseAccountingInputDate(_through.text)!;
    widget.workspace.addListener(_load);
    _load();
  }

  @override
  void didUpdateWidget(covariant ClaimantStatementsDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspace != widget.workspace) {
      oldWidget.workspace.removeListener(_load);
      widget.workspace.addListener(_load);
      _report = null;
      _load();
    }
  }

  @override
  void dispose() {
    _generation++;
    widget.workspace.removeListener(_load);
    _from.dispose();
    _through.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final report = await widget.workspace.claimantStatements(
        from: _appliedFrom,
        through: _appliedThrough,
      );
      if (mounted && generation == _generation) {
        setState(() => _report = report);
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(
          () => _error = error is StateError ? error.message.toString() : 'Claimant balances could not be loaded. Retry after checking the source records.',
        );
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  void _run() {
    final from = parseAccountingInputDate(_from.text),
        through = parseAccountingInputDate(_through.text);
    if (from == null || through == null || from.isAfter(through)) {
      setState(
        () => _error = 'Enter valid dates with the start on or before the end.',
      );
      return;
    }
    _appliedFrom = from;
    _appliedThrough = through;
    _load();
  }

  String _amount(BigInt value) =>
      formatAccountingMinor(context, value, widget.workspace.identity.currency);
  Future<void> _view(ClaimantStatement statement) => showDialog<void>(
    context: context,
    builder: (context) => AccountingDialog.alert(
      context,
      key: const ValueKey('claimant-statement-detail'),
      title: statement.claimantName,
      description:
          statement.identity?.label ??
          'Unlinked Recorded Name · Separate Claim',
      fixedContentWidth: 600,
      maxContentWidth: 600,
      content: SelectionArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AccountingInformationRows(
              rows: [
                ('Claimant ID', statement.identity?.payeeId ?? statement.key),
                ('Opening Amount Owed', _amount(statement.openingMinor)),
                ('Period Movement', _amount(statement.movementMinor)),
                ('Closing Amount Owed', _amount(statement.closingMinor)),
              ],
            ),
            for (final event in statement.events)
              Padding(
                padding: const EdgeInsets.only(top: accountingContentInset),
                child: AccountingInformationRows(
                  rows: [
                    ('Transaction', event.label),
                    ('Posting Date', formatAccountingInputDate(event.date)),
                    ('Recorded Claimant', event.claim.claimantName),
                    ('Claimant Type', event.claim.claimantIdentityLabel),
                    ('Merchant', event.claim.vendorName),
                    ('Amount Owed Change', _amount(event.balanceChangeMinor)),
                    if (event.reference.isNotEmpty)
                      ('Payment Reference', event.reference),
                    ('Business Purpose', event.claim.businessPurpose),
                    ('Claim ID', event.claim.id.value),
                    ('Journal ID', event.journalId.value),
                    ('Liability Account ID', event.accountId.value),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [],
    ),
  );
  Future<void> _control(
    ClaimantControlBalance balance,
    ClaimantStatementReport report,
  ) => showDialog<void>(
    context: context,
    builder: (context) => AccountingDialog.alert(
      context,
      title: balance.ledgerBalance.account.displayName,
      fixedContentWidth: 600,
      maxContentWidth: 600,
      content: SelectionArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AccountingInformationRows(
              rows: [
                (
                  'Ledger Opening Credit',
                  _amount(-balance.ledgerBalance.openingNetDebit),
                ),
                ('Claimant Opening', _amount(balance.attributedOpeningMinor)),
                ('Other Opening', _amount(balance.otherOpeningMinor)),
                (
                  'Claimant Period Movement',
                  _amount(balance.attributedMovementMinor),
                ),
                ('Other Period Movement', _amount(balance.otherMovementMinor)),
                (
                  'Ledger Closing Credit',
                  _amount(-balance.ledgerBalance.endingNetDebit),
                ),
                ('Claimant Closing', _amount(balance.attributedClosingMinor)),
                ('Other Closing', _amount(balance.otherClosingMinor)),
                ('Account ID', balance.ledgerBalance.account.id.value),
              ],
            ),
            for (final entry in report.ledger.activityFor(
              balance.ledgerBalance.account.id,
            ))
              Padding(
                padding: const EdgeInsets.only(top: accountingContentInset),
                child: AccountingInformationRows(
                  rows: [
                    ('Posting Date', formatAccountingInputDate(entry.date)),
                    ('Memo', entry.memo),
                    (
                      'Credit Balance Change',
                      _amount(
                        entry.lines
                            .where(
                              (l) =>
                                  l.accountId ==
                                  balance.ledgerBalance.account.id,
                            )
                            .fold(
                              BigInt.zero,
                              (n, l) =>
                                  n +
                                  BigInt.from(l.amount.minorUnits) *
                                      (l.isDebit ? -BigInt.one : BigInt.one),
                            ),
                      ),
                    ),
                    ('Journal ID', entry.id.value),
                    if (entry.reversesId != null)
                      ('Reverses Journal', entry.reversesId!.value),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [],
    ),
  );
  @override
  Widget build(BuildContext context) {
    final report = _report;
    return AccountingDialog.alert(
      context,
      key: const ValueKey('claimant-balances-dialog'),
      title: 'Claimant Balances',
      description: 'Amounts the company owes employees and directors from recognized claims.',
      fixedContentWidth: 600,
      maxContentWidth: 600,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: accountingContentInset,
            runSpacing: accountingContentInset,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              for (final field in [
                ('From', _from, 'claimant-from'),
                ('Through', _through, 'claimant-through'),
              ])
                SizedBox(
                  width: accountingCompactDateFieldWidth,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      accountingFieldLabel(context, field.$1),
                      const SizedBox(height: accountingFieldLabelGap),
                      TextField(
                        controller: field.$2,
                        key: ValueKey(field.$3),
                        enabled: !_busy,
                        inputFormatters: [const DateInputFormatter()],
                        decoration:
                            accountingSingleLineInputDecoration(
                              context,
                              hintText: 'DD-MM-YYYY',
                            ).copyWith(
                              suffixIcon: accountingCalendarButton(
                                context,
                                controller: field.$2,
                                label: field.$1,
                                enabled: !_busy,
                              ),
                            ),
                      ),
                    ],
                  ),
                ),
              AccountingButton.primary(
                context,
                key: const ValueKey('claimant-run'),
                onPressed: _busy ? null : _run,
                child: const Text('Run Report'),
              ),
            ],
          ),
          const SizedBox(height: accountingContentInset),
          if (_error != null)
            AccountingAlert.build(
              context,
              title: 'Report Needs Review',
              description: _error!,
              tone: AccountingAlertTone.critical,
            ),
          if (_busy) const LinearProgressIndicator(),
          if (report != null) ...[
            AccountingRecordList(
              paginationKey: 'claimant-balances',
              emptyState: const Padding(
                padding: accountingContentPadding,
                child: Text('No recognized claims through this date.'),
              ),
              children: [
                for (final statement in report.statements)
                  AccountingRecordRow(
                    topRightInfo: true,
                    title: statement.claimantName,
                    details: Text(
                      statement.identity?.label ??
                          'Unlinked Recorded Name · Separate Claim',
                      style: AccountingTypography.value(context),
                    ),
                    trailing: Text(
                      _amount(statement.closingMinor),
                      style: AccountingTypography.value(context),
                    ),
                    actions: [
                      AccountingRecordActions(
                        trailing: [
                          AccountingButton.iconOnly(
                            context,
                            key: ValueKey('claimant-view-${statement.key}'),
                            onPressed: () => _view(statement),
                            icon: Icons.visibility_outlined,
                            tooltip: 'View ${statement.claimantName}',
                          ),
                        ],
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: accountingContentInset),
            AccountingSummaryTableCard(
              title: 'Liability Controls',
              description: 'Claimant balances reconcile to the posted liability accounts.',
              labelHeader: 'Account',
              valueHeader: 'Closing Credit',
              rows: [
                for (final control in report.controls)
                  (
                    control.ledgerBalance.account.displayName,
                    _amount(-control.ledgerBalance.endingNetDebit),
                  ),
              ],
              note: 'Other ledger balances are not assigned to a person. Unlinked historical claims stay separate; negative balances need review as possible advances or corrections.',
            ),
            if (report.controls.isNotEmpty) ...[
              const SizedBox(height: accountingContentInset),
              AccountingRecordList(
                paginationKey: 'claimant-controls',
                children: [
                  for (final control in report.controls)
                    AccountingRecordRow(
                      title: control.ledgerBalance.account.displayName,
                      details: Text(
                        'Claimants ${_amount(control.attributedClosingMinor)} · Other ${_amount(control.otherClosingMinor)}',
                        style: AccountingTypography.value(context),
                      ),
                      trailing: AccountingRecordActions(
                        trailing: [
                          AccountingButton.iconOnly(
                            context,
                            key: ValueKey(
                              'claimant-control-${control.ledgerBalance.account.id.value}',
                            ),
                            onPressed: () => _control(control, report),
                            icon: Icons.visibility_outlined,
                            tooltip: 'View liability reconciliation',
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: accountingContentInset),
            AccountingSummaryTableCard(
              title: 'Currently Awaiting Review',
              description: 'Current submitted claims awaiting approval.',
              labelHeader: 'Workflow',
              valueHeader: 'Records',
              rows: [('Awaiting Review', '${report.awaitingReview.length}')],
              note: 'Current submitted claims, independent of the report dates. These amounts are not included in recognized claimant balances. Period-end accrual review is separate.',
            ),
            if (report.awaitingReview.isNotEmpty) ...[
              const SizedBox(height: accountingContentInset),
              AccountingRecordList(
                paginationKey: 'claimant-pending-review',
                children: [
                  for (final claim in report.awaitingReview)
                    AccountingRecordRow(
                      topRightInfo: true,
                      title: claim.claimantName,
                      details: Text(
                        '${claim.vendorName} · ${claim.claimantIdentityLabel}',
                        style: AccountingTypography.value(context),
                      ),
                      trailing: Text(
                        formatAccountingMoney(context, claim.amount),
                        style: AccountingTypography.value(context),
                      ),
                      actions: [
                        AccountingRecordActions(
                          trailing: [
                            AccountingButton.iconOnly(
                              context,
                              key: ValueKey(
                                'claimant-pending-${claim.id.value}',
                              ),
                              onPressed: () => showDialog<void>(
                                context: context,
                                builder: (context) => AccountingDialog.alert(
                                  context,
                                  title: claim.claimantName,
                                  description: 'Submitted / To Review',
                                  fixedContentWidth: 600,
                                  maxContentWidth: 600,
                                  content: SelectionArea(
                                    child: AccountingInformationRows(
                                      rows: [
                                        (
                                          'Claimant Type',
                                          claim.claimantIdentityLabel,
                                        ),
                                        (
                                          'Claimant ID',
                                          claim.claimantIdentity?.payeeId ??
                                              'Unlinked Recorded Name',
                                        ),
                                        ('Merchant', claim.vendorName),
                                        (
                                          'Claim Amount',
                                          formatAccountingMoney(
                                            context,
                                            claim.amount,
                                          ),
                                        ),
                                        (
                                          'Incurred Date',
                                          formatAccountingInputDate(
                                            claim.incurredOn!,
                                          ),
                                        ),
                                        (
                                          'Business Purpose',
                                          claim.businessPurpose,
                                        ),
                                        ('Claim ID', claim.id.value),
                                      ],
                                    ),
                                  ),
                                  actions: [],
                                ),
                              ),
                              icon: Icons.visibility_outlined,
                              tooltip: 'View submitted claim',
                            ),
                          ],
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ],
        ],
      ),
      actions: [],
    );
  }
}
