import 'package:audyt/features/accounting/presentation/record_expense_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('receipt dropzone uses a one-pixel foreground dashed outline', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(960, 1200));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: RecordExpensePage()));

    final surface = find.byKey(const ValueKey('expense-receipt-surface'));
    final paint = tester.widget<CustomPaint>(
      find.descendant(of: surface, matching: find.byType(CustomPaint)).first,
    );
    expect((paint.foregroundPainter! as dynamic).strokeWidth, 0.56);
  });
}
