import 'package:flutter/material.dart';

import '../../../app/accounting_components.dart';
import '../../../app/accounting_theme.dart';
import '../../../app/frontend_review.dart';
import '../../../core/dates/accounting_date.dart';
import '../../../core/documents/receipt_document.dart';
import '../../../core/ids/entity_id.dart';
import '../../../core/money/money.dart';
import '../application/accounting_workspace.dart';
import '../data/accounting_database.dart';
import '../application/tax_remittance_candidate.dart';
import '../domain/tax_activity_report.dart';
import '../domain/tax_remittance.dart';
import 'attachment_preview_dialog.dart';
import 'widgets/accounting_formatters.dart';

String _text(Map<String, Object?> values, String key) =>
    '${values[key] ?? ''}'.trim();
DateTime _date(Map<String, Object?> values, String key) =>
    parseAccountingInputDate(_text(values, key)) ??
    (throw FormatException('Enter a valid $key.'));
String _money(BuildContext context, Money value) => formatAccountingMinor(
  context,
  BigInt.from(value.minorUnits),
  value.currency,
);
List<(String, String)> _allocationFacts(
  BuildContext context,
  TaxRemittanceAllocation allocation,
  Map<EntityId, String> accounts,
) => [
  ('Tax Agency', allocation.agency.name),
  ('Registration Number', allocation.agency.registrationNumber),
  ('Agency Revision', '${allocation.agency.revision}'),
  (
    'Tax Account',
    accounts[allocation.liabilityAccountId] ??
        allocation.liabilityAccountId.value,
  ),
  ('Period From', formatAccountingInputDate(allocation.periodFrom)),
  ('Period Through', formatAccountingInputDate(allocation.periodThrough)),
  ('Amount', _money(context, allocation.amount)),
];

/// Shared live editor for the existing Tax Payments route. Financial eligibility
/// remains owned by the workspace commands.
class TaxRemittanceEditor extends StatefulWidget {
  const TaxRemittanceEditor({
    super.key,
    required this.workspace,
    this.linkExisting = false,
    this.initial,
  });
  final AccountingWorkspace workspace;
  final bool linkExisting;
  final Map<String, Object?>? initial;
  @override
  State<TaxRemittanceEditor> createState() => _TaxRemittanceEditorState();
}

class _TaxRemittanceEditorState extends State<TaxRemittanceEditor> {
  final _allocations = <TaxRemittanceAllocation>[];
  late final _paymentAccounts = widget.workspace.taxRemittancePaymentAccounts;
  late final _accounts = {
    for (final r in widget.workspace.taxRemittanceLiabilityAccounts)
      r.account.id: r.account.displayName,
  };
  late final _candidates = {
    if (widget.linkExisting)
      for (final p in _paymentAccounts)
        for (final c in widget.workspace.taxRemittanceCandidates(p.id))
          '${p.id}/${c.journal.entry.id.value}': c,
  };
  List<(String, String)> _candidateFacts(TaxRemittanceCandidate c) => [
    (
      'Bank Account',
      _paymentAccounts.singleWhere((p) => p.id == c.paymentAccountId).name,
    ),
    ('Payment Date', formatAccountingInputDate(c.journal.entry.date)),
    ('Journal ID', c.journal.entry.id.value),
    ('Journal Memo', c.journal.entry.memo),
    ('Available To Link', _money(context, c.available)),
    for (final entry in c.remaining.entries)
      (
        'Available · ${_accounts[entry.key] ?? entry.key.value}',
        _money(context, entry.value),
      ),
  ];
  Future<void> _editAllocation([int? index]) async {
    final w = widget.workspace, agencies = w.taxAgencies;
    final original = index == null ? null : _allocations[index];
    TaxRemittanceAllocation? reviewed;
    TaxRemittanceAllocation resolve(Map<String, Object?> v) =>
        TaxRemittanceAllocation(
          agency: agencies.singleWhere(
            (a) => a.choice == _text(v, 'Tax Agency'),
            orElse: () => throw StateError('Choose a saved tax agency.'),
          ),
          liabilityAccountId: EntityId.parse(_text(v, 'Tax Account')),
          periodFrom: _date(v, 'Period From'),
          periodThrough: _date(v, 'Period Through'),
          amount: Money.fromDecimal(_text(v, 'Amount'), w.identity.currency),
        );
    await showDialog<void>(
      context: context,
      builder: (_) => FrontendFormDialog(
        form: DesignForm(
          original == null ? 'Add Tax Allocation' : 'Edit Tax Allocation',
          [
            DesignField(
              'Tax Agency',
              required: true,
              choiceLabels: {for (final a in agencies) a.choice: a.name},
            ),
            DesignField(
              'Tax Account',
              required: true,
              choiceLabels: {
                for (final entry in _accounts.entries)
                  entry.key.value: entry.value,
              },
            ),
            const DesignField('Period From', required: true),
            const DesignField('Period Through', required: true),
            DesignField(
              'Amount',
              required: true,
              currencyCode: w.identity.currency,
            ),
          ],
          description: 'Allocate part of the payment to a saved tax agency and period. This does not calculate a statutory return.',
        ),
        initial: original == null
            ? null
            : {
                'Tax Agency': original.agency.choice,
                'Tax Account': original.liabilityAccountId.value,
                'Period From': formatAccountingInputDate(original.periodFrom),
                'Period Through': formatAccountingInputDate(
                  original.periodThrough,
                ),
                'Amount': formatAccountingInputAmount(original.amount),
              },
        reviewInformationRowsBuilder: (v) {
          final a = resolve(v);
          if (!_accounts.containsKey(a.liabilityAccountId)) {
            throw StateError('Choose an eligible tax-liability account.');
          }
          if (_allocations.indexed.any(
            (e) => e.$1 != index && e.$2.key == a.key,
          )) {
            throw StateError(
              'This agency, account and period already has an allocation. Edit it instead.',
            );
          }
          reviewed = a;
          return _allocationFacts(context, a, _accounts);
        },
        onCommit: (_) async {
          final a =
              reviewed ?? (throw StateError('Review this allocation first.'));
          setState(() {
            if (index == null) {
              _allocations.add(a);
            } else {
              _allocations[index] = a;
            }
          });
        },
      ),
    );
  }

