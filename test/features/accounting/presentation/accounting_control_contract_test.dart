import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_description_field.dart';
import 'package:audyt/app/accounting_color_library.dart';
import 'package:audyt/app/accounting_icons.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/naming_setup.dart';
import 'package:audyt/features/accounting/presentation/record_expense_page.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('expense popout fields share the right content boundary', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1224, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: const RecordExpensePage(
          includeTopSafeArea: false,
          paymentAccounts: ['Cash'],
        ),
      ),
    );
    await tester.pumpAndSettle();

    final content = tester.getRect(
      find.byKey(const ValueKey('expense-receipt-surface')),
    );
    for (final key in [
      'expense-document-number',
      'expense-field-payment-account',
      'expense-recurring-control',
    ]) {
      final field = tester.getRect(find.byKey(ValueKey(key)));
      expect(field.right, closeTo(content.right, 0.1), reason: key);
    }
    expect(find.text('Optional. Choose a payee.'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (w) => w is Tooltip && w.message == 'Optional. Choose a payee.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('setup popout keeps its heading and field gap groups', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1224, 1000));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: const Scaffold(
          body: Center(
            child: NamingSetupDialog(
              demo: true,
              kind: SetupKind.voucher,
              setupRequired: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final title = tester.getRect(find.text('Payment Voucher Setup'));
    final subtitle = tester.getRect(
      find.text('Build your filename one value at a time.'),
    );
    final alert = tester.getRect(
      find.byKey(const ValueKey('naming-setup-required-alert')),
    );
    expect(subtitle.top - title.bottom, 6);
    expect(alert.top - subtitle.bottom, 20);
    expect(
      find.textContaining('Downloads/Audyt Demo/Payment Vouchers'),
      findsWidgets,
    );

    final gaps = <double>[
      tester.getRect(find.byKey(const ValueKey('naming-folder-picker'))).top -
          tester.getRect(find.text('Save Location')).bottom,
      tester.getRect(find.byKey(const ValueKey('naming-block-frame-0'))).top -
          tester.getRect(find.text('Filename Format')).bottom,
      tester.getRect(find.byKey(const ValueKey('naming-preview-frame'))).top -
          tester.getRect(find.text('Filename Preview')).bottom,
    ];
    expect(
      gaps.reduce((a, b) => a > b ? a : b) -
          gaps.reduce((a, b) => a < b ? a : b),
      lessThanOrEqualTo(1.5),
    );
    for (final key in const ['naming-block-frame-0', 'naming-preview-frame']) {
      final frame = tester.widget<Container>(find.byKey(ValueKey(key)));
      expect(
        (frame.decoration! as BoxDecoration).color,
        AccountingTokens.light.card,
      );
    }
  });

  testWidgets('priced row groups share the title/detail visible line gap', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 800,
                child: AccountingRecordList(
                  children: [
                    AccountingRecordRow(
                      key: const ValueKey('record-row'),
                      topRightInfo: true,
                      title: 'Meridian Trading',
                      details: const Text('DEMO-PAYBILLS-3 · 03-09-2026'),
                      trailing: const Text(
                        'RM 350.00',
                        key: ValueKey('amount'),
                      ),
                      trailingBelow: AccountingRecordActions(
                        trailing: [
                          AccountingButton.outline(
                            context,
                            key: const ValueKey('view'),
                            onPressed: () {},
                            child: const Text('View'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final amount = tester.getRect(find.byKey(const ValueKey('amount')));
    final view = tester.getRect(find.byKey(const ValueKey('view')));
    final title = tester.getRect(find.text('Meridian Trading'));
    final detail = tester.getRect(find.text('DEMO-PAYBILLS-3 · 03-09-2026'));
    final row = tester.getRect(find.byKey(const ValueKey('record-row')));
    expect(
      view.top - amount.bottom,
      closeTo(accountingRecordPriceActionGap, 0.1),
    );
    expect(view.right, closeTo(amount.right, 0.1));
    expect(
      detail.top - title.bottom,
      closeTo(accountingRecordInfoLineGap, 0.1),
    );
    expect(
      (title.top + detail.bottom) / 2,
      closeTo((amount.top + view.bottom) / 2, 1),
    );
    expect(row.right - view.right, closeTo(accountingContentInset, 0.1));
    expect(row.bottom - view.bottom, closeTo(accountingContentInset, 0.1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('popup fields use the search green focused outline', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1224, 1500));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: const RecordExpensePage(includeTopSafeArea: false),
      ),
    );

    final amount = tester.widget<InputDecorator>(
      find.descendant(
        of: find.byKey(const ValueKey('expense-field-amount')),
        matching: find.byType(InputDecorator),
      ),
    );
    final focused = amount.decoration.focusedBorder! as OutlineInputBorder;
    expect(focused.borderSide.color, AccountingTokens.light.primary);
    expect(focused.borderSide.width, accountingFocusedBorderWidth);
    final themeFocused =
        AccountingTheme.light().inputDecorationTheme.focusedBorder!
            as OutlineInputBorder;
    expect(themeFocused.borderSide, focused.borderSide);
  });

  testWidgets('recurrence is selected within the expense form', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1224, 1500));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: const RecordExpensePage(),
      ),
    );

    final checkbox = find.byKey(const ValueKey('expense-recurring-control'));
    await tester.ensureVisible(checkbox);
    expect(
      find.byKey(const ValueKey('expense-recurrence-period')),
      findsNothing,
    );
    await tester.tap(checkbox);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yes').last);
    await tester.pumpAndSettle();
    final period = find.byKey(const ValueKey('expense-recurrence-period'));
    expect(period, findsOneWidget);
    await tester.tap(period);
    await tester.pumpAndSettle();
    expect(find.text('Every 5 Years'), findsOneWidget);
  });

  test('defines one compact shadcn-like control contract for Accounting', () {
    final theme = AccountingTheme.light();
    final input = theme.inputDecorationTheme;
    expect(
      input.contentPadding,
      const EdgeInsets.symmetric(
        horizontal: accountingFieldContentInset,
        vertical: 12,
      ),
    );
    expect(input.constraints?.minHeight, 44);
    expect(input.border, isA<OutlineInputBorder>());
    expect(
      (input.border! as OutlineInputBorder).borderRadius,
      BorderRadius.circular(10),
    );
    expect(theme.dialogTheme.shape, isA<RoundedRectangleBorder>());
    expect(
      (theme.dialogTheme.shape! as RoundedRectangleBorder).borderRadius,
      BorderRadius.circular(20),
    );
    expect(theme.dropdownMenuTheme.menuStyle, isNotNull);
    expect(
      (theme.checkboxTheme.shape! as RoundedRectangleBorder).borderRadius,
      BorderRadius.circular(5),
    );
    expect(
      WidgetStateProperty.resolveAs<BorderSide?>(
        theme.checkboxTheme.side!,
        const <WidgetState>{},
      )!.width,
      accountingCheckboxBorderWidth,
    );
  });

  testWidgets('popout close keeps an accessible label without a tooltip', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: Scaffold(
          body: Builder(builder: (context) => accountingCompactClose(context)),
        ),
      ),
    );
    final button = tester.widget<IconButton>(find.byType(IconButton));
    expect(button.tooltip, isNull);
    expect(find.bySemanticsLabel('Close'), findsOneWidget);
    expect(
      button.style!.side!.resolve(<WidgetState>{})!.color,
      AccountingColorLibrary.grapefruit,
    );
    expect(
      button.style!.backgroundColor!.resolve(<WidgetState>{}),
      AccountingColorLibrary.grapefruit,
    );
  });

  testWidgets('creation actions belong to their Payee and Account menus', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1224, 1500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: RecordExpensePage()));
    expect(find.text('Add Payee'), findsNothing);
    expect(find.text('Add Account'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('expense-field-payee')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('expense-add-payee')), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('expense-field-payment-account')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('expense-add-account')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'receipt dropzone exposes an explicit add action and state semantics',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1224, 1500));
      addTearDown(() async => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const MaterialApp(home: RecordExpensePage()));

      expect(
        find.byKey(const ValueKey('expense-receipt-dropzone')),
        findsOneWidget,
      );
      expect(find.text('Choose Files'), findsOneWidget);
      expect(find.text('Drop receipts here or choose files'), findsOneWidget);
      expect(find.textContaining('DOCX'), findsOneWidget);
      final semantics = tester.getSemantics(
        find.byKey(const ValueKey('expense-receipt-dropzone')),
      );
      expect(semantics.label, contains('Drop receipts here or choose files'));
    },
  );

  testWidgets('receipt dropzone keeps its dashed outline in the foreground', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1224, 1500));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: RecordExpensePage()));

    final surface = find.byKey(const ValueKey('expense-receipt-surface'));
    final customPaint = tester.widget<CustomPaint>(
      find.descendant(of: surface, matching: find.byType(CustomPaint)).first,
    );
    expect(customPaint.painter, isNull);
    final painter = customPaint.foregroundPainter;
    expect(painter, isNotNull);
    expect(painter.runtimeType.toString(), contains('DashedBorderPainter'));
    final tokens = AccountingTheme.of(tester.element(surface));
    final borderColor = (painter! as dynamic).color as Color;
    expect(borderColor, tokens.ring);
    expect(borderColor, isNot(tokens.muted));
  });

  testWidgets('receipt dropzone centers its complete content group', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1224, 1500));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: RecordExpensePage()));

    final surface = find.byKey(const ValueKey('expense-receipt-surface'));
    final content = find.byKey(const ValueKey('expense-receipt-content'));
    expect(content, findsOneWidget);

    final surfaceRect = tester.getRect(surface);
    final contentRect = tester.getRect(content);
    expect(contentRect.center.dx, closeTo(surfaceRect.center.dx, 1));
    expect(contentRect.center.dy, closeTo(surfaceRect.center.dy, 1));

    for (final textFinder in <Finder>[
      find.byKey(const ValueKey('expense-upload-prompt')),
      find.text(
        'JPEG, PNG, HEIC, PDF, DOC, or DOCX. Multiple files supported.',
      ),
    ]) {
      expect(tester.widget<Text>(textFinder).textAlign, TextAlign.center);
    }
    expect(
      tester
          .getRect(
            find.descendant(
              of: content,
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is AccountingIcon &&
                    widget.icon == Icons.description_outlined,
              ),
            ),
          )
          .center
          .dx,
      closeTo(
        tester
            .getRect(find.byKey(const ValueKey('expense-add-receipt-action')))
            .center
            .dx,
        1,
      ),
    );
  });

  testWidgets(
    'receipt dropzone keeps drag-over distinct and Choose Files accessible',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      var pickCount = 0;
      await tester.binding.setSurfaceSize(const Size(1224, 1500));
      addTearDown(() async => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: RecordExpensePage(
            onAttachmentsPick: (_) async {
              pickCount += 1;
              return const <PickedExpenseAttachment>[];
            },
          ),
        ),
      );

      final dropzone = find.byKey(const ValueKey('expense-receipt-dropzone'));
      final addReceipt = find.byKey(
        const ValueKey('expense-add-receipt-action'),
      );
      await tester.ensureVisible(dropzone);

      final dropSemanticsFinder = find
          .ancestor(of: dropzone, matching: find.byType(Semantics))
          .first;
      final dropSemantics = tester
          .getSemantics(dropSemanticsFinder)
          .getSemanticsData();
      expect(dropSemantics.flagsCollection.isButton, isTrue);
      expect(
        dropSemantics.label,
        contains('Drop receipts here or choose files'),
      );
      final addSemantics = tester.getSemantics(addReceipt).getSemanticsData();
      expect(addSemantics.flagsCollection.isButton, isTrue);
      expect(addSemantics.label, contains('Choose Files'));

      Color borderColor() {
        final surface = find.byKey(const ValueKey('expense-receipt-surface'));
        final paint = tester.widget<CustomPaint>(
          find
              .descendant(of: surface, matching: find.byType(CustomPaint))
              .first,
        );
        return ((paint.foregroundPainter! as dynamic).color as Color);
      }

      final defaultBorderColor = borderColor();
      final dropTarget = tester.widget<DropTarget>(find.byType(DropTarget));
      dropTarget.onDragEntered!(
        DropEventDetails(
          localPosition: Offset.zero,
          globalPosition: Offset.zero,
        ),
      );
      await tester.pump();
      expect(borderColor(), isNot(defaultBorderColor));

      dropTarget.onDragExited!(
        DropEventDetails(
          localPosition: Offset.zero,
          globalPosition: Offset.zero,
        ),
      );
      await tester.pump();
      expect(find.text('Drop receipts here or choose files'), findsOneWidget);

      await tester.tap(addReceipt);
      await tester.pumpAndSettle();
      expect(pickCount, 1);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'category picker omits popup titles and preserves searchable selection',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1224, 1500));
      addTearDown(() async => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const MaterialApp(home: RecordExpensePage()));

      final categorySelector = tester.widget<AccountingSelector<String>>(
        find.ancestor(
          of: find.byKey(const ValueKey('expense-category-control')),
          matching: find.byType(AccountingSelector<String>),
        ),
      );
      expect(categorySelector.menuTitle, isNull);

      await tester.tap(find.byKey(const ValueKey('expense-category-control')));
      await tester.pumpAndSettle();
      expect(find.text('Choose a category'), findsNothing);
      expect(
        find.byKey(const ValueKey('expense-category-dialog-title')),
        findsNothing,
      );
      expect(find.text('Transport & Travel'), findsOneWidget);
      expect(find.text('Petrol / Fuel'), findsOneWidget);
      final groupHeading = find.byKey(
        const ValueKey('accounting-selector-group-Personnel'),
      );
      final firstGroupItem = find.descendant(
        of: find.byKey(const ValueKey('expense-category-option-personnel')),
        matching: find.text('Personnel'),
      );
      expect(
        tester.getRect(firstGroupItem).left - tester.getRect(groupHeading).left,
        closeTo(20, 0.5),
      );
      expect(tester.widget<Text>(groupHeading).style!.fontSize, 11);
      expect(find.textContaining('Treatment:'), findsNothing);
      expect(find.textContaining('Review:'), findsNothing);

      final categorySearch = tester.widget<TextField>(
        find.byKey(const ValueKey('expense-category-search')),
      );
      expect(categorySearch.decoration!.hintText, 'Search categories');
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('expense-category-menu')),
          matching: find.byType(TextField),
        ),
        findsNothing,
      );

      await tester.enterText(
        find.byKey(const ValueKey('expense-category-search')),
        'petrol',
      );
      await tester.pump();
      expect(find.text('Petrol / Fuel'), findsOneWidget);
      await tester.tap(find.text('Petrol / Fuel'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('expense-category-menu')), findsNothing);
      expect(find.text('Petrol / Fuel'), findsOneWidget);
    },
  );

  testWidgets('tax picker omits popup titles and preserves option selection', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1224, 1500));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: RecordExpensePage()));

    final taxSelector = tester.widget<AccountingSelector<String>>(
      find.ancestor(
        of: find.byKey(const ValueKey('expense-tax-control')),
        matching: find.byType(AccountingSelector<String>),
      ),
    );
    expect(taxSelector.menuTitle, isNull);

    final tax = find.byKey(const ValueKey('expense-field-tax'));
    expect(tax, findsOneWidget);
    expect(find.byKey(const ValueKey('expense-tax-control')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('expense-tax-control')));
    await tester.pumpAndSettle();
    expect(find.text('Choose tax'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('expense-tax-menu')),
        matching: find.text('No Tax'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('expense-tax-menu')), findsOneWidget);
    expect(find.byKey(const ValueKey('tax-search-field')), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('expense-tax-menu')),
        matching: find.byType(TextField),
      ),
      findsNothing,
    );

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('expense-tax-menu')),
        matching: find.text('No Tax'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('expense-tax-menu')), findsNothing);
    expect(
      find.descendant(of: tax, matching: find.text('No Tax')),
      findsOneWidget,
    );
  });

  testWidgets('advanced accounting details are collapsed until requested', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1224, 1500));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: RecordExpensePage()));

    expect(
      find.byKey(const ValueKey('expense-advanced-details')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('expense-field-dimensions')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('expense-field-item-or-split')),
      findsOneWidget,
      reason: 'The growing line description is visible independently of advanced details.',
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('expense-advanced-details')),
    );
    await tester.tap(find.byKey(const ValueKey('expense-advanced-details')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('expense-field-dimensions')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('expense-field-item-or-split')),
      findsOneWidget,
    );
  });

  testWidgets(
    'populated advanced accounting details open without losing values',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1224, 1500));
      addTearDown(() async => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        const MaterialApp(
          home: RecordExpensePage(
            initialDimensions: 'Project Atlas / Kuala Lumpur',
            initialItemOrSplitDetails: 'Two split lines',
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey('expense-field-dimensions')),
        findsOneWidget,
      );
      expect(find.text('Project Atlas / Kuala Lumpur'), findsOneWidget);
      expect(
        tester
            .widget<AccountingDescriptionField>(
              find.byKey(const ValueKey('expense-field-item-or-split')),
            )
            .controller!
            .text,
        'Two split lines',
      );
    },
  );
}
