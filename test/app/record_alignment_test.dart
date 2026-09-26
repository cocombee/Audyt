import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';

void main() {
  testWidgets('expense title gap stops at the status pill container', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: Scaffold(
          body: SizedBox(
            width: 900,
            child: AccountingRecordRow(
              title: 'Metro Travel',
              titleStatusGap: accountingContentInset,
              status: Builder(
                builder: (context) => AccountingBadge.build(
                  context,
                  label: 'Needs Review',
                  key: const ValueKey('review-badge'),
                ),
              ),
              details: const Text('Operating Expenses'),
              trailing: const Text('RM 98.00'),
            ),
          ),
        ),
      ),
    );
    final title = tester.getRect(find.text('Metro Travel'));
    final badge = tester.getRect(find.byKey(const ValueKey('review-badge')));
    expect(badge.left - title.right, closeTo(accountingContentInset, 0.1));
    final badgeText = tester.getRect(find.text('Needs Review'));
    expect(badgeText.left - badge.left, closeTo(8, 0.1));
  });
  testWidgets('two-line records join the existing price-above-actions group', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 900,
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AccountingRecordRow(
                    key: ValueKey('row'),
                    topRightInfo: true,
                    title: 'Meridian Trading',
                    details: Text('DEMO-PAYBILLS-1 · 01-09-2026'),
                    trailing: Text('RM 12,000.00'),
                    trailingBelow: SizedBox(
                      key: ValueKey('trailing-action'),
                      width: 120,
                      height: 32,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final row = tester.getRect(find.byKey(const ValueKey('row')));
    final title = tester.getRect(find.text('Meridian Trading'));
    final detail = tester.getRect(find.text('DEMO-PAYBILLS-1 · 01-09-2026'));
    final price = tester.getRect(find.text('RM 12,000.00'));
    final action = tester.getRect(
      find.byKey(const ValueKey('trailing-action')),
    );
    expect(price.right, closeTo(action.right, 0.1));
    expect(action.top - price.bottom, accountingRecordPriceActionGap);
    expect(detail.top - title.bottom, accountingRecordInfoLineGap);
    expect(price.top - row.top, accountingContentInset);
    expect(row.bottom - action.bottom, accountingContentInset);
    expect(
      (title.top + detail.bottom) / 2,
      closeTo((price.top + action.bottom) / 2, 1),
    );
    expect(row.right - action.right, accountingContentInset);
    expect(tester.takeException(), isNull);
  });

  testWidgets('three-line records stack icon groups below the amount', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: const Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 900,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AccountingRecordRow(
                    key: ValueKey('row'),
                    topRightInfo: true,
                    title: 'City Supplies',
                    details: Text(
                      'Claimant: Aina Rahman\nCategory: Office Supplies',
                    ),
                    trailing: Text('RM 25.00'),
                    trailingBelow: AccountingRecordActions(
                      actions: [
                        SizedBox(
                          key: ValueKey('workflow'),
                          width: 32,
                          height: 32,
                        ),
                      ],
                      trailing: [
                        SizedBox(
                          key: ValueKey('neutral'),
                          width: 32,
                          height: 32,
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
    );
    final row = tester.getRect(find.byKey(const ValueKey('row')));
    final title = tester.getRect(find.text('City Supplies'));
    final category = tester.getRect(find.textContaining('Claimant:'));
    final price = tester.getRect(find.text('RM 25.00'));
    final workflow = tester.getRect(find.byKey(const ValueKey('workflow')));
    final neutral = tester.getRect(find.byKey(const ValueKey('neutral')));
    expect(price.top - row.top, accountingContentInset);
    expect(category.top - title.bottom, accountingRecordInfoLineGap);
    expect(workflow.top - price.bottom, accountingRecordInfoLineGap);
    expect(neutral.left - workflow.right, accountingRecordIconGap);
    expect(row.bottom - neutral.bottom, accountingContentInset);
    expect(row.right - neutral.right, accountingContentInset);
    expect(
      (title.top + category.bottom) / 2,
      closeTo((price.top + neutral.bottom) / 2, 1),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow bank row moves status last and stacks the right side', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: const Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 500,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AccountingRecordRow(
                    key: ValueKey('bank-row'),
                    title: 'SR-001 Customer Payment',
                    status: Text('Not Connected', key: ValueKey('status')),
                    adaptiveStatusLastLine: true,
                    topRightInfo: true,
                    details: Text('01-09-2026'),
                    trailing: Text('unused'),
                    trailingWhenStatusLastLine: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('RM 680,000.00', key: ValueKey('amount')),
                        SizedBox(height: accountingContentInset),
                        SizedBox(key: ValueKey('link'), width: 32, height: 32),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    final row = tester.getRect(find.byKey(const ValueKey('bank-row')));
    final date = tester.getRect(find.text('01-09-2026'));
    final status = tester.getRect(find.byKey(const ValueKey('status')));
    final amount = tester.getRect(find.byKey(const ValueKey('amount')));
    final link = tester.getRect(find.byKey(const ValueKey('link')));
    expect(status.top, greaterThan(date.bottom));
    expect(link.top - amount.bottom, accountingContentInset);
    expect(amount.top - row.top, accountingContentInset);
    expect(row.bottom - link.bottom, accountingContentInset);
    expect(row.right - link.right, accountingContentInset);
  });

  testWidgets('height-setting text retains its outer insets', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 900,
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AccountingRecordRow(
                    key: ValueKey('row'),
                    topRightInfo: true,
                    title: 'Northwind Office Supplies',
                    details: Text('DEMO-INV-002 · 01-09-2026'),
                    trailing: Text('RM 185.00'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final row = tester.getRect(find.byKey(const ValueKey('row')));
    final title = tester.getRect(find.text('Northwind Office Supplies'));
    final detail = tester.getRect(find.text('DEMO-INV-002 · 01-09-2026'));
    expect(title.top - row.top, accountingContentInset);
    expect(detail.top - title.bottom, accountingRecordInfoLineGap);
    expect(row.bottom - detail.bottom, accountingContentInset);
    expect(tester.takeException(), isNull);
  });

  testWidgets('painted leading checkbox anchors both record text lines', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: const Scaffold(
          body: SizedBox(
            width: 900,
            child: AccountingRecordRow(
              topRightInfo: true,
              leadingOverlaysTitle: true,
              leading: AccountingLeadingCheckbox(value: false, onChanged: null),
              title: 'DEMO-INV-001',
              details: Text('Meridian Trading'),
              trailing: Text('RM 3,613,950.45'),
              trailingBelow: SizedBox(width: 90, height: 32),
            ),
          ),
        ),
      ),
    );
    final checkbox = tester.getRect(find.byType(Checkbox));
    final title = tester.getRect(find.text('DEMO-INV-001'));
    final customer = tester.getRect(find.text('Meridian Trading'));
    expect(checkbox.left, accountingContentInset);
    expect(title.left, customer.left);
    expect(title.left - checkbox.right, accountingContentInset);
    expect(checkbox.center.dy, closeTo((title.top + customer.bottom) / 2, 2));
    expect(tester.takeException(), isNull);
  });
  for (final width in [340.0, 900.0]) {
    testWidgets('status keeps the compact title gap at $width', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: const AccountingRecordRow(
                  title: 'City Fuel',
                  status: SizedBox(
                    key: ValueKey('status'),
                    width: 50,
                    height: 20,
                  ),
                  details: Text('03-09-2026'),
                  trailing: SizedBox(width: 60, height: 20),
                ),
              ),
            ),
          ),
        ),
      );
      final title = tester.getRect(find.text('City Fuel'));
      final status = tester.getRect(find.byKey(const ValueKey('status')));
      expect(status.left - title.right, accountingRecordTitleLabelGap);
      expect(status.center.dy, closeTo(title.center.dy, 2));
      expect(tester.takeException(), isNull);
    });
  }
  for (final width in [340.0, 520.0, 900.0]) {
    testWidgets('record actions use actual available width at $width', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: AccountingRecordRow(
                  title: 'Workspace Rental',
                  details: const SizedBox(key: ValueKey('details'), height: 48),
                  trailing: const SizedBox(
                    key: ValueKey('actions'),
                    width: 250,
                    height: 40,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final details = tester.getRect(find.byKey(const ValueKey('details')));
      final actions = tester.getRect(find.byKey(const ValueKey('actions')));
      if (width >= 900) {
        expect(actions.center.dy, closeTo((20 + details.bottom) / 2, 0.1));
        expect(actions.right, width - 20);
      } else {
        expect(actions.top, greaterThan(details.bottom));
        expect(actions.center.dx, width / 2);
      }
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'tall row preserves top-right metadata and separates left details',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 360,
                child: AccountingRecordRow(
                  topRightInfo: true,
                  title: 'City Supplies',
                  details: const Text(
                    'Claimant: Aina Rahman (Office Supplies and Small Equipment)',
                    key: ValueKey('details'),
                  ),
                  trailing: const SizedBox(
                    key: ValueKey('amount'),
                    width: 100,
                    height: 64,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final amount = tester.getRect(find.byKey(const ValueKey('amount')));
      final details = tester.getRect(find.byKey(const ValueKey('details')));
      expect(amount.top, 20);
      expect(amount.right, 340);
      expect(details.right, lessThanOrEqualTo(amount.left - 12));
      expect(tester.takeException(), isNull);
    },
  );
  test('all buttons darken fill with stable borders and disabled states', () {
    for (final color in [Colors.white, Colors.green, Colors.red, Colors.grey]) {
      final base = ButtonStyle(
        backgroundColor: WidgetStatePropertyAll(color),
        foregroundColor: const WidgetStatePropertyAll(Colors.white),
      );
      final style = accountingButtonHover(base);
      final hover = Color.alphaBlend(
        style.overlayColor!.resolve({WidgetState.hovered})!,
        color,
      );
      expect(hover.computeLuminance(), lessThan(color.computeLuminance()));
      expect(
        style.backgroundColor!.resolve({
          WidgetState.disabled,
          WidgetState.hovered,
        }),
        color,
      );
      expect(
        style.overlayColor!.resolve({
          WidgetState.disabled,
          WidgetState.hovered,
        }),
        Colors.transparent,
      );
    }
    expect(
      accountingButtonHover(const ButtonStyle()).overlayColor!
          .resolve({WidgetState.hovered})!
          .a,
      greaterThan(0),
    );
  });
}
