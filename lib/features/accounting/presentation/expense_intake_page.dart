import '../../../../app/responsive.dart';
import 'attachment_preview_dialog.dart';
import 'record_expense_page.dart';
import '../domain/payee.dart';
import 'expense_recurrence_dialog.dart';
import '../domain/recurring_expense_template.dart';
import 'journal_workspace_page.dart';

import 'package:flutter/material.dart';

import '../../../../app/accounting_components.dart';
import '../../../../app/accounting_theme.dart';
import '../../../../core/dates/accounting_date.dart';
import '../../../../core/money/currency_presentation.dart';
import '../application/accounting_workspace.dart';
import '../domain/expense_intake.dart';
import '../data/accounting_database.dart';
import '../../../../core/ids/entity_id.dart';
import 'widgets/accounting_layout.dart';
import 'widgets/accounting_formatters.dart';

/// The existing saved Expense form and exact revision/review commands shared
/// by Expenses and its originating Claim tab. No separate Claim form is built.
Future<void> showCurrentExpenseEditor(
  BuildContext context,
  AccountingWorkspace workspace,
  ExpenseIntakeRecord record, {
  bool forceReadOnly = false,
  Future<List<Payee>> Function(String)? employeePayeeSearch,
  ExpenseAttachmentsPicker? onAttachmentsPick,
}) async {
  final locked =
      forceReadOnly ||
      record.summary.isArchived ||
      (record.summary.journalId != null &&
          workspace.database.isJournalReconciled(
            workspace.identity.businessId,
            record.summary.journalId!,
          ));
  final canReview = !locked;
  await showDialog<void>(
    context: context,
    builder: (routeContext) => RecordExpensePage(
      employeePayeeSearch: employeePayeeSearch,
      preferences: workspace.preferences,
      settingsWorkspace: workspace,
      includeTopSafeArea: false,
      savedDraft: record.draft,
      readOnly: locked,
      onAttachmentsPick: onAttachmentsPick,
      recordActions: [
        if (canReview &&
            (!record.summary.isPosted || record.summary.hasPendingRevision))
          AccountingButton.outline(
            routeContext,
            key: ValueKey('review-expense-posting-${record.summary.id.value}'),
            onPressed: () async {
              final saved = await workspace.expense(record.summary.id);
              if (!routeContext.mounted || saved == null) return;
              Navigator.pop(routeContext);
              if (!context.mounted) return;
              await showExpenseJournalReview(context, workspace, saved);
            },
            child: const Text('Review Saved Posting'),
          ),
        if (record.summary.journalId != null)
          (locked ? AccountingButton.primary : AccountingButton.outline)(
            routeContext,
            key: ValueKey('view-expense-journal-${record.summary.id.value}'),
            onPressed: () => showPostedJournal(
              routeContext,
              workspace,
              record.summary.journalId!,
            ),
            child: const Text('View Journal'),
          ),
      ],
      accounts: workspace.paymentAccounts,
      payeeStore: workspace.payees,
      onPaymentAccountSave: workspace.savePaymentAccount,
      onSave: (replacement) async {
        if (record.summary.isPosted) {
          workspace.saveExpenseRevision(
            expenseId: record.summary.id,
            requestId: EntityId.random(),
            expectedSourceJournalId: record.summary.journalId!,
            expectedSourceExpenseRevision: record.summary.revision,
            expectedRevision: record.currentRevision?.revision ?? 0,
            expected: record.draft,
            replacement: replacement,
            savedAt: DateTime.now().toUtc(),
          );
        } else {
          await workspace.updateExpenseIntake(
            id: record.summary.id,
            expected: record.draft,
            replacement: replacement,
            expectedRevision: record.summary.revision,
          );
        }
      },
      onSavedReview: !canReview
          ? null
          : () async {
              final saved = await workspace.expense(record.summary.id);
              if (!routeContext.mounted || saved == null) return;
              Navigator.pop(routeContext);
              if (!context.mounted) return;
              await showExpenseJournalReview(context, workspace, saved);
            },
      onSaved: () => Navigator.pop(routeContext),
      onCancel: () => Navigator.pop(routeContext),
    ),
  );
}

