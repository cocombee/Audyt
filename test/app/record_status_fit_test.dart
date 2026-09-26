import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/responsive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('record status changes only at its measured painted fit', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1224, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2'))).load();
    for (final label in [
      'Needs Review',
      'Partially Paid And Credited',
      'Approved For Payment And Awaiting Bank Reconciliation',
    ]) {
      for (final mode in ['full-title-fit', 'title-yields', 'badge-no-fit']) {
        double badgeWidth = 0;
        double titleNaturalWidth = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: AccountingTheme.light(),
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  badgeWidth = AccountingBadge.measuredWidth(context, label);
                  titleNaturalWidth = AccountingResponsive.measuredTextWidth(
                    context,
                    'Sample Supplier',
                    AccountingTypography.value(context).copyWith(
                      fontSize: accountingControlFontSize,
                      fontWeight: FontWeight.w500,
                    ),
                  );
                  final available = mode == 'badge-no-fit'
                      ? accountingRecordTitleLabelGap + badgeWidth - 2
                      : titleNaturalWidth +
                            accountingRecordTitleLabelGap +
                            badgeWidth +
                            (mode == 'title-yields' ? -2 : 2);
                  final width =
                      available +
                      100 +
                      accountingContentInset +
                      accountingContentPadding.horizontal;
                  return Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: width,
                      child: AccountingRecordRow(
                        title: 'Sample Supplier',
                        details: const Text('01-09-2026'),
                        topRightInfo: true,
                        trailing: const SizedBox(width: 100, height: 20),
                        status: AccountingBadge.build(
                          context,
                          label: label,
                          key: const ValueKey('full-status'),
                        ),
                        statusWidth: badgeWidth,
                        compactStatus: AccountingBadge.build(
                          context,
                          label: 'Review',
                          key: const ValueKey('compact-status'),
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
        if (mode != 'badge-no-fit') {
          expect(find.byKey(const ValueKey('full-status')), findsOneWidget);
          expect(find.byKey(const ValueKey('compact-status')), findsNothing);
          expect(
            tester.getSize(find.byKey(const ValueKey('full-status'))).width,
            closeTo(badgeWidth, .1),
          );
          if (mode == 'title-yields') {
            expect(
              tester.getSize(find.text('Sample Supplier')).width,
              lessThan(titleNaturalWidth),
            );
          }
        } else {
          expect(find.byKey(const ValueKey('full-status')), findsNothing);
          expect(find.byKey(const ValueKey('compact-status')), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      }
    }
  });
}
