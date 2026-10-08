// Isolated UI proposal: actual owners and separate autocomplete geometry.
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/features/accounting/domain/payee.dart';
import 'package:audyt/features/accounting/presentation/record_expense_page.dart';
import 'package:audyt/features/accounting/presentation/widgets/payee_autocomplete_menu.dart';
import 'package:audyt/features/purchases/presentation/claims_page.dart';
import 'package:audyt/features/purchases/presentation/payment_vouchers_page.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'journal_workspace_integration_test.dart' show captureUi;

const directory = [
  Payee(
    id: 'staff',
    name: 'Nur Aina Sofea Binti Abdul Rahman',
    type: PayeeType.staff,
  ),
  Payee(id: 'director', name: 'Daniel Alexander Lim', type: PayeeType.director),
  Payee(
    id: 'supplier',
    name: 'Kumpulan Contoh Teknologi Malaysia Sdn Bhd',
    type: PayeeType.supplier,
  ),
  Payee(id: 'vendor', name: 'Alam Office Supplies', type: PayeeType.vendor),
];

Finder keyed(String value) => find.byKey(ValueKey(value));

Future<void> prepare(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await (FontLoader(
    'Inter',
  )..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2'))).load();
  await (FontLoader(
    'MaterialIcons',
  )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
}

Future<void> capturePayee(WidgetTester tester, String name) async {
  final shadows = debugDisableShadows;
  try {
    debugDisableShadows = false;
    for (final object in tester.allRenderObjects) {
      object.markNeedsPaint();
    }
    await tester.pump();
    await captureUi(tester, name);
  } finally {
    debugDisableShadows = shadows;
  }
}

Future<void> actualOwner(
  WidgetTester tester,
  String owner, {
  bool readOnly = false,
  double scale = 1,
  List<Payee> choices = directory,
}) async {
  final payees = PayeeStore(payees: choices);
  final Widget form = switch (owner) {
    'Expense' => RecordExpensePage(
      payeeStore: payees,
      readOnly: readOnly,
      includeTopSafeArea: false,
      onSave: (_) async {},
      onCancel: () {},
    ),
    'Claimant' || 'Merchant' => ClaimEditorDialog(
      id: EntityId.random(),
      payeeStore: payees,
      readOnly: readOnly,
      onSaveDraft: (_) {},
      onSubmit: (_) {},
    ),
    _ => PaymentVoucherEditorDialog(
      id: 'trial-voucher',
      payeeStore: payees,
      readOnly: readOnly,
      onSaveDraft: (_) {},
      onSubmit: (_) {},
    ),
  };
  await tester.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('workspace-capture'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AccountingTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () =>
                    showDialog<void>(context: context, builder: (_) => form),
                child: const Text('Open proposal'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open proposal'));
  await tester.pumpAndSettle();
}

void checkOneLine(WidgetTester tester, Finder menu) {
  final texts = find.descendant(of: menu, matching: find.byType(RichText));
  for (final element in texts.evaluate()) {
    final p = element.renderObject! as RenderParagraph;
    if (p.text.toPlainText() != 'Add Payee') expect(p.maxLines, 1);
    expect(p.didExceedMaxLines, isFalse);
  }
}

void main() {
  for (final width in [720.0, 1162.0, 1224.0]) {
    for (final owner in ['Expense', 'Claimant', 'Merchant', 'Voucher']) {
      testWidgets(
        '$owner actual menu fits full directory and keeps selection at $width',
        (tester) async {
          await prepare(tester, width);
          await actualOwner(tester, owner);
          final (
            fieldKey,
            menuKey,
            prefix,
            id,
            query,
            shortQuery,
            shortId,
          ) = switch (owner) {
            'Expense' => (
              'expense-field-payee',
              'expense-payee-menu',
              'expense-payee-option',
              'supplier',
              'Kumpulan',
              'Alam',
              'vendor',
            ),
            'Claimant' => (
              'claim-claimant',
              'claim-claimant-menu',
              'claim-claimant-option',
              'staff',
              'Nur',
              'Daniel',
              'director',
            ),
            'Merchant' => (
              'claim-payee',
              'claim-merchant-menu',
              'claim-merchant-option',
              'supplier',
              'Kumpulan',
              'Alam',
              'vendor',
            ),
            _ => (
              'voucher-payee',
              'voucher-payee-menu',
              'voucher-payee-option',
              'supplier',
              'Kumpulan',
              'Alam',
              'vendor',
            ),
          };
          final field = keyed(fieldKey);
          await tester.ensureVisible(field);
          await tester.enterText(field, query);
          await tester.pumpAndSettle();
          final menu = keyed(menuKey);
          final before = tester.getRect(field);
          final panel = tester.getRect(menu);
          expect(panel.width, greaterThanOrEqualTo(before.width - .01));
          expect(panel.left, greaterThanOrEqualTo(8));
          expect(panel.right, lessThanOrEqualTo(width - 8));
          checkOneLine(tester, menu);
          {
            final choice = directory.singleWhere((payee) => payee.id == id);
            final role = tester.widget<Text>(
              find.descendant(of: menu, matching: find.text(choice.typeLabel)),
            );
            expect(role.style!.fontSize, accountingSmallControlFontSize);
            expect(role.style!.fontWeight, FontWeight.w400);
            expect(
              role.style!.color,
              AccountingTheme.of(tester.element(menu)).mutedForeground,
            );
            // Keep the selected name separate from its smaller metadata label.
            final name = tester.renderObject<RenderParagraph>(
              find.descendant(of: menu, matching: find.text(choice.name)),
            );
            expect(
              (name.text as TextSpan).style!.fontSize,
              accountingControlFontSize,
            );
            final labelBox = find
                .ancestor(
                  of: find.descendant(
                    of: menu,
                    matching: find.text(choice.typeLabel),
                  ),
                  matching: find.byType(DecoratedBox),
                )
                .first;
            final nameBox = find.descendant(
              of: menu,
              matching: find.text(choice.name),
            );
            expect(
              tester.getRect(labelBox).left - tester.getRect(nameBox).right,
              greaterThanOrEqualTo(
                AccountingSelectionLabel.minimumTextGap - 0.5,
              ),
            );
          }
          await capturePayee(tester, 'Payee Scroller $owner ${width.toInt()}');
          // Filtering to a shorter name must not shrink the whole-directory width.
          await tester.enterText(field, shortQuery);
          await tester.pumpAndSettle();
          expect(tester.getRect(menu).width, closeTo(panel.width, .01));
          final row = tester.getRect(keyed('$prefix-$shortId'));
          final x = panel.left < before.left
              ? panel.left + 10
              : panel.right - 10;
          await tester.tapAt(Offset(x, row.center.dy));
          await tester.pumpAndSettle();
          expect(
            tester.widget<TextFormField>(field).controller!.text,
            directory.singleWhere((p) => p.id == shortId).name,
          );
          expect(menu, findsNothing);
          expect(tester.getRect(field), before);
          // Keyboard activation of the first Add action preserves free entry
          // when its existing creation dialog is cancelled.
          const typed = 'A name not in the directory';
          await tester.enterText(field, typed);
          await tester.pumpAndSettle();
          await tester.testTextInput.receiveAction(TextInputAction.next);
          await tester.pumpAndSettle();
          if (owner == 'Expense') {
            expect(keyed('payee-name-field'), findsOneWidget);
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          } else {
            await tester.tap(
              keyed(
                owner == 'Voucher'
                    ? 'voucher-add-payee-cancel'
                    : 'claim-add-payee-cancel',
              ),
            );
          }
          await tester.pumpAndSettle();
          expect(tester.widget<TextFormField>(field).controller!.text, typed);
          await tester.tap(field);
          // The autocomplete keeps its keyboard selection owner.
          await tester.enterText(field, query);
          await tester.pumpAndSettle();
          await tester.sendKeyEvent(
            LogicalKeyboardKey.arrowDown,
          ); // Add is first for every owner.
          await tester.testTextInput.receiveAction(TextInputAction.next);
          await tester.pumpAndSettle();
          expect(
            tester.widget<TextFormField>(field).controller!.text,
            directory.singleWhere((p) => p.id == id).name,
          );
          expect(menu, findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'open directory follows parent shrink and expansion, including its clickable overflow',
    (tester) async {
      await prepare(tester, 720);
      final fieldAnchor = GlobalKey();
      final payee = directory.first;
      var width = 600.0;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(20),
              child: Align(
                alignment: Alignment.topRight,
                child: StatefulBuilder(
                  builder: (context, setState) {
                    update = setState;
                    return SizedBox(
                      width: width,
                      child: Autocomplete<Payee>(
                        optionsBuilder: (value) => [payee],
                        displayStringForOption: (p) => p.name,
                        optionsViewBuilder: (context, select, options) =>
                            PayeeAutocompleteMenu(
                              triggerKey: fieldAnchor,
                              surfaceKey: const ValueKey(
                                'responsive-payee-menu',
                              ),
                              contentWidth: payeeAutocompleteMenuWidth(
                                context,
                                [payee],
                                badged: false,
                              ),
                              itemCount: 1,
                              itemBuilder: (context, index) => InkWell(
                                key: const ValueKey('responsive-payee-row'),
                                onTap: () => select(payee),
                                child: Padding(
                                  padding: const EdgeInsets.all(10),
                                  child: Text(
                                    '${payee.name} · ${payee.typeLabel}',
                                    maxLines: 1,
                                    softWrap: false,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ),
                        fieldViewBuilder:
                            (context, controller, focus, submit) =>
                                KeyedSubtree(
                                  key: fieldAnchor,
                                  child: TextFormField(
                                    key: const ValueKey(
                                      'responsive-payee-field',
                                    ),
                                    controller: controller,
                                    focusNode: focus,
                                  ),
                                ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.enterText(keyed('responsive-payee-field'), 'Nur');
      await tester.pumpAndSettle();
      final menu = keyed('responsive-payee-menu');
      expect(tester.getSize(menu).width, 600);
      update(() => width = 130);
      await tester.pumpAndSettle();
      final narrow = tester.getRect(keyed('responsive-payee-field'));
      final widened = tester.getRect(menu);
      expect(widened.width, greaterThan(130));
      expect(widened.width, lessThan(600));
      expect(widened.right, lessThanOrEqualTo(712));
      checkOneLine(tester, menu);
      update(() => width = 600);
      await tester.pumpAndSettle();
      expect(tester.getSize(menu).width, 600);
      update(() => width = 130);
      await tester.pumpAndSettle();
      // Click the part left of the original field, not merely its painted center.
      expect(widened.left, lessThan(narrow.left));
      await tester.tapAt(
        Offset(
          widened.left + 12,
          tester.getRect(keyed('responsive-payee-row')).center.dy,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(keyed('responsive-payee-field'))
            .controller!
            .text,
        payee.name,
      );
      expect(menu, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  for (final width in [720.0, 1224.0]) {
    for (final owner in ['Expense', 'Claimant', 'Merchant', 'Voucher']) {
      testWidgets('$owner read-only field cannot open directory at $width', (
        tester,
      ) async {
        await prepare(tester, width);
        await actualOwner(tester, owner, readOnly: true);
        final (fieldKey, menuKey) = switch (owner) {
          'Expense' => ('expense-field-payee', 'expense-payee-menu'),
          'Claimant' => ('claim-claimant', 'claim-claimant-menu'),
          'Merchant' => ('claim-payee', 'claim-merchant-menu'),
          _ => ('voucher-payee', 'voucher-payee-menu'),
        };
        await tester.ensureVisible(keyed(fieldKey));
        await tester.tap(keyed(fieldKey), warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TextField>(
                find.descendant(
                  of: keyed(fieldKey),
                  matching: find.byType(TextField),
                ),
              )
              .focusNode!
              .hasFocus,
          isFalse,
        );
        expect(keyed(menuKey), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets(
    'scaled Claim merchant keeps name and role on one line; no results and Escape preserve input',
    (tester) async {
      await prepare(tester, 720);
      await actualOwner(tester, 'Merchant', scale: 1.5);
      final field = keyed('claim-payee');
      await tester.ensureVisible(field);
      await tester.enterText(field, 'Kumpulan');
      await tester.pumpAndSettle();
      final menu = keyed('claim-merchant-menu');
      checkOneLine(tester, menu);
      expect(tester.getRect(menu).right, lessThanOrEqualTo(712));
      final width = tester.getSize(menu).width;
      await capturePayee(tester, 'Payee Scroller Merchant Scaled 720');
      await tester.enterText(field, 'Not In Directory');
      await tester.pumpAndSettle();
      expect(keyed('claim-merchant-option-no-results'), findsOneWidget);
      expect(tester.getSize(menu).width, width);
      checkOneLine(tester, menu);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(menu, findsNothing);
      expect(
        tester.widget<TextFormField>(field).controller!.text,
        'Not In Directory',
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('viewport-capped Voucher retains complete accessible name', (
    tester,
  ) async {
    await prepare(tester, 720);
    final name = List.filled(30, 'Contoh').join(' ');
    await actualOwner(
      tester,
      'Voucher',
      choices: [Payee(id: 'long', name: name, type: PayeeType.smallProvider)],
    );
    final field = keyed('voucher-payee');
    await tester.ensureVisible(field);
    await tester.enterText(field, 'Contoh');
    await tester.pumpAndSettle();
    final menu = keyed('voucher-payee-menu');
    expect(tester.getSize(menu).width, 704);
    expect(tester.getRect(menu).left, 8);
    final option = keyed('voucher-payee-option-long');
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: option, matching: find.text(name)),
    );
    expect(paragraph.maxLines, 1);
    expect(paragraph.didExceedMaxLines, isTrue);
    expect(
      tester.getSemantics(option).getSemanticsData().label,
      contains(name),
    );
    await tester.tapAt(Offset(12, tester.getRect(option).center.dy));
    await tester.pumpAndSettle();
    expect(tester.widget<TextFormField>(field).controller!.text, name);
    expect(menu, findsNothing);
    expect(tester.takeException(), isNull);
  });
}
