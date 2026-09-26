import 'dart:math' as math;

import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final count in [1, 3]) {
    testWidgets(
      'colon-table labels share headers and edge padding survives $count rows',
      (t) async {
        await t.pumpWidget(
          MaterialApp(
            theme: AccountingTheme.light(),
            home: Scaffold(
              body: SizedBox(
                width: 600,
                child: AccountingInformationRows(
                  rows: [
                    ('Customer', 'Meridian Trading'),
                    if (count > 1) ('Invoice', 'DEMO-INV-001'),
                    if (count > 1) ('Outstanding', 'RM 3,613,950.45'),
                  ],
                ),
              ),
            ),
          ),
        );
        final table = find.byType(Table);
        final tableWidget = t.widget<Table>(table);
        final border = tableWidget.border!.dimensions;
        final bounds = t.getRect(table);
        final labels = count == 1
            ? ['Customer']
            : ['Customer', 'Invoice', 'Outstanding'];
        final values = count == 1
            ? ['Meridian Trading']
            : ['Meridian Trading', 'DEMO-INV-001', 'RM 3,613,950.45'];
        final colons = find.text(':');
        expect(
          math.min(
                t.getRect(find.text(labels.first)).top,
                t.getRect(find.text(values.first)).top,
              ) -
              bounds.top -
              border.top,
          closeTo(20, .01),
        );
        expect(
          bounds.bottom -
              math.max(
                t.getRect(find.text(labels.last)).bottom,
                t.getRect(find.text(values.last)).bottom,
              ) -
              border.bottom,
          closeTo(20, .01),
        );
        final largestLabelWidth = labels
            .map((v) => t.getRect(find.text(v)).width)
            .reduce((a, b) => a > b ? a : b);
        for (var i = 0; i < count; i++) {
          expect(
            t.widget<Text>(find.text(labels[i])).style!.fontWeight,
            FontWeight.w600,
          );
          expect(
            t.widget<Text>(find.text(values[i])).style!.fontWeight,
            FontWeight.w400,
          );
          final colon = t.getRect(colons.at(i));
          final label = t.getRect(find.text(labels[i]));
          expect(
            colon.left - label.left - largestLabelWidth,
            closeTo(AccountingSidewaysDetailsTokens.columnGap, .01),
          );
          expect(
            t.getRect(find.text(values[i])).left - colon.right,
            closeTo(AccountingSidewaysDetailsTokens.columnGap, .01),
          );
          if (i > 0) {
            expect(
              math.min(label.top, t.getRect(find.text(values[i])).top) -
                  math.max(
                    t.getRect(find.text(labels[i - 1])).bottom,
                    t.getRect(find.text(values[i - 1])).bottom,
                  ),
              closeTo(20, .01),
            );
          }
        }
        final context = t.element(table);
        expect(
          AccountingTypography.tableHeader(context).fontWeight,
          FontWeight.w600,
        );
        expect(AccountingSidewaysDetailsTokens.horizontalInset, 20);
        expect(AccountingSidewaysDetailsTokens.columnGap, 10);
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets('wrapped colon facts remain readable under scaled text', (
    t,
  ) async {
    t.view.physicalSize = const Size(420, 1400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(1.5)),
            child: const Scaffold(
              body: AccountingInformationRows(
                rows: [
                  (
                    'Customer',
                    'A longer customer name with enough words to wrap',
                  ),
                  ('Invoice', 'DEMO-INV-001'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    expect(t.takeException(), isNull);
    expect(find.textContaining('longer customer'), findsOneWidget);
    expect(
      t.getRect(find.text(':').first).left,
      t.getRect(find.text(':').last).left,
    );
  });
}