  Future<void> Function()? _reviewedCommit;
  List<(String, String)> _review(Map<String, Object?> values) {
    _reviewedCommit = null;
    final w = widget.workspace;
    if (_allocations.isEmpty) {
      throw StateError('Add at least one tax allocation.');
    }
    final allocations = List<TaxRemittanceAllocation>.unmodifiable(
      _allocations,
    );
    final currentAgencies = w.taxAgencies.map((a) => a.choice).toSet();
    if (allocations.any((a) => !currentAgencies.contains(a.agency.choice))) {
      throw StateError(
        'An agency changed. Edit its allocation and review the current registration.',
      );
    }
    final attachments = values['_attachments'] as List? ?? const [];
    final files = values['_files'] as List? ?? const [];
    if (attachments.length != files.length ||
        attachments.any((a) => a is! ReceiptAttachment)) {
      throw StateError('Complete or remove unavailable supporting documents.');
    }
    final evidence = List<ReceiptAttachment>.unmodifiable(
      attachments.cast<ReceiptAttachment>(),
    );
    final total = allocations.map((a) => a.amount).reduce((a, b) => a + b);
    final reference = _text(values, 'Reference'), memo = _text(values, 'Memo');
    if (reference.isEmpty || reference.length > 120 || memo.length > 2000) {
      throw const FormatException(
        'Reference must be 1–120 characters; Memo may contain up to 2,000.',
      );
    }
    final request = EntityId.random();
    DateTime? recordedAt;
    final facts = <(String, String)>[];
    if (widget.linkExisting) {
      final candidate =
          _candidates[_text(values, 'Existing Payment')] ??
          (throw StateError('Choose an eligible posted payment.'));
      final current = w
          .taxRemittanceCandidates(candidate.paymentAccountId)
          .where((c) => c.journal.entry.id == candidate.journal.entry.id)
          .firstOrNull;
      if (current == null ||
          w.database.taxRemittanceJournalFingerprint(current.journal) !=
              w.database.taxRemittanceJournalFingerprint(candidate.journal)) {
        throw StateError(
          'The payment changed or is no longer eligible. Reopen Link Existing Payment.',
        );
      }
      final requested = <EntityId, Money>{};
      for (final a in allocations) {
        requested.update(
          a.liabilityAccountId,
          (v) => v + a.amount,
          ifAbsent: () => a.amount,
        );
      }
      if (requested.entries.any(
        (e) => e.value.minorUnits > (current.remaining[e.key]?.minorUnits ?? 0),
      )) {
        throw StateError(
          'Allocation exceeds the current available payment amount.',
        );
      }
      facts.addAll(_candidateFacts(current));
      facts.add(('Posting', 'Link attribution only; no new bank movement.'));
      facts.add((
        'Unallocated After Link',
        _money(context, current.available - total),
      ));
      _reviewedCommit = () async {
        recordedAt ??= DateTime.now().toUtc();
        w.linkTaxRemittance(
          requestId: request,
          reviewedJournal: candidate.journal,
          paymentAccountId: candidate.paymentAccountId,
          allocations: allocations,
          attachments: evidence,
          reference: reference,
          memo: memo,
          recordedAt: recordedAt!,
        );
      };
    } else {
      final bank = w.taxRemittancePaymentAccounts
          .where((p) => p.id == _text(values, 'Bank Account'))
          .firstOrNull;
      if (bank == null) {
        throw StateError('Choose an eligible company bank or cash account.');
      }
      final date = _date(values, 'Payment Date');
      facts.addAll([
        ('Bank Account', bank.name),
        ('Payment Date', formatAccountingInputDate(date)),
        (
          'Posting',
          'Debit allocated tax liabilities; credit the selected bank. This records an external payment already made.',
        ),
      ]);
      final debits = <EntityId, Money>{};
      for (final a in allocations) {
        debits.update(
          a.liabilityAccountId,
          (v) => v + a.amount,
          ifAbsent: () => a.amount,
        );
      }
      facts.addAll([
        for (final e in debits.entries)
          (
            'Debit · ${_accounts[e.key] ?? e.key.value}',
            _money(context, e.value),
          ),
        ('Credit · ${bank.name}', _money(context, total)),
      ]);
      _reviewedCommit = () async {
        recordedAt ??= DateTime.now().toUtc();
        w.recordTaxRemittance(
          requestId: request,
          paymentAccountId: bank.id,
          allocations: allocations,
          attachments: evidence,
          paidOn: date,
          reference: reference,
          memo: memo,
          recordedAt: recordedAt!,
        );
      };
    }
    facts.addAll([
      ('Reference', reference),
      ('Memo', memo),
      ('Payment Allocation Total', _money(context, total)),
    ]);
    for (final (i, a) in allocations.indexed) {
      facts.add(('Allocation', '${i + 1}'));
      facts.addAll(_allocationFacts(context, a, _accounts));
    }
    facts.addAll([
      ('Supporting Documents', '${evidence.length}'),
      for (final a in evidence) ('Document', '${a.filename} · ${a.originalId}'),
      (
        'Book Status',
        'Recorded attribution does not establish bank reconciliation, filing or statutory settlement.',
      ),
    ]);
    return facts;
  }

