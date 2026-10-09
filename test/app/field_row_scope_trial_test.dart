import 'dart:convert';

import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/accounting/domain/payment_account.dart';
import 'package:audyt/features/accounting/domain/bank_statement_import.dart';
import 'package:audyt/features/accounting/presentation/statement_reconciliation_dialog.dart';
import 'package:audyt/app/field_row_trial.dart';
import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/frontend_review.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/app/app.dart';
import 'package:audyt/features/purchases/presentation/bill_form.dart';
import 'package:audyt/features/accounting/presentation/record_expense_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../support/fixed_popout_host.dart';

import 'package:flutter_test/flutter_test.dart';

import 'journal_workspace_integration_test.dart'
    show captureUi, loadJournalLayoutFonts;
import 'restored_page_routes_test.dart' show tables;

void main() {
  for (final caller in [
    (
      name: 'Transfer',
      path: '/banking',
      tab: 'Transfers',
      action: 'Record Transfer',
      companion: 'Transfer Date',
      record: 'DEMO-TRANSFERS-1',
    ),
    (
      name: 'Cheque',
      path: '/banking',
      tab: 'Cheques',
      action: 'Record Cheque',
      companion: 'Payee Or Payer',
      record: 'DEMO-CHEQUES-1',
    ),
    (
      name: 'Document',
      path: '/documents',
      tab: 'For Review',
      action: 'Review Documents',
      companion: 'Merchant / Supplier',
      record: 'DEMO-FORREVIEW-1',
    ),
  ]) {
    for (final width in [720.0, 1162.0]) {
      testWidgets(
        'actual ${caller.name} companion and amount pack together at $width',
        (t) async {
          t.view.physicalSize = Size(width, 809);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.resetPhysicalSize);
          addTearDown(t.view.resetDevicePixelRatio);
          installFixedPopoutHost(t);
          await loadJournalLayoutFonts();
          final workspace = await createDemoWorkspace();
          addTearDown(workspace.dispose);
          final before = tables(workspace);
          await t.pumpWidget(
            RepaintBoundary(
              key: const ValueKey('workspace-capture'),
              child: DemoCompany(
                child: AudytApp(initialPath: caller.path, workspace: workspace),
              ),
            ),
          );
          await t.pumpAndSettle();
          final tabs = t.widget<AccountingTabs>(
            find.byType(AccountingTabs).first,
          );
          final index = tabs.labels.indexOf(caller.tab);
          expect(index, greaterThanOrEqualTo(0));
          await t.ensureVisible(
            find.byKey(ValueKey('${tabs.keyPrefix}-$index')),
          );
          await t.tap(find.byKey(ValueKey('${tabs.keyPrefix}-$index')));
          await t.pumpAndSettle();
          await t.tap(find.text(caller.action));
          await t.pumpAndSettle();
          final companion = find.byKey(
            ValueKey('design-field-${caller.companion}'),
          );
          final amount = find.byKey(const ValueKey('design-field-Amount'));
          expect(t.getRect(companion).top, closeTo(t.getRect(amount).top, .1));
          expect(t.getRect(companion).right, lessThan(t.getRect(amount).left));
          await captureUi(
            t,
            '${caller.name} Fluid Companion Amount Empty ${width.toInt()}',
          );
          final original = t.getRect(amount);
          await t.enterText(amount, '1234567.89');
          await t.pumpAndSettle();
          expect(
            t.getRect(amount),
            original,
            reason: 'Independent amounts retain their two-field track.',
          );
          await captureUi(
            t,
            '${caller.name} Fluid Companion Amount Typed ${width.toInt()}',
          );
          await t.tap(find.byKey(const ValueKey('design-close')));
          await t.pumpAndSettle();
          await t.tap(find.text('Keep Editing'));
          await t.pumpAndSettle();
          expect(
            t.widget<TextFormField>(amount).controller!.text,
            '1,234,567.89',
          );
          await t.tap(find.byKey(const ValueKey('design-close')));
          await t.pumpAndSettle();
          await t.tap(find.text('Discard'));
          await t.pumpAndSettle();
          await t.tap(find.byKey(ValueKey('view-record-${caller.record}')));
          await t.pumpAndSettle();
          expect(t.getRect(companion).top, closeTo(t.getRect(amount).top, .1));
          expect(t.widget<TextFormField>(amount).controller!.text, '12,000.00');
          await captureUi(
            t,
            '${caller.name} Fluid Companion Amount Retained ${width.toInt()}',
          );
          await t.tap(find.byKey(const ValueKey('design-close')));
          await t.pumpAndSettle();
          expect(tables(workspace), before);
          expect(t.takeException(), isNull);
        },
      );
    }
  }

  test('ordinary money growth uses the actual three-or-more row only', () {
    const base = [80.0, 120.0, 120.0, 120.0];
    const grown = [210.0, null, null, null];
    final crowded = trialRows(700, base, threeOrMoreFieldMinima: grown);
    expect(crowded.single.widths, hasLength(4));
    expect(crowded.single.widths.first, greaterThanOrEqualTo(210));
    final fallback = trialRows(320, base, threeOrMoreFieldMinima: grown);
    expect(fallback.first.widths, hasLength(2));
    expect(fallback.first.widths, trialRows(320, base).first.widths);
    for (final count in [1, 2]) {
      expect(
        trialRows(
          620,
          base.take(count).toList(),
          threeOrMoreFieldMinima: grown.take(count).toList(),
        ).first.widths,
        trialRows(620, base.take(count).toList()).first.widths,
      );
    }
    expect(trialRows(700, base).single.widths.first, lessThan(210));
  });

  for (final width in [1162.0, 720.0, 1224.0]) {
    testWidgets('actual Fixed Assets populated money fits at $width', (
      t,
    ) async {
      t.view.physicalSize = Size(width, 809);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      installFixedPopoutHost(t);
      await loadJournalLayoutFonts();
      final workspace = await createDemoWorkspace();
      addTearDown(workspace.dispose);
      await t.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('workspace-capture'),
          child: DemoCompany(
            child: AudytApp(initialPath: '/accounting', workspace: workspace),
          ),
        ),
      );
      await t.pumpAndSettle();
      final tabs = t.widget<AccountingTabs>(find.byType(AccountingTabs).first);
      final index = tabs.labels.indexOf('Fixed Assets');
      expect(index, greaterThanOrEqualTo(0));
      await t.ensureVisible(find.byKey(ValueKey('${tabs.keyPrefix}-$index')));
      await t.tap(find.byKey(ValueKey('${tabs.keyPrefix}-$index')));
      await t.pumpAndSettle();
      final view = find.byKey(const ValueKey('view-record-DEMO-FIXEDASSETS-4'));
      await t.ensureVisible(view);
      await t.tap(view);
      await t.pumpAndSettle();
      final cost = find.byKey(const ValueKey('design-field-Cost'));
      await t.ensureVisible(
        find.ancestor(of: cost, matching: find.byType(Column)).first,
      );
      await t.pumpAndSettle();
      final editable = find.descendant(
        of: cost,
        matching: find.byType(EditableText),
      );
      expect(t.widget<EditableText>(editable).controller.text, '350.00');
      expect(
        t.state<EditableTextState>(editable).renderEditable.maxScrollExtent,
        closeTo(0, .1),
        reason: 'Retained 350.00 must not clip its last digit',
      );
      await captureUi(
        t,
        'Ordinary Money Fixed Assets Retained ${width.toInt()}',
      );
      await t.enterText(cost, '1234567.89');
      await t.pumpAndSettle();
      final peers = find.ancestor(of: cost, matching: find.byType(Row)).first;
      final row = t.widget<Row>(peers);
      final count = row.children
          .whereType<SizedBox>()
          .where((w) => w.key != null)
          .length;
      expect(count, greaterThanOrEqualTo(3));
      expect(
        t.state<EditableTextState>(editable).renderEditable.maxScrollExtent,
        closeTo(0, .1),
        reason: 'Current amount fits only in eligible crowded row',
      );
      expect(t.widget<EditableText>(editable).focusNode.hasFocus, isTrue);
      expect(t.testTextInput.isRegistered, isTrue);
      await captureUi(t, 'Ordinary Money Fixed Assets Typed ${width.toInt()}');
      expect(t.takeException(), isNull);
    });
  }

  for (final count in [1, 2]) {
    testWidgets('ordinary $count-field amount retains its track after entry', (
      t,
    ) async {
      await loadJournalLayoutFonts();
      await t.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 620,
                child: FrontendFormDialog(
                  embedded: true,
                  fieldLayoutOwner: AccountingFieldLayoutOwner.sharedPopup,
                  form: DesignForm('Ordinary Scope Check', [
                    const DesignField('Cost', monetary: true),
                    if (count == 2) const DesignField('Reference'),
                  ]),
                  onCommit: (_) async {},
                ),
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      final cost = find.byKey(const ValueKey('design-field-Cost'));
      final original = t.getRect(cost);
      await t.enterText(cost, '123456789012345678901234567890.56');
      await t.pumpAndSettle();
      expect(t.getRect(cost), original);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets(
    'crowded amount fallback retains focus and restores static tracks',
    (t) async {
      await loadJournalLayoutFonts();
      final width = ValueNotifier<double>(620);
      addTearDown(width.dispose);
      await t.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: ValueListenableBuilder<double>(
                valueListenable: width,
                builder: (_, available, _) => SizedBox(
                  width: available,
                  child: FrontendFormDialog(
                    embedded: true,
                    fieldLayoutOwner: AccountingFieldLayoutOwner.sharedPopup,
                    form: const DesignForm('Ordinary Scope Check', [
                      DesignField('Cost', monetary: true),
                      DesignField('Reference'),
                      DesignField('Code'),
                    ]),
                    onCommit: (_) async {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      final cost = find.byKey(const ValueKey('design-field-Cost'));
      await t.enterText(cost, '123456789012345.67');
      await t.pumpAndSettle();
      final editable = find.descendant(
        of: cost,
        matching: find.byType(EditableText),
      );
      final state = t.state<EditableTextState>(editable);
      final selection = t.widget<EditableText>(editable).controller.selection;
      expect(state.renderEditable.maxScrollExtent, closeTo(0, .1));
      width.value = 400;
      await t.pumpAndSettle();
      expect(t.state<EditableTextState>(editable), same(state));
      expect(t.widget<EditableText>(editable).focusNode.hasFocus, isTrue);
      expect(t.widget<EditableText>(editable).controller.selection, selection);
      expect(t.getSize(cost).width, 190);
      expect(t.testTextInput.isRegistered, isTrue);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'ordinary reflow retains editor focus, caret and input connection',
    (tester) async {
      final width = ValueNotifier<double>(620);
      final controller = TextEditingController(text: 'Draft reference');
      addTearDown(width.dispose);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: ValueListenableBuilder<double>(
                valueListenable: width,
                builder: (context, available, _) => SizedBox(
                  width: available,
                  child: AccountingOrdinaryFieldRows(
                    width: available,
                    minima: const [180, 180],
                    fieldBuilder: (index, _) => index == 0
                        ? const TextField(key: ValueKey('reflow-first'))
                        : TextField(
                            key: const ValueKey('reflow-editor'),
                            controller: controller,
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('reflow-editor'));
      final editable = find.descendant(
        of: field,
        matching: find.byType(EditableText),
      );
      await tester.tap(field);
      await tester.pumpAndSettle();
      controller.selection = const TextSelection.collapsed(offset: 5);
      final state = tester.state<EditableTextState>(editable);
      for (final nextWidth in [300.0, 620.0, 300.0, 620.0]) {
        width.value = nextWidth;
        await tester.pumpAndSettle();
        expect(tester.state<EditableTextState>(editable), same(state));
        expect(
          tester.widget<EditableText>(editable).focusNode.hasFocus,
          isTrue,
        );
        expect(controller.selection, const TextSelection.collapsed(offset: 5));
        expect(tester.testTextInput.isRegistered, isTrue);
      }
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'Draft continued',
          selection: TextSelection.collapsed(offset: 15),
        ),
      );
      await tester.pumpAndSettle();
      expect(controller.text, 'Draft continued');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final width in [720.0, 1224.0]) {
    testWidgets(
      'ordinary title holds field width with optional helper at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await (FontLoader('Inter')
              ..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2')))
            .load();
        for (final showHelp in [false, true]) {
          final title =
              'Transaction Reference Information${showHelp ? ' *' : ''}';
          await tester.pumpWidget(
            MaterialApp(
              theme: AccountingTheme.light(),
              home: Scaffold(
                body: Builder(
                  builder: (context) {
                    final slot = AccountingOrdinaryFieldSlot(
                      label: title,
                      contentSample: '0',
                      hasGuidance: showHelp,
                      builder: (_) => const SizedBox.shrink(),
                    );
                    return Align(
                      alignment: Alignment.topLeft,
                      child: SizedBox(
                        width: slot.minimumWidth(context),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            accountingFieldLabel(
                              context,
                              title,
                              guidance: showHelp
                                  ? 'Use the retained document reference.'
                                  : null,
                            ),
                            const SizedBox(height: accountingFieldLabelGap),
                            const TextField(
                              key: ValueKey('title-minimum-input'),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final field = tester.getRect(
            find.byKey(const ValueKey('title-minimum-input')),
          );
          final text = tester.renderObject<RenderParagraph>(
            find.text('Transaction Reference Information'),
          );
          final boxes = text.getBoxesForSelection(
            const TextSelection(baseOffset: 0, extentOffset: 33),
          );
          expect(boxes.map((box) => box.top).toSet(), hasLength(1));
          final ending = showHelp
              ? tester.getRect(find.byType(AccountingFieldHelp)).right
              : tester
                    .getRect(find.text('Transaction Reference Information'))
                    .right;
          expect(ending, closeTo(field.right, 0.01));
          expect(tester.takeException(), isNull);
        }
      },
    );
  }

  testWidgets('ordinary text minimum includes the painted input insets', (
    tester,
  ) async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2'))).load();
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              final slot = AccountingOrdinaryFieldSlot(
                label: 'Reference #',
                contentSample: 'Reference',
                builder: (_) => const SizedBox.shrink(),
              );
              return Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: slot.minimumWidth(context),
                  child: TextField(
                    decoration: accountingSingleLineInputDecoration(
                      context,
                      hintText: 'Reference',
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final hint = tester.renderObject<RenderParagraph>(find.text('Reference'));
    expect(hint.didExceedMaxLines, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('frontend ordinary inputs fit painted text after wrapping', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1224, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2'))).load();
    const value = 'WWWWWWWWWW';
    const labels = ['Code', 'Tag', 'Note', 'Ref'];
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              final painter = TextPainter(
                text: TextSpan(
                  text: value,
                  style: AccountingTypography.controlValue(context),
                ),
                textDirection: TextDirection.ltr,
              )..layout();
              // Just below four complete painted inputs: the ordinary owner
              // must wrap peers rather than clip their retained values.
              final width = (painter.width + 36) * labels.length + 60;
              painter.dispose();
              return Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
                  child: FrontendFormDialog(
                    embedded: true,
                    fieldLayoutOwner: AccountingFieldLayoutOwner.sharedPopup,
                    contentWidth: 1200,
                    initial: {for (final label in labels) label: value},
                    form: const DesignForm('Popup Settings', [
                      DesignField('Code'),
                      DesignField('Tag'),
                      DesignField('Note'),
                      DesignField('Ref'),
                    ]),
                    onCommit: (_) async {},
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final label in labels) {
      final field = find.byKey(ValueKey('design-field-$label'));
      final editable = tester
          .state<EditableTextState>(
            find.descendant(of: field, matching: find.byType(EditableText)),
          )
          .renderEditable;
      expect(editable.text!.toPlainText(), value);
      expect(
        editable.maxScrollExtent,
        closeTo(0, .1),
        reason:
            '$label must display the retained value without horizontal clipping',
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'popup settings replan at parent width and reuse the grey footer',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1224, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await (FontLoader(
        'Inter',
      )..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2'))).load();
      final parentWidth = ValueNotifier<double>(620);
      addTearDown(parentWidth.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: ValueListenableBuilder<double>(
                valueListenable: parentWidth,
                builder: (context, width, _) => SizedBox(
                  width: width,
                  child: FrontendFormDialog(
                    embedded: true,
                    fieldLayoutOwner: AccountingFieldLayoutOwner.sharedPopup,
                    contentWidth: 680,
                    form: const DesignForm('Popup Settings', [
                      DesignField('Reference'),
                      DesignField('Number'),
                      DesignField('Code'),
                      DesignField('Tag'),
                      DesignField('Memo', multiline: true),
                    ]),
                    onCommit: (_) async {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Finder field(String label) => find.byKey(ValueKey('design-field-$label'));
      final first = tester.getRect(field('Reference'));
      for (final label in ['Number', 'Code', 'Tag']) {
        expect(tester.getRect(field(label)).top, first.top);
        expect(tester.getRect(field(label)).width, closeTo(first.width, .1));
      }
      final footer = tester.widget<Container>(
        find.byKey(const ValueKey('settings-form-footer-Popup Settings')),
      );
      expect(
        (footer.decoration as BoxDecoration).color,
        AccountingTheme.light().extension<AccountingTokens>()!.muted,
      );
      parentWidth.value = 300;
      await tester.pumpAndSettle();
      expect(
        tester.getRect(field('Code')).top,
        greaterThan(tester.getRect(field('Reference')).top),
      );
      for (final label in ['Reference', 'Number', 'Code', 'Tag']) {
        expect(tester.getRect(field(label)).right, lessThanOrEqualTo(300));
      }
      expect(find.byKey(const ValueKey('design-field-Memo')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('address popup minima and term dependents share available rows', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1224, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2'))).load();
    Map<String, Object?>? reviewed;
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: Scaffold(
          body: FrontendFormDialog(
            contentWidth: 620,
            form: DesignForm('Address and terms popup', [
              ...addressFields.take(2),
              const DesignField(
                'Preferred Billing Currency',
                options: ['MYR', 'SGD'],
              ),
              const DesignField(
                'Payment Terms',
                options: ['Net 30', 'Day Of Month'],
              ),
            ]),
            initial: const {
              'Payment Terms': 'Day Of Month',
              'Monthly Due Day': '21',
              'Rollover Within Days': '7',
            },
            reviewInformationRowsBuilder: (values) {
              reviewed = values;
              return const [('Review', 'Ready')];
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final address1 = tester.getRect(
      find.byKey(const ValueKey('design-field-Address Line 1')),
    );
    final address2 = tester.getRect(
      find.byKey(const ValueKey('design-field-Address Line 2')),
    );
    final rowWidth = tester
        .getSize(find.byType(AccountingOrdinaryFieldRows).first)
        .width;
    expect(address1.width, greaterThanOrEqualTo((rowWidth - 20) / 2));
    expect(address2.width, closeTo(address1.width, .1));
    expect(address1.top, closeTo(address2.top, .1));
    final day = find.byKey(const ValueKey('design-field-Monthly Due Day'));
    final rollover = find.byKey(
      const ValueKey('design-field-Rollover Within Days'),
    );
    expect(tester.getRect(day).top, greaterThan(address2.bottom));
    final dayRect = tester.getRect(day);
    final rolloverRect = tester.getRect(rollover);
    if ((rolloverRect.top - dayRect.top).abs() < .1) {
      expect(dayRect.left, closeTo(address1.left, .1));
      expect(rolloverRect.left, greaterThan(dayRect.right));
    } else {
      expect(rolloverRect.left, closeTo(address1.left, .1));
    }
    expect(
      tester.getRect(rollover).top,
      greaterThanOrEqualTo(tester.getRect(day).top),
    );
    await tester.ensureVisible(day);
    await tester.tap(day);
    await tester.pumpAndSettle();
    final lastDay = find.widgetWithText(MenuItemButton, '31');
    await tester.ensureVisible(lastDay);
    await tester.tap(lastDay);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('design-review')));
    await tester.tap(find.byKey(const ValueKey('design-review')));
    await tester.pumpAndSettle();
    expect(reviewed?['Monthly Due Day'], '31');
    expect(reviewed?['Rollover Within Days'], '7');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'normal ordinary popout inherits two-field rows without a form allowlist',
    (tester) async {
      tester.view.physicalSize = const Size(1224, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await (FontLoader(
        'Inter',
      )..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2'))).load();
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: const Scaffold(
            body: FrontendFormDialog(
              contentWidth: 620,
              form: DesignForm('Previously Unknown Ordinary Form', [
                DesignField('Reference'),
                DesignField('Number'),
                DesignField('Code'),
                DesignField('Tag'),
                DesignField('Custom Part', customLayout: true, fullWidth: true),
                DesignField('Notes', multiline: true),
              ]),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final frames = [
        for (final label in ['Reference', 'Number', 'Code', 'Tag'])
          tester.getRect(find.byKey(ValueKey('design-field-$label'))),
      ];
      expect(frames[1].top, frames[0].top);
      expect(frames[2].top, greaterThan(frames[0].bottom));
      expect(frames[3].top, frames[2].top);
      for (final frame in frames.skip(1)) {
        expect(frame.width, closeTo(frames.first.width, .01));
      }
      final custom = tester.getRect(
        find.byKey(const ValueKey('design-field-Custom Part')),
      );
      final notes = tester.getRect(
        find.byKey(const ValueKey('design-field-Notes')),
      );
      expect(custom.width, greaterThan(frames.first.width * 2));
      expect(notes.width, custom.width);
      expect(notes.top, greaterThan(custom.top));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('ordinary adapter replans on parent width and text scale', (
    tester,
  ) async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2'))).load();
    Future<void> render(double width, double scale) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(
            body: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
                  child: AccountingOrdinaryFields(
                    fields: [
                      for (final label in [
                        'Reference',
                        'Number',
                        'Code',
                        'Tag',
                      ])
                        AccountingOrdinaryFieldSlot(
                          label: label,
                          builder: (_) => TextField(key: ValueKey(label)),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    Rect frame(String label) => tester.getRect(find.byKey(ValueKey(label)));
    await render(620, 1);
    expect(frame('Tag').top, frame('Reference').top);
    expect(frame('Tag').width, closeTo(frame('Reference').width, .01));
    await render(310, 1);
    expect(frame('Number').top, frame('Reference').top);
    expect(frame('Code').top, greaterThan(frame('Reference').top));
    await render(310, 2);
    expect(frame('Number').top, greaterThan(frame('Reference').top));
    expect(frame('Reference').width, 310);
    await render(620, 1);
    expect(frame('Tag').top, frame('Reference').top);
  });
  testWidgets(
    'reconciliation uses measured balance fitting and preserves embedded dates',
    (tester) async {
      await (FontLoader(
        'Inter',
      )..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2'))).load();
      tester.view.physicalSize = const Size(1000, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final w = await createDemoWorkspace();
      addTearDown(w.dispose);
      w.savePaymentAccount(
        PaymentAccount.create(
          id: 'scope-bank',
          name: 'Fictional Bank',
          type: PaymentAccountType.bank,
          currencyCode: 'MYR',
        ),
      );
      final statement = w.database.importBankStatement(
        id: EntityId.random(),
        businessId: w.identity.businessId,
        paymentAccountId: 'scope-bank',
        importedAt: DateTime(2026, 10, 2),
        statement: BankStatementImport.csv(
          filename: 'Scope.csv',
          currency: 'MYR',
          bytes: Uint8List.fromList(
            utf8.encode('Date,Description,Amount\n2026-10-01,Example,-10.00'),
          ),
        ),
      );
      for (final (embedded, width, datesStack) in [
        (false, 500.0, false),
        (false, 480.0, true),
        (true, 480.0, true),
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            key: ValueKey((embedded, width)),
            theme: AccountingTheme.light(),
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
                  child: StatementReconciliationDialog(
                    workspace: w,
                    statementId: statement,
                    currency: 'MYR',
                    embedded: embedded,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        Rect frame(String key) => tester.getRect(find.byKey(ValueKey(key)));
        final start = frame('reconciliation-start');
        final end = frame('reconciliation-end');
        if (datesStack) {
          expect(end.top, greaterThan(start.top));
        } else {
          expect(end.top, start.top);
          expect(end.width, start.width);
        }
        expect(end.right, lessThanOrEqualTo(width));
        if (embedded) {
          expect(
            find.byKey(const ValueKey('reconciliation-date-fields')),
            findsNothing,
          );
        } else {
          expect(
            find.byKey(const ValueKey('reconciliation-date-fields')),
            findsOneWidget,
          );
        }
        final opening = frame('reconciliation-opening');
        final closing = frame('reconciliation-closing');
        expect(
          find.byKey(const ValueKey('reconciliation-balance-fields')),
          findsOneWidget,
        );
        expect(closing.top, opening.top);
        expect(closing.width, opening.width);
        expect(closing.left - opening.right, closeTo(20, .1));
        expect(tester.takeException(), isNull);
      }
    },
  );
  for (final width in [720.0, 1224.0]) {
    testWidgets(
      'embedded Bill/tab form bypasses equal-third popout trial at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        installFixedPopoutHost(tester);
        final workspace = await createDemoWorkspace();
        addTearDown(workspace.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: AccountingTheme.light(),
            home: Scaffold(
              body: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: 1000,
                  child: SingleChildScrollView(
                    child: FrontendFormDialog(
                      embedded: true,
                      form: billForm(
                        {},
                        {},
                        preferences: workspace.preferences,
                      ),
                      settingsWorkspace: workspace,
                      contentWidth: 728,
                      initial: const {'Tax Mode': 'Exclusive'},
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final date = tester.getRect(
          find.byKey(const ValueKey('design-field-Date')),
        );
        final due = tester.getRect(
          find.byKey(const ValueKey('design-field-Due Date')),
        );
        final reference = tester.getRect(
          find.byKey(const ValueKey('design-field-Reference')),
        );
        expect(date.top, due.top);
        expect(date.width, closeTo(due.width, .01));
        expect(reference.top, isNot(date.top));
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets('main-page Expense keeps its original equal header at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: const Scaffold(body: RecordExpensePage()),
        ),
      );
      await tester.pumpAndSettle();
      final tax = tester.widget<AccountingSelector<String>>(
        find.byWidgetPredicate(
          (w) =>
              w is AccountingSelector<String> &&
              w.triggerKey == const ValueKey('expense-tax-treatment'),
        ),
      );
      final recurring = tester.widget<AccountingSelector<bool>>(
        find.byWidgetPredicate(
          (w) =>
              w is AccountingSelector<bool> &&
              w.triggerKey == const ValueKey('expense-recurring-control'),
        ),
      );
      expect(tax.assignedWidth, closeTo(recurring.assignedWidth!, .01));
      expect(tester.takeException(), isNull);
    });
  }
}
