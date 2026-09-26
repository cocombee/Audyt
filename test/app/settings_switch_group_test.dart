import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/frontend_review.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/menu_visual_geometry.dart';

void main() {
  for (final width in [720.0, 1224.0]) {
    testWidgets('every Settings form ends with compact switches at $width', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await (FontLoader(
        'Inter',
      )..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2'))).load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      final boundary = GlobalKey();
      final formWidth = width == 720 ? 520.0 : 680.0;
      for (final form in settingsForms) {
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              theme: AccountingTheme.light().copyWith(
                platform: TargetPlatform.macOS,
              ),
              home: Scaffold(
                body: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: SizedBox(
                      width: formWidth,
                      child: FrontendFormDialog(
                        key: ValueKey(form.title),
                        form: form,
                        embedded: true,
                        contentWidth: formWidth,
                        initial: {
                          for (final f in form.fields.where((f) => f.toggle))
                            f.label: true,
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final toggles = form.fields.where((f) => f.toggle).toList();
        final group = find.byKey(ValueKey('settings-switches-${form.title}'));
        if (toggles.isEmpty) {
          expect(group, findsNothing);
          continue;
        }
        await tester.ensureVisible(group);
        await tester.pumpAndSettle();
        for (final field in form.fields.where((f) => !f.toggle)) {
          final input = find.byKey(ValueKey('design-field-${field.label}'));
          if (input.evaluate().isNotEmpty) {
            expect(
              tester.getRect(input).bottom,
              lessThan(tester.getRect(group).top),
              reason: '${form.title}: ${field.label} precedes switches',
            );
          }
        }
        final previousTracks = <int, Rect>{};
        final fieldWidth = (formWidth - 20) / 2;
        final color = AccountingTheme.light()
            .extension<AccountingTokens>()!
            .primary;
        for (final (index, field) in toggles.indexed) {
          final row = find.byKey(ValueKey('design-field-${field.label}'));
          expect(find.descendant(of: group, matching: row), findsOneWidget);
          expect(tester.getRect(row).width, closeTo(fieldWidth, 0.1));
          final switchTarget = find.descendant(
            of: row,
            matching: find.byType(Switch),
          );
          if (field.label == 'Preserve Original Files') {
            expect(tester.widget<Switch>(switchTarget).value, isTrue);
            expect(tester.widget<Switch>(switchTarget).onChanged, isNull);
            continue; // Locked controls use disabled opacity, not solid primary.
          }
          final track = await paintedSurfaceBounds(
            tester,
            boundary,
            switchTarget,
            color,
          );
          final previousTrack = previousTracks[index % 2];
          if (previousTrack != null) {
            expect(
              track.top - previousTrack.bottom,
              closeTo(20, 1),
              reason: '${form.title}: painted tracks, not hit-box margins',
            );
          }
          previousTracks[index % 2] = track;
        }
        final active = toggles
            .where((f) => f.label != 'Preserve Original Files')
            .firstOrNull;
        if (active != null) {
          final row = find.byKey(ValueKey('design-field-${active.label}'));
          final control = find.descendant(
            of: row,
            matching: find.byType(Switch),
          );
          await tester.tap(find.text(active.label));
          await tester.pumpAndSettle();
          expect(tester.widget<Switch>(control).value, isFalse);
          final rowElement = tester.element(row);
          bool rowHasFocus() {
            var inside = false;
            FocusManager.instance.primaryFocus?.context?.visitAncestorElements((
              element,
            ) {
              if (identical(element, rowElement)) inside = true;
              return !inside;
            });
            return inside;
          }

          for (var i = 0; i < 60 && !rowHasFocus(); i++) {
            await tester.sendKeyEvent(LogicalKeyboardKey.tab);
            await tester.pump();
          }
          expect(
            rowHasFocus(),
            isTrue,
            reason: 'Switch row is keyboard reachable',
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.space);
          await tester.pumpAndSettle();
          expect(
            tester.widget<Switch>(control).value,
            isTrue,
            reason: 'The label row retains keyboard activation',
          );
        }
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        if (form.title == 'Sales Preferences' ||
            form.title == 'Purchase Preferences' ||
            form.title == 'Accounting Preferences') {
          await capture(
            boundary,
            '${form.title} Compact Switches ${width.toInt()}',
            tester,
          );
        }
        expect(tester.takeException(), isNull, reason: form.title);
      }
    });
  }

  test(
    'remove redundant/unimplemented switches while preserving record fields',
    () {
      final labels = settingsForms
          .expand((f) => f.fields)
          .map((f) => f.label)
          .toSet();
      expect(
        labels.intersection({
          'Track Classes',
          'Track Locations',
          'Enable Account Numbers',
          'Progress Invoicing',
        }),
        isEmpty,
      );
      expect(
        transactionFields.map((f) => f.label),
        containsAll(['Class', 'Location']),
      );
      expect(
        labels,
        containsAll([
          'Link To Customer',
          'Billable Expenses',
          'Show Rate',
          'Enable Discounts',
        ]),
      );
    },
  );
}
