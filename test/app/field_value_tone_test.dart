import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/menu_visual_geometry.dart';

void main() {
  for (final width in [720.0, 1224.0]) {
    testWidgets('field values and hints keep distinct tones at $width', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await (FontLoader(
        'Inter',
      )..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2'))).load();
      final boundary = GlobalKey();
      final entered = TextEditingController(text: 'Annual Return');
      addTearDown(entered.dispose);
      var period = 'All Dates';
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            theme: AccountingTheme.light(),
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) => Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AccountingSelector<String>(
                        triggerKey: const ValueKey('period'),
                        options: const [
                          AccountingSelectorOption(
                            value: 'All Dates',
                            label: 'All Dates',
                          ),
                          AccountingSelectorOption(
                            value: 'This Month',
                            label: 'This Month',
                          ),
                        ],
                        value: period,
                        hintText: 'Choose Period',
                        onChanged: (value) => setState(() => period = value!),
                      ),
                      const SizedBox(height: 20),
                      AccountingSelector<String>(
                        options: const [
                          AccountingSelectorOption(
                            value: 'bank',
                            label: 'Bank Account',
                          ),
                        ],
                        value: null,
                        hintText: 'Choose Account',
                        onChanged: (_) {},
                      ),
                      const SizedBox(height: 20),
                      AccountingSelector<String>(
                        options: const [
                          AccountingSelectorOption(
                            value: 'All Statuses',
                            label: 'All Statuses',
                          ),
                        ],
                        value: 'All Statuses',
                        hintText: 'Status',
                        enabled: false,
                        onChanged: (_) {},
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        key: const ValueKey('entered-value'),
                        controller: entered,
                        style: AccountingTypography.controlValue(context),
                        decoration: accountingSingleLineInputDecoration(
                          context,
                          hintText: 'Enter Description',
                        ),
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        key: const ValueKey('search-hint'),
                        style: AccountingTypography.controlValue(context),
                        decoration: accountingSingleLineInputDecoration(
                          context,
                          hintText: 'Search Tax Overview',
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
      await tester.pumpAndSettle();
      final context = tester.element(find.byKey(const ValueKey('period')));
      final tokens = AccountingTheme.of(context);
      for (final entry in {
        'All Dates': tokens.foreground,
        'Choose Account': tokens.mutedForeground,
        'All Statuses': tokens.mutedForeground,
      }.entries) {
        final label = find.text(entry.key);
        final text = tester.widget<Text>(label);
        expect(text.style!.color, entry.value);
        expect(text.style!.fontWeight, FontWeight.w400);
        final ink = await paintedSurfaceBounds(
          tester,
          boundary,
          label,
          entry.value,
        );
        expect(ink.height, greaterThan(5));
      }
      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('entered-value')),
      );
      final hint = tester.widget<TextField>(
        find.byKey(const ValueKey('search-hint')),
      );
      expect(field.style!.color, tokens.foreground);
      expect(hint.decoration!.hintStyle!.color, tokens.mutedForeground);
      await capture(boundary, 'Field Value Tones ${width.toInt()}', tester);
      await tester.tap(find.byKey(const ValueKey('period')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('This Month'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.text('This Month')).style!.color,
        tokens.foreground,
      );
      final frame = tester.getRect(find.byKey(const ValueKey('period')));
      await tester.tap(find.byKey(const ValueKey('period')));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(const ValueKey('period'))), frame);
      final choice = tester.widget<MenuItemButton>(
        find.ancestor(
          of: find.text('This Month').last,
          matching: find.byType(MenuItemButton),
        ),
      );
      expect(choice.style!.foregroundColor!.resolve({}), tokens.foreground);
      await capture(
        boundary,
        'Field Value Menu Tones ${width.toInt()}',
        tester,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
