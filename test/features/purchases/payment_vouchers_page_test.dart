import 'dart:math' as math;

import 'package:flutter/services.dart';

import '../../app/journal_workspace_integration_test.dart'
    show captureUi, loadJournalLayoutFonts;

import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/feature_registry.dart';

import 'package:audyt/core/documents/receipt_document.dart';
import 'package:audyt/features/purchases/domain/payment_voucher.dart';
import 'package:audyt/features/purchases/domain/payment_voucher_store.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/purchases/presentation/payment_vouchers_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in [720.0, 1162.0, 1224.0]) {
    for (final existing in [false, true]) {
      testWidgets(
        'actual voucher ${existing ? 'Edit' : 'New'} guards focused Reference and backdrop at $width',
        (t) async {
          t.view.physicalSize = Size(width, 809);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.resetPhysicalSize);
          addTearDown(t.view.resetDevicePixelRatio);
          for (final font in [
            ('Inter', 'assets/fonts/Inter-Variable.woff2'),
            ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
          ]) {
            await (FontLoader(
              font.$1,
            )..addFont(rootBundle.load(font.$2))).load();
          }
          final store = PaymentVoucherStore();
          if (existing) {
            store.save(
              PaymentVoucher.create(
                id: 'guarded-voucher',
                sourceType: PaymentVoucherSourceType.directExpense,
                sourceId: 'expense-original',
                payee: 'Original payee',
                amount: Money.fromMinor(2500, 'MYR'),
                paymentAccount: 'Original account',
                paymentMethod: 'Cash',
                paymentDate: DateTime.utc(2026, 9, 1),
                reference: 'Original reference',
              ),
            );
          }
          final original = store.all.map((v) => v.toJson()).toList();
          await t.pumpWidget(
            RepaintBoundary(
              key: const ValueKey('workspace-capture'),
              child: MaterialApp(
                theme: AccountingTheme.light(),
                home: PaymentVouchersPage(store: store),
              ),
            ),
          );
          await t.pumpAndSettle();
          final open = find.byKey(
            ValueKey(
              existing
                  ? 'voucher-view-guarded-voucher'
                  : 'payment-voucher-create',
            ),
          );
          Future<void> tap(Finder target) async {
            await t.ensureVisible(target);
            await t.tap(target);
            await t.pumpAndSettle();
          }

          final close = find.byKey(const ValueKey('voucher-editor-close'));
          expect(
            find.text(
              'Confirm the source payment and bank review without another payment or expense posting.',
            ),
            findsOneWidget,
          );
          await tap(open);
          final frame = find
              .descendant(
                of: find.byKey(const ValueKey('payment-voucher-editor-dialog')),
                matching: find.byWidgetPredicate(
                  (v) => v is Material && v.type == MaterialType.card,
                ),
              )
              .first;
          final rect = t.getRect(frame);
          expect(
            rect.width,
            closeTo(
              math.min(
                AccountingPopoutTokens.widerContentWidth +
                    AccountingPopoutTokens.contentInset * 2,
                width - AccountingPopoutTokens.windowInsets.horizontal,
              ),
              .01,
            ),
          );
          expect(
            rect.left,
            greaterThanOrEqualTo(AccountingPopoutTokens.windowInsets.left),
          );
          expect(
            rect.right,
            lessThanOrEqualTo(
              width - AccountingPopoutTokens.windowInsets.right,
            ),
          );
          await captureUi(
            t,
            'Voucher ${existing ? 'Edit' : 'New'} Wider Initial ${width.toInt()}',
          );
          final sourceHelp = find.byWidgetPredicate(
            (widget) =>
                widget is AccountingFieldHelp &&
                widget.label == 'Linked source type',
          );
          final sourceMessage = t
              .widget<AccountingFieldHelp>(sourceHelp)
              .message;
          expect(find.text(sourceMessage), findsNothing);
          await tap(sourceHelp);
          expect(find.text(sourceMessage), findsOneWidget);
          await captureUi(
            t,
            'Voucher ${existing ? 'Edit' : 'New'} Source Helper ${width.toInt()}',
          );
          Tooltip.dismissAllToolTips();
          await t.pumpAndSettle();
          expect(find.text(sourceMessage), findsNothing);
          await tap(close);
          expect(find.text('Discard Unsaved Changes?'), findsNothing);
          await tap(open);
          final reference = find.byKey(const ValueKey('voucher-reference'));
          await t.ensureVisible(reference);
          await t.enterText(reference, 'Working voucher reference');
          await t.sendKeyEvent(LogicalKeyboardKey.escape);
          await t.pumpAndSettle();
          expect(find.text('Discard Unsaved Changes?'), findsOneWidget);
          await captureUi(
            t,
            'Voucher ${existing ? 'Edit' : 'New'} Focused Discard ${width.toInt()}',
          );
          await tap(find.byKey(const ValueKey('voucher-keep-editing')));
          expect(
            t.widget<TextFormField>(reference).controller!.text,
            'Working voucher reference',
          );
          await tap(close);
          await tap(find.byKey(const ValueKey('voucher-discard-close')));
          expect(
            t.widget<TextFormField>(reference).controller!.text,
            'Working voucher reference',
          );
          // Clicking outside the editor goes through the same deliberate warning.
          await t.tapAt(const Offset(2, 2));
          await t.pumpAndSettle();
          expect(find.text('Discard Unsaved Changes?'), findsOneWidget);
          await tap(find.byKey(const ValueKey('voucher-discard-changes')));
          expect(find.byType(PaymentVoucherEditorDialog), findsNothing);
          expect(store.all.map((v) => v.toJson()).toList(), original);
          await tap(open);
          expect(
            t.widget<TextFormField>(reference).controller!.text,
            existing ? 'Original reference' : '',
          );
          await tap(close);
          expect(find.text('Discard Unsaved Changes?'), findsNothing);
          expect(t.takeException(), isNull);
        },
      );
    }
  }

  for (final width in [720.0, 1224.0]) {
    testWidgets(
      'voucher attachment removal is a guarded working edit at $width',
      (t) async {
        t.view.physicalSize = Size(width, 1000);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final bytes = Uint8List.fromList('%PDF-1.7 original'.codeUnits);
        final attachment = ReceiptAttachment.queued(
          ReceiptAttachmentInput(
            originalId: 'guard-original',
            batchId: 'guard',
            filename: 'Original.pdf',
            mimeType: 'application/pdf',
            bytes: bytes,
          ),
        ).withStatus(AttachmentProcessingStatus.ready);
        final store = PaymentVoucherStore();
        store.save(
          PaymentVoucher.create(
            id: 'guard-attachment',
            sourceType: PaymentVoucherSourceType.directExpense,
            sourceId: 'expense-original',
            payee: 'Original',
            amount: Money.fromMinor(2500, 'MYR'),
            paymentAccount: 'Bank',
            paymentMethod: 'Cash',
            paymentDate: DateTime.utc(2026, 9, 1),
            reference: 'Original',
            attachments: [attachment],
          ),
        );
        final original = store.byId('guard-attachment')!.toJson();
        await t.pumpWidget(
          MaterialApp(
            theme: AccountingTheme.light(),
            home: PaymentVouchersPage(store: store),
          ),
        );
        Future<void> tap(Finder target) async {
          await t.ensureVisible(target);
          await t.tap(target);
          await t.pumpAndSettle();
        }

        final open = find.byKey(
          const ValueKey('voucher-view-guard-attachment'),
        );
        await tap(open);
        await tap(
          find.byKey(
            const ValueKey('voucher-attachment-remove-guard-original'),
          ),
        );
        await tap(find.text('Delete'));
        expect(
          find.byKey(const ValueKey('voucher-attachment-row-guard-original')),
          findsNothing,
        );
        await tap(find.byKey(const ValueKey('voucher-editor-close')));
        expect(find.text('Discard Unsaved Changes?'), findsOneWidget);
        await tap(find.byKey(const ValueKey('voucher-keep-editing')));
        expect(
          find.byKey(const ValueKey('voucher-attachment-row-guard-original')),
          findsNothing,
        );
        await tap(find.byKey(const ValueKey('voucher-editor-close')));
        await tap(find.byKey(const ValueKey('voucher-discard-changes')));
        expect(store.byId('guard-attachment')!.toJson(), original);
        await tap(open);
        expect(
          find.byKey(const ValueKey('voucher-attachment-row-guard-original')),
          findsOneWidget,
        );
        expect(
          store.byId('guard-attachment')!.attachments.single.originalBytes,
          bytes,
        );
        await tap(find.byKey(const ValueKey('voucher-editor-close')));
        expect(find.text('Discard Unsaved Changes?'), findsNothing);
        expect(t.takeException(), isNull);
      },
    );
    testWidgets(
      'explicit original voucher View stays keyboard read-only at $width',
      (t) async {
        t.view.physicalSize = Size(width, 1000);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final store = PaymentVoucherStore.demo();
        final record = store.all.firstWhere(
          (v) => v.status == PaymentVoucherStatus.approved,
        );
        final original = record.toJson();
        await t.pumpWidget(
          MaterialApp(
            theme: AccountingTheme.light(),
            home: Builder(
              builder: (context) => TextButton(
                key: ValueKey('voucher-view-${record.id}'),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => PaymentVoucherEditorDialog(
                    id: record.id,
                    initial: record,
                    readOnly: true,
                    onSaveDraft: (_) => fail('Original View must not save'),
                    onSubmit: (_) => fail('Original View must not submit'),
                  ),
                ),
                child: const Text('View Original'),
              ),
            ),
          ),
        );
        final open = find.byKey(ValueKey('voucher-view-${record.id}'));
        await t.ensureVisible(open);
        await t.tap(open);
        await t.pumpAndSettle();
        expect(find.byKey(const ValueKey('voucher-save-draft')), findsNothing);
        expect(find.byKey(const ValueKey('voucher-submit')), findsNothing);
        final reference = find.byKey(const ValueKey('voucher-reference'));
        await t.ensureVisible(reference);
        await t.tap(reference);
        await t.sendKeyEvent(LogicalKeyboardKey.keyX);
        await t.pumpAndSettle();
        expect(
          t.widget<TextFormField>(reference).controller!.text,
          record.reference,
        );
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await t.pumpAndSettle();
        expect(find.byType(PaymentVoucherEditorDialog), findsNothing);
        expect(find.text('Discard Unsaved Changes?'), findsNothing);
        expect(store.byId(record.id)!.toJson(), original);
        expect(t.takeException(), isNull);
      },
    );
  }
  for (final width in [720.0, 1224.0]) {
    for (final status in [
      PaymentVoucherStatus.pendingApproval,
      PaymentVoucherStatus.approved,
      PaymentVoucherStatus.paid,
    ]) {
      testWidgets(
        'unreconciled current voucher ${status.name} edits without draft save at $width',
        (t) async {
          t.view.physicalSize = Size(width, 1000);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.resetPhysicalSize);
          addTearDown(t.view.resetDevicePixelRatio);
          await loadJournalLayoutFonts();
          final store = PaymentVoucherStore.demo();
          final record = store.all.singleWhere((v) => v.status == status);
          final original = record.toJson();
          await t.pumpWidget(
            MaterialApp(
              theme: AccountingTheme.light(),
              builder: (_, child) => RepaintBoundary(
                key: const ValueKey('workspace-capture'),
                child: child!,
              ),
              home: PaymentVouchersPage(store: store),
            ),
          );
          final open = find.byKey(ValueKey('voucher-view-${record.id}'));
          await t.ensureVisible(open);
          expect(
            t
                .widget<Tooltip>(
                  find.ancestor(of: open, matching: find.byType(Tooltip)).first,
                )
                .message,
            'Edit',
          );
          await t.tap(open);
          await t.pumpAndSettle();
          expect(
            t
                .widget<PaymentVoucherEditorDialog>(
                  find.byType(PaymentVoucherEditorDialog),
                )
                .readOnly,
            isFalse,
          );
          expect(
            find.byKey(const ValueKey('voucher-save-draft')),
            findsNothing,
          );
          expect(find.byKey(const ValueKey('voucher-submit')), findsNothing);
          expect(
            find.text('Edit current source and payment control details.'),
            findsOneWidget,
          );
          final currentSave = find.byKey(
            const ValueKey('voucher-save-current'),
          );
          expect(currentSave, findsOneWidget);
          expect(
            find.byWidgetPredicate(
              (w) =>
                  w is ButtonStyleButton &&
                  w.key == const ValueKey('voucher-save-current') &&
                  w.onPressed == null,
            ),
            findsOneWidget,
          );
          expect(
            t
                .widget<Tooltip>(
                  find
                      .ancestor(of: currentSave, matching: find.byType(Tooltip))
                      .first,
                )
                .message,
            contains('Saving changes to this Payment Voucher is unavailable'),
          );
          await captureUi(t, 'Voucher Current ${status.name} $width');
          final reference = find.byKey(const ValueKey('voucher-reference'));
          await t.ensureVisible(reference);
          await t.enterText(reference, '${record.reference}-edited');
          await t.pumpAndSettle();
          expect(
            t.widget<TextFormField>(reference).controller!.text,
            '${record.reference}-edited',
          );
          await t.sendKeyEvent(LogicalKeyboardKey.escape);
          await t.pumpAndSettle();
          expect(find.text('Discard Unsaved Changes?'), findsOneWidget);
          await t.tap(find.byKey(const ValueKey('voucher-keep-editing')));
          await t.pumpAndSettle();
          expect(
            t.widget<TextFormField>(reference).controller!.text,
            '${record.reference}-edited',
          );
          await t.tap(find.byKey(const ValueKey('voucher-editor-close')));
          await t.pumpAndSettle();
          await t.tap(find.byKey(const ValueKey('voucher-discard-changes')));
          await t.pumpAndSettle();
          expect(find.byType(PaymentVoucherEditorDialog), findsNothing);
          expect(store.byId(record.id)!.toJson(), original);
          expect(t.takeException(), isNull);
        },
      );
    }
  }
  test('payment vouchers are registered as a Money Out destination', () {
    expect(FeatureRegistry.byPath('/payment-vouchers'), isNotNull);
  });

  testWidgets(
    'renders truthful source links and keeps approval separate from payment',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: PaymentVouchersPage(store: PaymentVoucherStore.demo()),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('page-title-payment-vouchers')),
        findsOneWidget,
      );
      expect(find.textContaining('Claim Payment'), findsWidgets);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Text &&
              (widget.data == 'Approved For Payment' ||
                  widget.data == 'Approved'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('voucher-status-voucher-claim-2026-0002')),
        findsOneWidget,
      );
      expect(find.text('Paid'), findsOneWidget);
      expect(
        find.textContaining('Confirm the source payment and bank review'),
        findsOneWidget,
      );
    },
  );

  testWidgets('records payment only after explicit confirmation', (
    tester,
  ) async {
    final store = PaymentVoucherStore.demo();
    final draft = store.save(
      PaymentVoucher.create(
        id: 'voucher-editable-test',
        sourceType: PaymentVoucherSourceType.directExpense,
        sourceId: 'expense-test',
        payee: 'Draft supplier',
        amount: Money.fromMinor(2500, 'MYR'),
        paymentAccount: 'Maybank Current',
        paymentMethod: 'Cash',
        paymentDate: DateTime.utc(2026, 9, 1),
        reference: 'PV-DRAFT',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(home: PaymentVouchersPage(store: store)),
    );
    final approved = store.all.singleWhere(
      (voucher) => voucher.status == PaymentVoucherStatus.approved,
    );
    expect(
      find.descendant(
        of: find.byKey(ValueKey('voucher-row-${draft.id}')),
        matching: find.byKey(ValueKey('voucher-view-${draft.id}')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(ValueKey('voucher-row-${approved.id}')),
        matching: find.byKey(ValueKey('voucher-view-${approved.id}')),
      ),
      findsOneWidget,
    );
    final action = find.byKey(ValueKey<String>('voucher-pay-${approved.id}'));
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(
      find.byKey(
        ValueKey<String>('voucher-payment-confirmation-${approved.id}'),
      ),
      findsOneWidget,
    );
    expect(store.byId(approved.id)?.status, PaymentVoucherStatus.approved);
    await tester.tap(
      find.byKey(ValueKey<String>('voucher-confirm-pay-${approved.id}')),
    );
    await tester.pumpAndSettle();
    expect(store.byId(approved.id)?.status, PaymentVoucherStatus.paid);
    expect(find.text('Payment recorded'), findsOneWidget);
  });

  testWidgets(
    'voucher editor uses the shared responsive fields and currency heading',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(960, 1200));
      addTearDown(() async => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(home: PaymentVouchersPage(store: PaymentVoucherStore())),
      );

      await tester.tap(find.byKey(const ValueKey('payment-voucher-create')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('voucher-editor-two-column')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('voucher-currency')), findsNothing);
      expect(find.byKey(const ValueKey('voucher-amount-prefix')), findsNothing);
      expect(find.text('Amount (RM)'), findsOneWidget);
      expect(
        tester
            .widget<InputDecorator>(
              find.descendant(
                of: find.byKey(const ValueKey('voucher-amount')),
                matching: find.byType(InputDecorator),
              ),
            )
            .decoration
            .prefixIcon,
        isNull,
      );
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('voucher-date')))
            .controller!
            .text,
        matches(RegExp(r'^\d{2}-\d{2}-\d{4}$')),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('voucher-date'))).width,
        closeTo(
          tester.getSize(find.byKey(const ValueKey('voucher-amount'))).width,
          1,
        ),
      );
      expect(
        find.byKey(const ValueKey('voucher-upload-file-action')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'voucher editor validates source and payment fields before submit',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: PaymentVouchersPage(store: PaymentVoucherStore())),
      );
      await tester.tap(find.byKey(const ValueKey('payment-voucher-create')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('voucher-submit')));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('voucher-editor-error')),
        findsOneWidget,
      );
      expect(find.textContaining('source'), findsWidgets);
    },
  );

  testWidgets('voucher draft keeps original attachment bytes when edited', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(960, 1400));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    final bytes = Uint8List.fromList('%PDF-1.7\nreceipt'.codeUnits);
    final attachment = ReceiptAttachment.queued(
      ReceiptAttachmentInput(
        originalId: 'stored-pdf',
        batchId: 'voucher-test',
        filename: 'foreign-invoice.pdf',
        mimeType: 'application/pdf',
        bytes: bytes,
      ),
    ).withStatus(AttachmentProcessingStatus.ready);
    final store = PaymentVoucherStore();
    store.save(
      PaymentVoucher.create(
        id: 'voucher-attachment-test',
        sourceType: PaymentVoucherSourceType.billSettlement,
        sourceId: 'bill-foreign-1',
        payee: 'Foreign Supplier',
        amount: Money.fromMinor(12345, 'MYR'),
        paymentAccount: 'Maybank Current',
        paymentMethod: 'Bank Transfer',
        paymentDate: DateTime.utc(2026, 9, 1),
        reference: 'PV-USD-1',
        attachments: [attachment],
      ),
    );
    await tester.pumpWidget(
      MaterialApp(home: PaymentVouchersPage(store: store)),
    );
    final open = find.byKey(
      const ValueKey('voucher-view-voucher-attachment-test'),
    );
    await tester.ensureVisible(open);
    expect(tester.widget<IconButton>(open), isNotNull);
    await tester.tap(open);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('voucher-attachment-row-stored-pdf')),
      findsOneWidget,
    );
    expect(find.text('PDF · 16 B'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('voucher-save-draft')));
    await tester.pumpAndSettle();

    final voucher = store.byId('voucher-attachment-test')!;
    expect(voucher.attachments.single.filename, 'foreign-invoice.pdf');
    expect(voucher.attachments.single.originalBytes, bytes);
    expect(voucher.attachmentNames, <String>['foreign-invoice.pdf']);
  });
}
