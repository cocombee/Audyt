import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'currency prefix region compacts two-character symbols without shrinking the field',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(480, 240));
      addTearDown(() async => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: <Widget>[
                    TextField(
                      key: const ValueKey('prefix-rm-field'),
                      decoration: accountingInputDecoration(
                        context,
                        prefixText: 'RM',
                        prefixKey: const ValueKey('prefix-rm'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const ValueKey('prefix-code-field'),
                      decoration: accountingInputDecoration(
                        context,
                        prefixText: 'XYZ',
                        prefixKey: const ValueKey('prefix-code'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      final rmField = tester.getRect(
        find.byKey(const ValueKey('prefix-rm-field')),
      );
      final codeField = tester.getRect(
        find.byKey(const ValueKey('prefix-code-field')),
      );
      expect(rmField.width, closeTo(codeField.width, 0.01));
      final prefix = find.byKey(const ValueKey('prefix-rm'));
      final symbol = tester.getRect(
        find.descendant(of: prefix, matching: find.text('RM')),
      );
      final divider = tester.getRect(
        find.descendant(of: prefix, matching: find.byType(Container)),
      );
      final value = tester.getRect(find.byType(EditableText).first);
      expect(divider.left - symbol.right, closeTo(20, 0.5));
      expect(value.left - divider.right, closeTo(20, 0.5));
    },
  );
}
