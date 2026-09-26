import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/naming_setup.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Code Name resolves settings at render time without freezing custom text',
    () {
      final blocks = [
        NamingBlock(type: NamingValue.codeName),
        NamingBlock(type: NamingValue.separator, text: '-'),
        NamingBlock(type: NamingValue.year),
      ];
      final date = DateTime(2026, 10, 2);
      expect(namingPreview(blocks, date, 'GAS', codeName: 'qt'), 'QT-2026');
      expect(
        namingPreview(blocks, date, 'GAS', codeName: 'QUOTE'),
        'QUOTE-2026',
      );
      expect(() => namingPreview(blocks, date, 'GAS'), throwsStateError);
      expect(
        NamingBlock.fromJson(blocks.first.toJson()).type,
        NamingValue.codeName,
      );
    },
  );

  for (final width in [720.0, 1224.0]) {
    testWidgets(
      'Code Name occupies 30 percent before Save Location at $width; preview save writes nothing',
      (tester) async {
        tester.view.physicalSize = Size(width, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final calls = <MethodCall>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(namingSettingsChannel, (call) async {
              calls.add(call);
              return null;
            });
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(namingSettingsChannel, null),
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: AccountingTheme.light(),
            home: const Scaffold(
              body: NamingSetupDialog(demo: true, proposalCodeName: 'QT'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final code = find.byKey(const ValueKey('naming-code-name'));
        final folder = find.byKey(const ValueKey('naming-folder-picker'));
        final codeRect = tester.getRect(code),
            folderRect = tester.getRect(folder);
        expect(
          codeRect.width / (codeRect.width + folderRect.width),
          closeTo(.3, .00001),
        );
        expect(codeRect.top, folderRect.top);
        expect(codeRect.right, lessThan(folderRect.left));
        expect(
          tester
              .widget<SelectableText>(
                find.byKey(const ValueKey('naming-preview')),
              )
              .data,
          'QT',
        );
        await tester.enterText(code, 'INV');
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<SelectableText>(
                find.byKey(const ValueKey('naming-preview')),
              )
              .data,
          'INV',
        );
        await tester.tap(find.byKey(const ValueKey('naming-type-0')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('naming-option-codeName')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const ValueKey('naming-option-year')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('naming-type-0')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('naming-option-codeName')));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<SelectableText>(
                find.byKey(const ValueKey('naming-preview')),
              )
              .data,
          'INV',
        );
        await tester.enterText(code, '');
        await tester.tap(find.byKey(const ValueKey('naming-save')));
        await tester.pumpAndSettle();
        expect(find.text('Enter a filename-safe Code Name.'), findsOneWidget);
        await tester.enterText(code, 'QT');
        await tester.tap(find.byKey(const ValueKey('naming-save')));
        await tester.pumpAndSettle();
        expect(find.text('Enter a filename-safe Code Name.'), findsNothing);
        expect(calls, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