class ExpenseIntakePage extends StatefulWidget {
  const ExpenseIntakePage({
    super.key,
    required this.workspace,
    this.compact = false,
    required this.onRecordExpense,
    this.beforeReviewExpense,
    this.employeePayeeSearch,
  });
  final AccountingWorkspace workspace;
  final Future<List<Payee>> Function(String)? employeePayeeSearch;
  final bool compact;
  final VoidCallback onRecordExpense;
  final Future<bool> Function()? beforeReviewExpense;
  @override
  State<ExpenseIntakePage> createState() => _ExpenseIntakePageState();
}

class _ExpenseIntakePageState extends State<ExpenseIntakePage> {
  List<ExpenseIntakeSummary>? _expenses;
  Map<String, ExpenseIntakeRecord> _records = {};
  List<String> _categories = const [];
  List<String> _payees = const [];
  int _total = 0;
  int _offset = 0;
  int _controlCount = 0;
  int _limit = AccountingRecordPageSizes.read('expense');
  int _loadRevision = 0;
  int _removedCount = 0;
  bool _showRemoved = false;
  String? _changingId;
  String? _error;
  String? _statusFilter;
  String? _categoryFilter;
  String? _payeeFilter;

  void _filter(VoidCallback update) {
    setState(() {
      update();
      _offset = 0;
    });
    _load();
  }

  Widget _filters(BuildContext context) => Wrap(
    spacing: accountingContentInset,
    runSpacing: AccountingPageControlScope.runGapOf(context),
    crossAxisAlignment: WrapCrossAlignment.end,
    children: [
      AccountingRecordFilter(
        label: 'Status',
        options: const ['Posted', 'Needs Review'],
        value: _statusFilter,
        controlKey: const ValueKey('expense-status-filter'),
        onChanged: (value) => _filter(() => _statusFilter = value),
      ),
      AccountingRecordFilter(
        label: 'Category',
        options: _categories,
        value: _categoryFilter,
        controlKey: const ValueKey('expense-category-filter'),
        onChanged: (value) => _filter(() => _categoryFilter = value),
      ),
      AccountingRecordFilter(
        label: 'Payee',
        options: _payees,
        value: _payeeFilter,
        controlKey: const ValueKey('expense-payee-filter'),
        onChanged: (value) => _filter(() => _payeeFilter = value),
      ),
      if (_statusFilter != null ||
          _categoryFilter != null ||
          _payeeFilter != null)
        AccountingButton.outline(
          context,
          key: const ValueKey('expense-clear-filters'),
          onPressed: () => _filter(() {
            _statusFilter = null;
            _categoryFilter = null;
            _payeeFilter = null;
          }),
          child: const Text('Clear'),
        ),
    ],
  );
  @override
  void initState() {
    super.initState();
    widget.workspace.addListener(_load);
    _load();
  }