  @override
  Widget build(BuildContext context) => FrontendFormDialog(
    key: ValueKey(
      widget.linkExisting ? 'tax-link-editor' : 'tax-record-editor',
    ),
    form: DesignForm(
      widget.linkExisting ? 'Link Existing Tax Payment' : 'Record Tax Payment',
      [
        if (widget.linkExisting)
          DesignField(
            'Existing Payment',
            required: true,
            choiceLabels: {
              for (final e in _candidates.entries)
                e.key:
                    '${_paymentAccounts.singleWhere((p) => p.id == e.value.paymentAccountId).name} · ${formatAccountingInputDate(e.value.journal.entry.date)} · ${_money(context, e.value.available)} available · ${e.value.journal.entry.id.value}',
            },
          )
        else ...[
          DesignField(
            'Bank Account',
            required: true,
            choiceLabels: {for (final p in _paymentAccounts) p.id: p.name},
          ),
          const DesignField('Payment Date', required: true),
        ],
        const DesignField('Reference', required: true),
        const DesignField('Memo', multiline: true),
      ],
      evidence: true,
      description: widget.linkExisting
          ? 'Link an existing posted tax-liability payment. No new bank movement is posted.'
          : 'Record a tax payment already made outside Audyt. Review the liability and bank posting before saving.',
    ),
    initial: widget.initial,
    reviewInformationRowsBuilder: _review,
    onCommit: (_) async =>
        (_reviewedCommit ??
        (throw StateError('Review the exact payment first.')))(),
    additionalContentBuilder: (context, values, reviewing) {
      if (reviewing) return const SizedBox.shrink();
      final c = _candidates[_text(values, 'Existing Payment')];
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: accountingContentInset),
          if (c != null) ...[
            AccountingInformationRows(rows: _candidateFacts(c)),
            const SizedBox(height: accountingContentInset),
          ],
          Row(
            children: [
              Expanded(
                child: accountingFieldLabel(
                  context,
                  'Tax Allocations',
                  alignToField: true,
                  guidance: [
                    'Add the agency, period, liability account and amount for each allocation.',
                    if (widget.workspace.taxAgencies.isEmpty ||
                        _accounts.isEmpty)
                      'Configure a saved tax agency and an active sales-tax liability mapping first.',
                    if (!widget.linkExisting && _paymentAccounts.isEmpty) 'Configure an active company bank or cash account linked to its ledger account first.',
                    if (widget.linkExisting && _candidates.isEmpty) 'No eligible unallocated payments. Existing payments must debit mapped tax liabilities and credit an eligible company bank or cash account, with an unallocated amount available.',
                  ].join(' '),
                ),
              ),
              const SizedBox(width: accountingContentInset),
              accountingCompactAdd(
                context,
                key: const ValueKey('tax-allocation-add'),
                tooltip: 'Add Tax Allocation',
                onPressed:
                    widget.workspace.taxAgencies.isEmpty || _accounts.isEmpty
                    ? null
                    : () => _editAllocation(),
              ),
            ],
          ),
          if (_allocations.isNotEmpty) ...[
            const SizedBox(height: accountingContentInset),
            AccountingRecordList(
              paginationKey: 'staged-tax-allocations',
              children: [
                for (final (i, a) in _allocations.indexed)
                  AccountingRecordRow(
                    key: ValueKey('tax-allocation-$i'),
                    topRightInfo: true,
                    title: a.agency.name,
                    details: Text(
                      '${formatAccountingInputDate(a.periodFrom)} – ${formatAccountingInputDate(a.periodThrough)} · ${_accounts[a.liabilityAccountId]}',
                      style: AccountingTypography.value(context),
                    ),
                    trailing: Text(
                      _money(context, a.amount),
                      style: AccountingTypography.value(context),
                    ),
                    actions: [
                      AccountingRecordActions(
                        trailing: [
                          AccountingButton.iconOnly(
                            context,
                            key: ValueKey('tax-allocation-edit-$i'),
                            onPressed: () => _editAllocation(i),
                            icon: Icons.edit_outlined,
                            tooltip: 'Edit Tax Allocation',
                          ),
                          accountingCompactRemove(
                            context,
                            key: ValueKey('tax-allocation-remove-$i'),
                            onPressed: () =>
                                setState(() => _allocations.removeAt(i)),
                            tooltip: 'Remove Tax Allocation',
                          ),
                        ],
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ],
      );
    },
  );
}

Future<void> showTaxRemittance(
  BuildContext context,
  AccountingWorkspace w,
  TaxRemittance source,
) async {
  final correction = w.database.readTaxRemittanceCorrection(
    w.identity.businessId,
    source.id,
  );
  final accounts = {
    for (final a in await w.accounts()) a.account.id: a.account.displayName,
  };
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) => AccountingDialog.alert(
      context,
      widthFamily: AccountingPopoutWidthFamily.normal,
      title: source.reference,
      maxContentWidth: AccountingPopoutTokens.normalContentWidth,
      fixedContentWidth: AccountingPopoutTokens.normalContentWidth,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SelectionArea(
            child: AccountingInformationRows(
              rows: [
                (
                  'Origin',
                  source.origin == TaxRemittanceOrigin.recorded
                      ? 'Recorded Payment'
                      : 'Linked Existing Payment',
                ),
                (
                  'Status',
                  correction == null
                      ? 'Recorded In Books'
                      : correction.kind == TaxRemittanceCorrectionKind.unlink
                      ? 'Attribution Unlinked'
                      : 'Payment Reversed',
                ),
                ('Payment Date', formatAccountingInputDate(source.paidOn)),
                (
                  'Bank Account',
                  accounts[source.bankAccountId] ?? source.bankAccountId.value,
                ),
                ('Amount', _money(context, source.total)),
                ('Memo', source.memo),
                ('Payment ID', source.id.value),
                ('Journal ID', source.journalId.value),
                ('Journal Revision', '${source.journalRevision}'),
                ('Recorded At', source.recordedAt.toIso8601String()),
                for (final (i, a) in source.allocations.indexed) ...[
                  ('Allocation', '${i + 1}'),
                  ..._allocationFacts(context, a, accounts),
                ],
                if (correction != null) ...[
                  ('Correction Date', formatAccountingInputDate(correction.on)),
                  ('Correction Reason', correction.reason),
                  ('Correction ID', correction.id.value),
                  if (correction.journalId != null)
                    ('Correction Journal', correction.journalId!.value),
                ],
                (
                  'Book Status',
                  'This record does not establish bank reconciliation, filing or statutory settlement.',
                ),
              ],
            ),
          ),
          if (source.attachments.isNotEmpty) ...[
            const SizedBox(height: accountingContentInset),
            AccountingAttachmentList(
              paginationKey: 'tax-remittance-evidence',
              children: [
                for (final a in source.attachments)
                  AccountingAttachmentRecordRow(
                    attachment: a,
                    actions: [
                      AccountingButton.iconOnly(
                        context,
                        key: ValueKey('tax-payment-evidence-${a.originalId}'),
                        onPressed: () => showAttachmentPreview(context, a),
                        icon: Icons.visibility_outlined,
                        tooltip: 'View Supporting Document',
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ],
      ),
      actions: [],
    ),
  );
}

Future<void> correctTaxRemittance(
  BuildContext context,
  AccountingWorkspace w,
  TaxRemittance source,
) {
  final unlink = source.origin == TaxRemittanceOrigin.linked;
  DateTime? date, recordedAt;
  String? reason;
  EntityId? request;
  return showDialog<void>(
    context: context,
    builder: (_) => FrontendFormDialog(
      form: DesignForm(
        unlink ? 'Unlink Tax Attribution' : 'Reverse Tax Payment',
        const [
          DesignField('Correction Date', required: true),
          DesignField('Reason', required: true, multiline: true),
        ],
        description: unlink
            ? 'Remove this tax attribution while preserving the existing journal and original record.'
            : 'Post an exact reversal while preserving the original payment, allocations and evidence.',
      ),
      initial: {'Correction Date': formatAccountingInputDate(DateTime.now())},
      reviewInformationRowsBuilder: (v) {
        date = _date(v, 'Correction Date');
        reason = _text(v, 'Reason');
        if (reason!.isEmpty || reason!.length > 500) {
          throw const FormatException('Enter a reason of 1–500 characters.');
        }
        request = EntityId.random();
        recordedAt = null;
        return [
          ('Reference', source.reference),
          ('Amount', _money(context, source.total)),
          ('Correction Date', formatAccountingInputDate(date!)),
          ('Reason', reason!),
          (
            'Effect',
            unlink
                ? 'Unlink attribution only. Preserve the bank and liability journal.'
                : 'Reverse the bank credit and every tax-liability debit exactly.',
          ),
          ('Original Journal', source.journalId.value),
        ];
      },
      onCommit: (_) async {
        recordedAt ??= DateTime.now().toUtc();
        w.correctTaxRemittance(
          requestId: request!,
          reviewedRemittance: source,
          on: date!,
          recordedAt: recordedAt!,
          reason: reason!,
        );
      },
    ),
  );
}

Future<void> showTaxRemittanceAccountTrace(
  BuildContext context,
  AccountingWorkspace w,
  TaxActivityReport report,
  TaxAccountActivity account,
) => showDialog<void>(
  context: context,
  builder: (context) {
    String amount(BigInt n) =>
        formatAccountingMinor(context, n, w.identity.currency);
    return AccountingDialog.alert(
      context,
      widthFamily: AccountingPopoutWidthFamily.normal,
      title: account.balance.account.displayName,
      maxContentWidth: AccountingPopoutTokens.normalContentWidth,
      fixedContentWidth: AccountingPopoutTokens.normalContentWidth,
      content: SelectionArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AccountingInformationRows(
              rows: [
                ('Opening Balance', amount(account.openingCredit)),
                ('Source Sales Tax', amount(account.sourceSalesTax)),
                ('Recorded Tax Payments', amount(account.remittanceCredit)),
                (
                  'Unattributed Movement',
                  amount(account.unattributedMovementCredit),
                ),
                ('Closing Balance', amount(account.closingCredit)),
              ],
            ),
            for (final m in account.movements) ...[
              const SizedBox(height: accountingContentInset),
              AccountingInformationRows(
                rows: [
                  ('Posted Date', formatAccountingInputDate(m.journal.date)),
                  ('Journal ID', m.journal.id.value),
                  ('Memo', m.journal.memo),
                  ('Source Sales Tax', amount(m.sourceSalesTax)),
                  ('Recorded Tax Payments', amount(m.remittanceCredit)),
                  (
                    'Unattributed Movement',
                    amount(m.unattributedMovementCredit),
                  ),
                  ('Net Credit Movement', amount(m.movementCredit)),
                  for (final r in m.remittances)
                    (
                      'Payment Reference',
                      '${r.source.reference}${r.reversal == null ? '' : ' · Reversal'}',
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [],
    );
  },
);
