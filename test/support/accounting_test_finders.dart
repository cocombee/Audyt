import 'package:audyt/app/accounting_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Finder accountingCloseIcon() =>
    find.byWidgetPredicate((widget) => widget is AccountingCloseIcon);

/// A framed popup control's title follows its painted frame's left edge.
void expectPopupFieldTitleAligned(
  WidgetTester tester,
  String label,
  Finder frame,
) {
  final title = find
      .byWidgetPredicate(
        (widget) =>
            widget is Text &&
            widget.data == label &&
            widget.style?.fontWeight == FontWeight.w600,
      )
      .last;
  expect(
    tester.getTopLeft(title).dx,
    closeTo(tester.getTopLeft(frame).dx, .1),
    reason: '$label follows its field frame',
  );
}

/// A page's first action stays content-fit on the title's right, not in filters.
void expectHeaderPrimaryAction(WidgetTester tester, String actionKey) {
  final action = find.byKey(ValueKey(actionKey));
  final header = find.byKey(const ValueKey('accounting-page-header'));
  expect(find.descendant(of: header, matching: action), findsOneWidget);
  final actionRect = tester.getRect(action);
  final headerRect = tester.getRect(header);
  expect(actionRect.right, closeTo(headerRect.right, 0.1));
  expect(actionRect.top, closeTo(headerRect.top, 0.1));
  expect(actionRect.height, closeTo(44, 0.1));
  expect(actionRect.width, lessThan(headerRect.width / 2));
  expect(
    find.descendant(of: action, matching: find.byType(Icon)),
    findsNothing,
  );
}

/// Measure a value's own font rather than comparing its height to a header.
void expectSingleLineText(WidgetTester tester, Finder finder) {
  final text = tester.widget<Text>(finder);
  final context = tester.element(finder);
  final painter = TextPainter(
    text: TextSpan(
      text: text.data,
      style: DefaultTextStyle.of(context).style.merge(text.style),
    ),
    textDirection: text.textDirection ?? Directionality.of(context),
    textScaler: text.textScaler ?? MediaQuery.textScalerOf(context),
  )..layout(maxWidth: tester.getSize(finder).width);
  expect(painter.computeLineMetrics(), hasLength(1));
  expect(tester.getSize(finder).height, closeTo(painter.height, 0.1));
  painter.dispose();
}

/// Enter review explicitly; the Banking landing page now lists documents.
Future<void> openStatementReview(
  WidgetTester tester, {
  String? statementId,
}) async {
  final finder = statementId == null
      ? find
            .byWidgetPredicate(
              (widget) =>
                  widget.key is ValueKey<String> &&
                  (widget.key as ValueKey<String>).value.startsWith(
                    'statement-matches-',
                  ),
            )
            .first
      : find.byKey(ValueKey('statement-matches-$statementId'));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}