  @override
  void didUpdateWidget(covariant ExpenseIntakePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspace == widget.workspace) return;
    oldWidget.workspace.removeListener(_load);
    widget.workspace.addListener(_load);
    _loadRevision++;
    _expenses = null;
    _records = {};
    _categories = const [];
    _payees = const [];
    _total = 0;
    _offset = 0;
    _statusFilter = null;
    _showRemoved = false;
    _removedCount = 0;
    _changingId = null;
    _categoryFilter = null;
    _payeeFilter = null;
    _load();
  }

  @override
  void dispose() {
    widget.workspace.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final revision = ++_loadRevision;
    try {
      final database = widget.workspace.database;
      final businessId = widget.workspace.identity.businessId;
      final removedCount = database
          .readExpenseIntakePage(
            businessId: businessId,
            archived: true,
            limit: 1,
          )
          .total;
      final options = database.expenseIntakeFilterOptions(
        businessId,
        archived: _showRemoved,
      );
      final controlCount = database
          .readExpenseIntakePage(
            businessId: businessId,
            archived: _showRemoved,
            limit: 1,
          )
          .total;
      final showControls = AccountingRecordControlsPolicy.visible(controlCount);
      final page = database.readExpenseIntakePage(
        businessId: businessId,
        archived: _showRemoved,
        posted: !showControls || _statusFilter == null
            ? null
            : _statusFilter == 'Posted',
        category: showControls ? _categoryFilter : null,
        payee: showControls ? _payeeFilter : null,
        offset: showControls ? _offset : 0,
        limit: _limit,
      );
      final records = await Future.wait(
        page.records.map(
          (summary) => widget.workspace.expense(
            summary.id,
            includeArchived: _showRemoved,
          ),
        ),
      );
      if (mounted && revision == _loadRevision) {
        setState(() {
          _controlCount = controlCount;
          _removedCount = removedCount;
          _categories = options.categories;
          _payees = options.payees;
          _total = page.total;
          _offset = page.offset;
          _records = {
            for (final record in records.whereType<ExpenseIntakeRecord>())
              record.summary.id.value: record,
          };
          _expenses = page.records;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Saved expenses could not be loaded. Your records have not been replaced.',
        );
      }
    }
  }

  bool _expenseLocked(ExpenseIntakeSummary summary) =>
      summary.isArchived ||
      (summary.journalId != null &&
          widget.workspace.database.isJournalReconciled(
            widget.workspace.identity.businessId,
            summary.journalId!,
          ));

  Future<void> _editSavedExpense(ExpenseIntakeRecord record) =>
      showCurrentExpenseEditor(
        context,
        widget.workspace,
        record,
        employeePayeeSearch: widget.employeePayeeSearch,
      );

  Future<void> _showSavedSuggestions() async {
    try {
      final suggestions = widget.workspace.database.recurringExpenseSuggestions(
        widget.workspace.identity.businessId,
      );
      if (!mounted) return;
      final selected = await showDialog<RecurringExpenseOccurrence>(
        context: context,
        builder: (context) => AccountingDialog.alert(
          context,
          widthFamily: suggestions.isEmpty
              ? AccountingPopoutWidthFamily.dialog
              : AccountingPopoutWidthFamily.wider,
          title: 'Saved Recurring Suggestions',
          description: suggestions.isEmpty ? null : 'Review a suggestion to record an expense. Saved occurrences remain linked to their expense.',
          titleGuidance: suggestions.isEmpty
              ? 'Review a suggestion to record an expense. Saved occurrences remain linked to their expense.'
              : null,
          content: SizedBox(
            width: suggestions.isEmpty
                ? AccountingPopoutTokens.dialogContentWidth
                : AccountingPopoutTokens.widerContentWidth,
            child: SingleChildScrollView(
              child: suggestions.isEmpty
                  ? accountingHelperText(
                      context,
                      'No recurring suggestions have been prepared.',
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AccountingRecordList(
                          paginationKey: 'recurring-expense-suggestions',
                          children: [
                            for (final occurrence in suggestions)
                              AccountingRecordRow(
                                title: occurrence.suggestion.payee,
                                details: Text(
                                  '${occurrence.suggestion.date} · Schedule revision ${occurrence.templateRevision} · ${occurrence.suggestion.tax}',
                                ),
                                topRightInfo: true,
                                status: occurrence.savedExpenseId == null
                                    ? null
                                    : AccountingBadge.build(
                                        context,
                                        label: 'Expense Saved',
                                      ),
                                trailing: Text(
                                  currencyAmountLabel(
                                    occurrence.suggestion.currencyCode,
                                    occurrence.suggestion.amount,
                                  ),
                                  style: AccountingTypography.fieldLabel(
                                    context,
                                  ),
                                ),
                                trailingBelow: occurrence.savedExpenseId != null
                                    ? null
                                    : AccountingRecordActions(
                                        trailing: [
                                          AccountingButton.iconOnly(
                                            context,
                                            key: ValueKey(
                                              'review-recurring-${occurrence.identity}',
                                            ),
                                            onPressed: () => Navigator.pop(
                                              context,
                                              occurrence,
                                            ),
                                            icon: Icons.edit_outlined,
                                            tooltip: 'Review Expense',
                                          ),
                                        ],
                                      ),
                              ),
                          ],
                        ),
                      ],
                    ),
            ),
          ),
          actions: [],
        ),
      );
      if (selected != null && mounted) {
        final allowed = await widget.beforeReviewExpense?.call() ?? true;
        if (!allowed || !mounted) return;
        await showDialog<void>(
          context: context,
          builder: (routeContext) => RecordExpensePage(
            employeePayeeSearch: widget.employeePayeeSearch,
            preferences: widget.workspace.preferences,
            settingsWorkspace: widget.workspace,
            includeTopSafeArea: false,
            currencyCode: selected.suggestion.currencyCode,
            recurringSuggestion: selected.suggestion,
            accounts: widget.workspace.paymentAccounts,
            payeeStore: widget.workspace.payees,
            onPaymentAccountSave: widget.workspace.savePaymentAccount,
            onSave: (draft) async {
              await widget.workspace.saveExpenseIntake(
                draft,
                recurringOccurrenceIdentity: selected.identity,
              );
            },
            onSaved: () => Navigator.pop(routeContext),
            onCancel: () => Navigator.pop(routeContext),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Saved recurring suggestions could not be loaded.'),
          ),
        );
      }
    }
  }

  Future<void> _showRecurring() async {
    try {
      var due = await widget.workspace.database.prepareDueRecurringExpenses(
        widget.workspace.identity.businessId,
        through: DateTime.now(),
      );
      var templates = widget.workspace.database.recurringExpenseTemplates(
        widget.workspace.identity.businessId,
      );
      if (!mounted) return;
      final offsets = <String, int>{};
      await showDialog<void>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, updateScheduleView) => AccountingDialog.alert(
            context,
            widthFamily: templates.isEmpty
                ? AccountingPopoutWidthFamily.dialog
                : AccountingPopoutWidthFamily.wider,
            title: 'Recurring Expenses',
            description: templates.isEmpty ? null : 'Due suggestions are prepared for review. Nothing is paid or posted.',
            titleGuidance: templates.isEmpty
                ? 'Due suggestions are prepared for review. Nothing is paid or posted.'
                : null,
            content: SizedBox(
              width: templates.isEmpty
                  ? AccountingPopoutTokens.dialogContentWidth
                  : AccountingPopoutTokens.widerContentWidth,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AccountingControlFlow(
                      children: [
                        if (due.hasMore)
                          AccountingButton.outline(
                            context,
                            key: const ValueKey('recurring-prepare-more'),
                            onPressed: () async {
                              try {
                                final next = await widget.workspace.database
                                    .prepareDueRecurringExpenses(
                                      widget.workspace.identity.businessId,
                                      through: DateTime.now(),
                                    );
                                if (context.mounted) {
                                  updateScheduleView(() => due = next);
                                }
                              } catch (_) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Some due suggestions could not be prepared. Retry to continue.',
                                      ),
                                    ),
                                  );
                                }
                              }
                            },
                            child: const Text('Prepare More Due Suggestions'),
                          ),
                        AccountingButton.outline(
                          context,
                          key: const ValueKey('recurring-saved-suggestions'),
                          onPressed: _showSavedSuggestions,
                          child: const Text('Saved Suggestions'),
                        ),
                      ],
                    ),
                    const SizedBox(height: accountingContentInset),
                    if (templates.isEmpty)
                      accountingHelperText(
                        context,
                        'Set recurrence when recording an expense to add a schedule.',
                      ),
                    if (templates.isNotEmpty)
                      AccountingRecordList(
                        paginationKey: 'recurring-expenses',
                        children: [
                          for (final template in templates)
                            Column(
                              key: ValueKey(
                                'recurring-expense-row-${template.id}',
                              ),
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                AccountingRecordRow(
                                  title: template.payee.isEmpty
                                      ? 'Unnamed Payee'
                                      : template.payee,
                                  status: AccountingBadge.build(
                                    context,
                                    label: template.paused
                                        ? 'Paused'
                                        : 'Active',
                                  ),
                                  details: Text(
                                    'Starts ${formatAccountingInputDate(template.schedule.startsOn)} · Every ${template.schedule.every} ${template.schedule.unit.name}',
                                  ),
                                  trailing: AccountingRecordActions(
                                    trailing: [
                                      AccountingButton.iconOnly(
                                        context,
                                        key: ValueKey(
                                          'recurring-edit-${template.id}',
                                        ),
                                        onPressed: () async {
                                          final schedule =
                                              await showExpenseRecurrenceDialog(
                                                context,
                                                startsOn:
                                                    template.schedule.startsOn,
                                                initial: template.schedule,
                                              );
                                          if (schedule == null ||
                                              !context.mounted) {
                                            return;
                                          }
                                          try {
                                            final revised =
                                                RecurringExpenseTemplate.fromJson(
                                                  {
                                                    ...template.toJson(),
                                                    'revision':
                                                        template.revision + 1,
                                                    'schedule': schedule
                                                        .toJson(),
                                                  },
                                                );
                                            widget.workspace.database
                                                .saveRecurringExpenseTemplate(
                                                  widget
                                                      .workspace
                                                      .identity
                                                      .businessId,
                                                  revised,
                                                );
                                            final refreshed = widget
                                                .workspace
                                                .database
                                                .recurringExpenseTemplates(
                                                  widget
                                                      .workspace
                                                      .identity
                                                      .businessId,
                                                );
                                            updateScheduleView(() {
                                              templates = refreshed;
                                              offsets[template.id] = 0;
                                            });
                                          } catch (_) {
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                    const SnackBar(
                                                      content: Text(
                                                        'Schedule could not be saved. Reopen it and try again.',
                                                      ),
                                                    ),
                                                  );
                                            }
                                          }
                                        },
                                        icon: Icons.edit_outlined,
                                        tooltip: 'Edit Schedule',
                                      ),

                                      AccountingButton.iconOnly(
                                        context,
                                        key: ValueKey(
                                          'recurring-toggle-${template.id}',
                                        ),
                                        onPressed: () {
                                          try {
                                            widget.workspace.database
                                                .saveRecurringExpenseTemplate(
                                                  widget
                                                      .workspace
                                                      .identity
                                                      .businessId,
                                                  template.withPaused(
                                                    !template.paused,
                                                  ),
                                                );
                                            final refreshed = widget
                                                .workspace
                                                .database
                                                .recurringExpenseTemplates(
                                                  widget
                                                      .workspace
                                                      .identity
                                                      .businessId,
                                                );
                                            updateScheduleView(
                                              () => templates = refreshed,
                                            );
                                          } catch (_) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                                  const SnackBar(
                                                    content: Text(
                                                      'Schedule could not be changed. Reopen it and try again.',
                                                    ),
                                                  ),
                                                );
                                          }
                                        },
                                        icon: template.paused
                                            ? Icons.play_arrow_outlined
                                            : Icons.pause_outlined,
                                        tooltip: template.paused
                                            ? 'Resume Schedule'
                                            : 'Pause Schedule',
                                      ),
                                    ],
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    accountingContentInset,
                                    0,
                                    accountingContentInset,
                                    accountingContentInset,
                                  ),
                                  child: AccountingButtonSizeScope(
                                    child: AccountingControlFlow(
                                      children: [
                                        if (template.paused)
                                          const Text(
                                            'Existing suggestions are preserved. Resume to review dates individually.',
                                          ),
                                        if (!template.paused)
                                          for (
                                            var index =
                                                offsets[template.id] ?? 0;
                                            index <
                                                (offsets[template.id] ?? 0) + 6;
                                            index++
                                          )
                                            if (template.schedule.occurrenceAt(
                                                  index,
                                                )
                                                case final date?)
                                              if (!_expenses!.any(
                                                (expense) =>
                                                    expense.id.value ==
                                                        template
                                                            .sourceExpenseId &&
                                                    expense.occurredOn.year ==
                                                        date.year &&
                                                    expense.occurredOn.month ==
                                                        date.month &&
                                                    expense.occurredOn.day ==
                                                        date.day,
                                              ))
                                                AccountingButton.outline(
                                                  context,
                                                  key: ValueKey(
                                                    'prepare-recurring-${template.id}-$index',
                                                  ),
                                                  onPressed: () async {
                                                    try {
                                                      final suggestion = widget
                                                          .workspace
                                                          .database
                                                          .prepareRecurringExpenseOccurrence(
                                                            widget
                                                                .workspace
                                                                .identity
                                                                .businessId,
                                                            template.id,
                                                            expectedRevision:
                                                                template
                                                                    .revision,
                                                            index: index,
                                                          );
                                                      if (!context.mounted) {
                                                        return;
                                                      }
                                                      await showDialog<void>(
                                                        context: context,
                                                        builder: (reviewContext) => AccountingDialog.alert(
                                                          reviewContext,
                                                          widthFamily:
                                                              AccountingPopoutWidthFamily
                                                                  .wider,
                                                          title: 'Recurring Suggestion',
                                                          description: 'Saved for review. This is not a recorded expense or payment.',
                                                          content: Column(
                                                            mainAxisSize:
                                                                MainAxisSize
                                                                    .min,
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .stretch,
                                                            children: [
                                                              _detail(
                                                                reviewContext,
                                                                'Date',
                                                                suggestion.date,
                                                              ),
                                                              _detail(
                                                                reviewContext,
                                                                'Payee',
                                                                suggestion
                                                                    .payee,
                                                              ),
                                                              _detail(
                                                                reviewContext,
                                                                'Amount',
                                                                currencyAmountLabel(
                                                                  suggestion
                                                                      .currencyCode,
                                                                  suggestion
                                                                      .amount,
                                                                ),
                                                              ),
                                                              _detail(
                                                                reviewContext,
                                                                'Tax',
                                                                suggestion.tax,
                                                              ),
                                                              const Text(
                                                                'Open Saved Suggestions to review the amount, category, payment and new receipt evidence before recording.',
                                                              ),
                                                            ],
                                                          ),
                                                          actions: [],
                                                        ),
                                                      );
                                                    } catch (_) {
                                                      if (context.mounted) {
                                                        ScaffoldMessenger.of(
                                                          context,
                                                        ).showSnackBar(
                                                          const SnackBar(
                                                            content: Text(
                                                              'The suggestion could not be prepared. Reopen the schedule and try again.',
                                                            ),
                                                          ),
                                                        );
                                                      }
                                                    }
                                                  },
                                                  child: Text(
                                                    'Prepare ${formatAccountingInputDate(date)}',
                                                  ),
                                                ),
                                        if (!template.paused)
                                          AccountingControlFlow(
                                            children: [
                                              AccountingButton.outline(
                                                context,
                                                key: ValueKey(
                                                  'recurring-earlier-${template.id}',
                                                ),
                                                onPressed:
                                                    (offsets[template.id] ??
                                                            0) ==
                                                        0
                                                    ? null
                                                    : () => updateScheduleView(
                                                        () =>
                                                            offsets[template
                                                                    .id] =
                                                                (offsets[template
                                                                        .id] ??
                                                                    0) -
                                                                6,
                                                      ),
                                                child: const Text(
                                                  'Earlier Dates',
                                                ),
                                              ),
                                              AccountingButton.outline(
                                                context,
                                                key: ValueKey(
                                                  'recurring-later-${template.id}',
                                                ),
                                                onPressed:
                                                    template.schedule
                                                            .occurrenceAt(
                                                              (offsets[template
                                                                          .id] ??
                                                                      0) +
                                                                  6,
                                                            ) ==
                                                        null
                                                    ? null
                                                    : () => updateScheduleView(
                                                        () =>
                                                            offsets[template
                                                                    .id] =
                                                                (offsets[template
                                                                        .id] ??
                                                                    0) +
                                                                6,
                                                      ),
                                                child: const Text(
                                                  'Later Dates',
                                                ),
                                              ),
                                            ],
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            actions: [],
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Recurring schedules could not be loaded.'),
          ),
        );
      }
    }
  }

  Future<void> _view(ExpenseIntakeSummary summary) async {
    try {
      final workspace = widget.workspace;
      final record = await workspace.expense(
        summary.id,
        includeArchived: _showRemoved,
      );
      if (!mounted || workspace != widget.workspace) {
        return;
      }
      if (record == null) {
        throw StateError('The saved expense could not be found.');
      }
      await _editSavedExpense(record);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'The expense could not be opened. Check storage and try again.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _reviewPosting(ExpenseIntakeSummary summary) async {
    final saved = await widget.workspace.expense(summary.id);
    if (!mounted) return;
    if (saved == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The saved expense could not be found.')),
      );
      return;
    }
    await showExpenseJournalReview(context, widget.workspace, saved);
  }

  Future<void> _changeRemovedState(ExpenseIntakeSummary expense) async {
    if (_changingId != null) return;
    final workspace = widget.workspace;
    final restoring = expense.isArchived;
    final confirmed = await AccountingDialog.showFixed<bool>(
      context: context,
      contentWidth: AccountingPopoutTokens.dialogContentWidth,
      builder: (dialogContext) => AccountingDialog.alert(
        dialogContext,
        widthFamily: AccountingPopoutWidthFamily.dialog,
        title: restoring ? 'Restore Expense' : 'Remove Expense',
        content: Text(
          restoring ? 'Restore this expense to the active list for review?' : 'Remove this unposted expense from the active list? Its details and receipts are retained in Removed Expenses, where you can restore it.',
        ),
        actions: [
          AccountingButton.ghost(
            dialogContext,
            key: const ValueKey('expense-cancel-removal'),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          if (restoring)
            AccountingButton.primary(
              dialogContext,
              key: const ValueKey('expense-confirm-removal'),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Restore'),
            )
          else
            AccountingButton.destructive(
              dialogContext,
              key: const ValueKey('expense-confirm-removal'),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Remove'),
            ),
        ],
      ),
    );
    if (confirmed != true ||
        !mounted ||
        workspace != widget.workspace ||
        _changingId != null) {
      return;
    }
    setState(() => _changingId = expense.id.value);
    try {
      workspace.setExpenseIntakeArchived(
        id: expense.id,
        expectedRevision: expense.revision,
        archived: !restoring,
      );
      await _load();
    } on StateError catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'The expense could not be changed. Reload and try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _changingId = null);
    }
  }

  String? _removalRestriction(ExpenseIntakeSummary expense) =>
      widget.workspace.database.expenseRemovalRestriction(
        widget.workspace.identity.businessId,
        expense.id,
      );

  Widget _detail(BuildContext context, String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        accountingFieldLabel(context, label),
        const SizedBox(height: 4),
        Text(value),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) => AccountingPageShell(
    includeTopSafeArea: !widget.compact,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AccountingPageHeader(
          routeLabel: 'Expenses',
          title: 'Expenses',
          titleKey: 'page-title-expenses-vendors',
          description: 'Keep receipt intake and posted expenses together, with their accounting status visible.',
          action: AccountingButton.primary(
            context,
            key: const ValueKey('intake-record-expense'),
            onPressed: widget.onRecordExpense,
            leadingIcon: Icons.add_rounded,
            child: const Text('Record Expense'),
          ),
          secondaryActions: [
            AccountingButton.outline(
              context,
              key: const ValueKey('expense-open-recurring'),
              onPressed: _showRecurring,
              child: const Text('Recurring'),
            ),
          ],
        ),
        const SizedBox(height: accountingContentInset),
        if (_removedCount > 0 || _showRemoved) ...[
          AccountingControlFlow(
            children: [
              AccountingButton.outline(
                context,
                key: const ValueKey('expense-toggle-removed'),
                onPressed: _changingId != null
                    ? null
                    : () => _filter(() {
                        _showRemoved = !_showRemoved;
                        _statusFilter = null;
                        _categoryFilter = null;
                        _payeeFilter = null;
                      }),
                child: Text(
                  _showRemoved
                      ? 'Active Expenses'
                      : 'Removed Expenses ($_removedCount)',
                ),
              ),
            ],
          ),
          const SizedBox(height: accountingContentInset),
        ],
        if (AccountingRecordControlsPolicy.visible(_controlCount) &&
            _expenses != null &&
            (_categories.isNotEmpty ||
                _payees.isNotEmpty ||
                _statusFilter != null ||
                _categoryFilter != null ||
                _payeeFilter != null)) ...[
          _filters(context),
          const SizedBox(height: 16),
          if (_total == 0)
            const Padding(
              padding: EdgeInsets.symmetric(
                horizontal: accountingContentInset,
                vertical: 16,
              ),
              child: Text('No expenses match these filters.'),
            ),
        ],
        if (_error != null) ...[
          AccountingPageText(_error!),
          AccountingButton.outline(
            context,
            key: null,
            onPressed: _load,
            leadingIcon: Icons.refresh_outlined,
            child: const Text('Retry'),
          ),
        ] else if (_expenses == null)
          const LinearProgressIndicator()
        else if (_expenses!.isEmpty &&
            _statusFilter == null &&
            _categoryFilter == null &&
            _payeeFilter == null)
          AccountingCard.surface(
            context,
            child: Padding(
              padding: accountingContentPadding,
              child: Text(
                _showRemoved ? 'No Removed Expenses' : 'No Saved Expenses',
                style: AccountingTypography.sectionTitle(context),
              ),
            ),
          )
        else if (_expenses!.isNotEmpty)
          AccountingRecordList(
            totalCount: _controlCount,
            paginationKey: 'expense-intake-1',
            externalPagination: Padding(
              padding: accountingContentPadding,
              child: AccountingRecordPagination(
                unfilteredTotal: _controlCount,
                total: _total,
                offset: _offset,
                pageSize: _limit,
                keyPrefix: 'expense',
                onPageSizeChanged: (size) => _filter(() => _limit = size),
                onPrevious: _offset == 0
                    ? null
                    : () {
                        _offset = (_offset - _limit).clamp(0, _total);
                        _load();
                      },
                onNext: _offset + _limit >= _total
                    ? null
                    : () {
                        _offset += _limit;
                        _load();
                      },
              ),
            ),
            children: [
              for (final expense in _expenses!)
                KeyedSubtree(
                  key: ValueKey(expense.id.value),
                  child: Padding(
                    padding: accountingContentPadding,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AccountingRecordRow(
                          topRightInfo: true,
                          padding: EdgeInsets.zero,
                          title: expense.payee.isEmpty
                              ? expense.category
                              : expense.payee,
                          status: AccountingBadge.build(
                            context,
                            label: expense.isArchived
                                ? 'Removed'
                                : expense.isPosted &&
                                      !expense.hasPendingRevision
                                ? 'Posted'
                                : 'Needs Review',
                            key: ValueKey('expense-status-${expense.id.value}'),
                          ),
                          statusWidth: AccountingBadge.measuredWidth(
                            context,
                            expense.isArchived
                                ? 'Removed'
                                : expense.isPosted &&
                                      !expense.hasPendingRevision
                                ? 'Posted'
                                : 'Needs Review',
                          ),
                          compactStatus:
                              (expense.isPosted &&
                                      !expense.hasPendingRevision) ||
                                  expense.isArchived
                              ? null
                              : Tooltip(
                                  message: 'Needs Review',
                                  child: AccountingBadge.build(
                                    context,
                                    label: 'Review',
                                  ),
                                ),
                          details: Text(
                            '${expense.category} · ${formatAccountingInputDate(expense.occurredOn)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AccountingTypography.helper(context),
                          ),
                          trailing: Text(
                            formatAccountingMoney(context, expense.amount),
                            style: AccountingTypography.fieldLabel(context),
                          ),
                          trailingBelow: AccountingRecordActions(
                            actions: [
                              AccountingOverflowMenu(
                                triggerKey: ValueKey(
                                  'expense-more-${expense.id.value}',
                                ),
                                actions: [
                                  if ((!expense.isPosted ||
                                          expense.hasPendingRevision) &&
                                      !_expenseLocked(expense) &&
                                      _records[expense.id.value]
                                              ?.draft
                                              .claimSource ==
                                          null)
                                    AccountingOverflowAction(
                                      key: ValueKey(
                                        'review-expense-${expense.id.value}',
                                      ),
                                      label: 'Review Posting',
                                      icon: Icons.preview_outlined,
                                      onPressed: () => _reviewPosting(expense),
                                    )
                                  else if (expense.journalId != null)
                                    AccountingOverflowAction(
                                      key: ValueKey(
                                        'journal-expense-${expense.id.value}',
                                      ),
                                      label: 'View Journal',
                                      icon: Icons.description_outlined,
                                      onPressed: () => showPostedJournal(
                                        context,
                                        widget.workspace,
                                        expense.journalId!,
                                      ),
                                    ),
                                  for (final attachment
                                      in _records[expense.id.value]
                                              ?.draft
                                              .attachments ??
                                          [])
                                    AccountingOverflowAction(
                                      key: ValueKey(
                                        'expense-row-attachment-${attachment.originalId}',
                                      ),
                                      label: 'View ${attachment.filename}',
                                      icon:
                                          attachment.originalMimeType
                                              .startsWith('image/')
                                          ? Icons.image_outlined
                                          : Icons.description_outlined,
                                      onPressed: () => showAttachmentPreview(
                                        context,
                                        attachment,
                                      ),
                                    ),
                                ],
                              ),
                            ],
                            trailing: [
                              AccountingButton.outline(
                                context,
                                key: ValueKey(
                                  'open-expense-${expense.id.value}',
                                ),
                                onPressed: () => _view(expense),
                                child: Text(
                                  _expenseLocked(expense) ? 'View' : 'Edit',
                                ),
                              ),
                              if (expense.isArchived)
                                AccountingButton.iconOnly(
                                  context,
                                  key: ValueKey(
                                    'expense-restore-${expense.id.value}',
                                  ),
                                  onPressed:
                                      _changingId != null ||
                                          _removalRestriction(expense) != null
                                      ? null
                                      : () => _changeRemovedState(expense),
                                  icon: Icons.restore,
                                  tooltip: 'Restore Expense',
                                )
                              else
                                AccountingButton.iconOnly(
                                  context,
                                  key: ValueKey(
                                    'expense-delete-${expense.id.value}',
                                  ),
                                  onPressed:
                                      _changingId != null ||
                                          _removalRestriction(expense) != null
                                      ? null
                                      : () => _changeRemovedState(expense),
                                  icon: Icons.delete_outline,
                                  tooltip:
                                      _removalRestriction(expense) ??
                                      'Remove Expense',
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
      ],
    ),
  );
}
