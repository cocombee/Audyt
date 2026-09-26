import 'dart:convert';
import 'dart:io';

import 'package:audyt/app/naming_setup.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'journal_workspace_integration_test.dart' show captureUi;

void main() {
  test(
    'renders user-defined sequence with uppercase and independent date tokens',
    () {
      final blocks = [
        NamingBlock(type: NamingValue.custom, text: 'c4'),
        NamingBlock(type: NamingValue.separator, text: '-'),
        NamingBlock(type: NamingValue.custom, text: 'me'),
        NamingBlock(type: NamingValue.separator, text: '-'),
        NamingBlock(type: NamingValue.day),
        NamingBlock(type: NamingValue.separator, text: '.'),
        NamingBlock(type: NamingValue.month),
        NamingBlock(type: NamingValue.separator, text: '.'),
        NamingBlock(type: NamingValue.shortYear),
        NamingBlock(type: NamingValue.separator, text: '-'),
        NamingBlock(type: NamingValue.category),
        NamingBlock(type: NamingValue.day),
        NamingBlock(type: NamingValue.month),
      ];
      expect(
        namingPreview(blocks, DateTime(2026, 9, 13), 'gas'),
        'C4-ME-13.09.26-GAS1309',
      );
      final restored =
          (jsonDecode(jsonEncode(blocks.map((b) => b.toJson()).toList()))
                  as List)
              .map((v) => NamingBlock.fromJson(v as Map<String, dynamic>))
              .toList();
      expect(
        namingPreview(restored, DateTime(2031, 1, 2), 'fuel'),
        'C4-ME-02.01.31-FUEL0201',
      );
    },
  );

  Future<void> showEditor(WidgetTester tester, {String? saved}) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    if (Platform.environment['AUDYT_UI_CAPTURE_DIR'] != null) {
      await (FontLoader('monospace')..addFont(
            Future.value(
              ByteData.sublistView(
                File('/System/Library/Fonts/Menlo.ttc').readAsBytesSync(),
              ),
            ),
          ))
          .load();
    }
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('workspace-capture'),
        child: MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(body: NamingSetupDialog(saved: saved)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'starts with one unselected value and adds another only on plus',
    (tester) async {
      await showEditor(tester);
      expect(find.byKey(const ValueKey('naming-type-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('naming-type-1')), findsNothing);
      expect(find.text('Select Type'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('naming-add')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('naming-type-1')), findsOneWidget);
      await tester.tap(find.byTooltip('Remove value 2'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('naming-type-1')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('first value can be a date token without custom text', (
    tester,
  ) async {
    await showEditor(tester);
    await tester.tap(find.byKey(const ValueKey('naming-type-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('YYYY').last);
    await tester.pumpAndSettle();
    final preview = tester.widget<SelectableText>(
      find.byKey(const ValueKey('naming-preview')),
    );
    expect(preview.data, DateTime.now().year.toString());
    expect(tester.takeException(), isNull);
  });

  testWidgets('uppercase edits persist as a reusable sequence', (tester) async {
    String? saved;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(namingSettingsChannel, (call) async {
          if (call.method == 'loadFolder') return '/Example/C4. Expenses';
          if (call.method == 'commitSetup') {
            saved = (call.arguments as Map)['format'] as String;
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(namingSettingsChannel, null),
    );
    await showEditor(tester, saved: '[{"type":"custom","text":""}]');
    await tester.enterText(find.byKey(const ValueKey('naming-inline-0')), 'me');
    await tester.pump();
    expect(
      tester
          .widget<SelectableText>(find.byKey(const ValueKey('naming-preview')))
          .data,
      'ME',
    );
    await tester.tap(find.byKey(const ValueKey('naming-save')));
    await tester.pumpAndSettle();
    expect(jsonDecode(saved!), [
      {'type': 'custom', 'text': 'ME'},
    ]);
  });

  testWidgets('ordinary filename values stay single-line and keep full text', (
    tester,
  ) async {
    await showEditor(tester, saved: '[{"type":"custom","text":"DEMO"}]');
    final input = find.byKey(const ValueKey('naming-inline-0'));
    for (final value in ['DEMO', 'LONG COMPANY DOCUMENT PREFIX']) {
      await tester.enterText(input, value);
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(input);
      expect(field.maxLines, 1);
      expect(field.expands, isFalse);
      final RenderEditable editable = tester
          .state<EditableTextState>(
            find.descendant(of: input, matching: find.byType(EditableText)),
          )
          .renderEditable;
      final boxes = editable.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: value.length),
      );
      expect(boxes, hasLength(1));
      expect(boxes.single.left, greaterThanOrEqualTo(0));
      expect(boxes.single.right, lessThanOrEqualTo(editable.size.width));
      expect(boxes.single.bottom, lessThanOrEqualTo(editable.size.height));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('growing a filename token pushes its neighboring token right', (
    tester,
  ) async {
    await showEditor(
      tester,
      saved: '[{"type":"custom","text":"DEMO"},{"type":"shortYear","text":""}]',
    );
    final first = find.byKey(const ValueKey('naming-block-frame-0'));
    final second = find.byKey(const ValueKey('naming-block-frame-1'));
    final beforeFirst = tester.getRect(first);
    final beforeSecond = tester.getRect(second);
    await tester.enterText(
      find.byKey(const ValueKey('naming-inline-0')),
      'DEMO COMPANY',
    );
    await tester.pumpAndSettle();
    final afterFirst = tester.getRect(first);
    final afterSecond = tester.getRect(second);
    expect(afterFirst.width, greaterThan(beforeFirst.width));
    expect(afterFirst.left, beforeFirst.left);
    expect(afterFirst.height, beforeFirst.height);
    expect(
      afterSecond.left - beforeSecond.left,
      closeTo(afterFirst.width - beforeFirst.width, .01),
    );
    expect(afterSecond.top, beforeSecond.top);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop typing keeps the first filename character visible', (
    tester,
  ) async {
    await showEditor(tester, saved: '[{"type":"custom","text":"DEMO"}]');
    final input = find.byKey(const ValueKey('naming-inline-0'));
    await tester.tapAt(tester.getCenter(input));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    expect(
      tester.widget<TextField>(input).controller!.selection,
      const TextSelection(baseOffset: 0, extentOffset: 4),
    );
    const value = 'DEMO_PROJECT_INVOICE_REFERENCE_2026';
    for (var length = 5; length <= value.length; length++) {
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: value.substring(0, length),
          selection: TextSelection.collapsed(offset: length),
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));
      final editable = tester
          .state<EditableTextState>(
            find.descendant(of: input, matching: find.byType(EditableText)),
          )
          .renderEditable;
      final box = editable
          .getBoxesForSelection(
            TextSelection(baseOffset: 0, extentOffset: length),
          )
          .single;
      expect(
        box.left,
        greaterThanOrEqualTo(0),
        reason: 'typed $length characters',
      );
      expect(box.right, lessThanOrEqualTo(editable.size.width));
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    final editable = tester
        .state<EditableTextState>(
          find.descendant(of: input, matching: find.byType(EditableText)),
        )
        .renderEditable;
    expect(editable.offset.pixels, 0);
    expect(tester.widget<TextField>(input).controller!.text, value);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('editable filename text uses the ordinary field baseline', (
    tester,
  ) async {
    await showEditor(
      tester,
      saved: '[{"type":"custom","text":"DSAFASDF"},{"type":"shortYear","text":""}]',
    );
    final input = find.byKey(const ValueKey('naming-inline-0'));
    await tester.tapAt(tester.getCenter(input));
    await tester.pumpAndSettle();
    final editable = tester
        .state<EditableTextState>(
          find.descendant(of: input, matching: find.byType(EditableText)),
        )
        .renderEditable;
    final textBox = editable
        .getBoxesForSelection(
          const TextSelection(baseOffset: 0, extentOffset: 8),
        )
        .single;
    final textTop = editable.localToGlobal(Offset(0, textBox.top)).dy;
    final peerField = find.byKey(const ValueKey('naming-date'));
    final peerState = tester.state<EditableTextState>(
      find.descendant(of: peerField, matching: find.byType(EditableText)),
    );
    final peer = peerState.renderEditable;
    final peerBox = peer
        .getBoxesForSelection(
          TextSelection(
            baseOffset: 0,
            extentOffset: peerState.widget.controller.text.length,
          ),
        )
        .single;
    final peerCenter = peer.localToGlobal(peerBox.toRect().center).dy;
    expect(
      textTop + textBox.toRect().height / 2 - tester.getRect(input).top,
      closeTo(peerCenter - tester.getRect(peerField).top, .5),
    );
    expect(textBox.left, greaterThanOrEqualTo(0));
    expect(tester.takeException(), isNull);
    await captureUi(tester, 'Custom Filename Current');
  });

  testWidgets('custom filename retains ordinary caret and selection editing', (
    tester,
  ) async {
    await showEditor(tester, saved: '[{"type":"custom","text":"CUSTOM TEXT"}]');
    final input = find.byKey(const ValueKey('naming-inline-0'));
    final editable = tester
        .state<EditableTextState>(
          find.descendant(of: input, matching: find.byType(EditableText)),
        )
        .renderEditable;
    final caret = editable.getLocalRectForCaret(const TextPosition(offset: 2));
    await tester.tapAt(editable.localToGlobal(caret.center));
    await tester.pump();
    final controller = tester.widget<TextField>(input).controller!;
    expect(controller.selection.isCollapsed, isTrue);
    expect(controller.selection.extentOffset, lessThan(10));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    expect(
      controller.selection,
      const TextSelection(baseOffset: 0, extentOffset: 11),
    );
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'short',
        selection: TextSelection.collapsed(offset: 5),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.text, 'SHORT');
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('does not save incomplete blocks', (tester) async {
    await showEditor(tester);
    await tester.tap(find.byKey(const ValueKey('naming-save')));
    await tester.pumpAndSettle();
    expect(
      find.text('Choose a type and complete each value first.'),
      findsOneWidget,
    );
  });
  testWidgets('preview controls match and custom editing uses just one box', (
    tester,
  ) async {
    await showEditor(tester, saved: '[{"type":"custom","text":"C4"}]');
    final date = tester.getSize(find.byKey(const ValueKey('naming-date')));
    final category = tester.getSize(
      find.byKey(const ValueKey('naming-category')),
    );
    expect(date, category);
    final dateBorder = find.descendant(
      of: find.byKey(const ValueKey('naming-date')),
      matching: find.byType(InputDecorator),
    );
    final categoryBorder = find.descendant(
      of: find.byKey(const ValueKey('naming-category')),
      matching: find.byType(InputDecorator),
    );
    expect(tester.getSize(dateBorder), tester.getSize(categoryBorder));
    expect(tester.getRect(dateBorder).top, tester.getRect(categoryBorder).top);
    expect(find.byType(TextField), findsNWidgets(3));
    expect(find.byKey(const ValueKey('naming-arrow-0')), findsOneWidget);
    expect(find.byTooltip('Remove value 1'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dragging a block updates filename order', (tester) async {
    await showEditor(
      tester,
      saved: '[{"type":"custom","text":"A"},{"type":"custom","text":"B"}]',
    );
    final first = tester.getCenter(find.byType(Draggable<NamingBlock>).at(0));
    final second = tester.getCenter(find.byType(Draggable<NamingBlock>).at(1));
    await tester.dragFrom(first, second - first);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SelectableText>(find.byKey(const ValueKey('naming-preview')))
          .data,
      'BA',
    );
  });
  testWidgets(
    'reorder opens a placeholder before release and has no first remove',
    (tester) async {
      await showEditor(
        tester,
        saved: '[{"type":"custom","text":"A"},{"type":"custom","text":"B"}]',
      );
      expect(find.byTooltip('Remove value 1'), findsNothing);
      expect(find.byTooltip('Remove value 2'), findsOneWidget);
      final first = tester.getCenter(find.byType(Draggable<NamingBlock>).at(0));
      final second = tester.getCenter(
        find.byType(Draggable<NamingBlock>).at(1),
      );
      final originalSize = tester.getSize(find.byType(MenuAnchor).first);
      final gesture = await tester.startGesture(first);
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump();
      await gesture.moveTo(second);
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        tester.getSize(find.byKey(const ValueKey('naming-drag-feedback'))),
        originalSize,
      );
      expect(
        find.byKey(const ValueKey('naming-drag-placeholder')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<SelectableText>(
              find.byKey(const ValueKey('naming-preview')),
            )
            .data,
        'BA',
      );
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('naming-drag-placeholder')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'picker shows root only and commits folder move plus format together',
    (tester) async {
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(namingSettingsChannel, (call) async {
            calls.add(call.method);
            if (call.method == 'chooseFolder') return '/Example/C4. Expenses';
            if (call.method == 'commitSetup') {
              expect(
                (call.arguments as Map)['format'],
                '[{"type":"custom","text":"C4"}]',
              );
              expect(Map.of(call.arguments as Map)..remove('format'), {
                'kind': 'expense',
                'folderPath': '/Example/C4. Expenses',
                'year': DateTime.now().year,
                'month': DateTime.now().month,
              });
              return '/Example/C4. Expenses/${namingFolderSuffix(DateTime.now())}';
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(namingSettingsChannel, null),
      );
      await showEditor(tester, saved: '[{"type":"custom","text":"C4"}]');
      await tester.tap(find.byKey(const ValueKey('naming-folder-picker')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          '/Example/C4. Expenses/${namingFolderSuffix(DateTime.now())}',
        ),
        findsNothing,
      );
      expect(find.text('/Example/C4. Expenses'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('naming-save')));
      await tester.pumpAndSettle();
      expect(calls, contains('commitSetup'));
      expect(calls, isNot(contains('save')));
      expect(
        namingFolderSuffix(DateTime(2026, 9, 13)),
        '2026/09. September 2026',
      );
      expect(
        namingFolderSuffix(DateTime(2026, 10, 1)),
        '2026/10. October 2026',
      );
    },
  );

  testWidgets('folder failure keeps setup edits and does not save format', (
    tester,
  ) async {
    bool saved = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(namingSettingsChannel, (call) async {
          if (call.method == 'loadFolder') return '/Example/C4. Expenses';
          if (call.method == 'commitSetup') {
            throw StateError('permission denied');
          }
          if (call.method == 'save') saved = true;
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(namingSettingsChannel, null),
    );
    await showEditor(tester, saved: '[{"type":"custom","text":"C4"}]');
    await tester.tap(find.byKey(const ValueKey('naming-save')));
    await tester.pumpAndSettle();
    expect(saved, isFalse);
    expect(find.byKey(const ValueKey('naming-inline-0')), findsOneWidget);
  });
  testWidgets('cancelled folder choice reopens the saved destination', (
    tester,
  ) async {
    var commits = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(namingSettingsChannel, (call) async {
          switch (call.method) {
            case 'load':
              return '[{"type":"custom","text":"C4"}]';
            case 'loadFolder':
              return '/Example/Existing Expenses';
            case 'chooseFolder':
              return '/Example/New Expenses';
            case 'commitSetup':
              commits++;
              return null;
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(namingSettingsChannel, null),
    );
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => openNamingSetup(context),
              child: const Text('Open Setup'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open Setup'));
    await tester.pumpAndSettle();
    expect(find.text('/Example/Existing Expenses'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('naming-folder-picker')));
    await tester.pumpAndSettle();
    expect(find.text('/Example/New Expenses'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('naming-cancel')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open Setup'));
    await tester.pumpAndSettle();
    expect(find.text('/Example/Existing Expenses'), findsOneWidget);
    expect(find.text('/Example/New Expenses'), findsNothing);
    expect(commits, 0);
  });
  testWidgets(
    'compact trigger retains readable type menu and shared selected surface',
    (tester) async {
      await showEditor(tester, saved: '[{"type":"day","text":""}]');
      final box = tester.getSize(find.byType(MenuAnchor).first);
      await tester.tap(find.byKey(const ValueKey('naming-type-0')));
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(const ValueKey('naming-option-day'))).width,
        greaterThan(box.width),
      );
      final selected = tester.widget<MenuItemButton>(
        find.byKey(const ValueKey('naming-option-day')),
      );
      final unselected = tester.widget<MenuItemButton>(
        find.byKey(const ValueKey('naming-option-year')),
      );
      final tokens = AccountingTheme.of(
        tester.element(find.byKey(const ValueKey('naming-option-day'))),
      );
      expect(
        selected.style!.backgroundColor!.resolve({}),
        tokens.primary.withValues(alpha: .10),
      );
      expect(
        unselected.style!.backgroundColor!.resolve({WidgetState.hovered}),
        tokens.accent,
      );
      expect(find.byIcon(Icons.check), findsNothing);
    },
  );
  testWidgets('separator offers only safe symbols and keeps type menu', (
    tester,
  ) async {
    await showEditor(tester, saved: '[{"type":"separator","text":"-"}]');
    expect(find.byKey(const ValueKey('naming-inline-0')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('naming-separator-0')));
    await tester.pumpAndSettle();
    for (final symbol in ['.', '-', '_']) {
      expect(find.byKey(ValueKey('separator-option-$symbol')), findsOneWidget);
    }
    await tester.tap(find.byKey(const ValueKey('separator-option-_')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SelectableText>(find.byKey(const ValueKey('naming-preview')))
          .data,
      '_',
    );
    await tester.tap(find.byKey(const ValueKey('naming-arrow-0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('naming-option-day')), findsOneWidget);
  });
}
