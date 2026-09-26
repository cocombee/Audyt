import 'dart:ui' show PointerDeviceKind;

import 'package:audyt/app/accounting_icons.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/frontend_review.dart';
import 'package:audyt/app/live_settings_catalog.dart';
import 'package:audyt/app/naming_setup.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/menu_visual_geometry.dart';

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(namingSettingsChannel, (call) async => null);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(namingSettingsChannel, null);
  });
  Future<void> fonts() async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  }

  testWidgets('changing country clears the saved region explicitly', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1224, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Map<String, Object?>? saved;
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 680,
              child: FrontendFormDialog(
                form: liveSettingsForms({})
                    .firstWhere((form) => form.title == 'Business Profile'),
                embedded: true,
                initial: const {
                  'Business Name': 'Saved Business',
                  'Country': 'Malaysia',
                  'State / Region': 'Selangor',
                },
                onCommit: (values) async => saved = values,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final country = find.byKey(const ValueKey('design-field-Country'));
    await tester.ensureVisible(country);
    await tester.tap(country);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MenuItemButton, 'Singapore'));
    await tester.pumpAndSettle();
    final save = find.byKey(const ValueKey('design-save-settings'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(saved?['Business Name'], 'Saved Business');
    expect(saved?['Country'], 'Singapore');
    expect(saved?['State / Region'], '');
  });

  for (final title in ['Sales Preferences', 'Purchase Preferences']) {
    testWidgets('$title only shows the custom term for custom choices', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1224, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final term = title == 'Sales Preferences'
          ? 'Default Payment Terms'
          : 'Default Bill Terms';
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: FrontendFormDialog(
                form: settingsForms.firstWhere((f) => f.title == title),
                embedded: true,
                contentWidth: 680,
                initial: {term: 'Due On Receipt'},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final custom = find.byKey(
        const ValueKey('design-field-Custom Term Value'),
      );
      expect(custom, findsNothing);
      Future<void> choose(String label) async {
        final selector = find.byKey(ValueKey('design-field-$term'));
        await tester.ensureVisible(selector);
        await tester.tap(selector);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text(label).last);
        await tester.tap(find.text(label).last);
        await tester.pumpAndSettle();
      }

      await choose('Days After Issue');
      expect(custom, findsOneWidget);
      await tester.enterText(custom, '21');
      await choose('Net 30');
      expect(custom, findsNothing);
      await choose('Day Of Month');
      expect(tester.widget<TextFormField>(custom).controller!.text, '21');
      final button = find.byKey(const ValueKey('design-review'));
      expect(
        find.descendant(of: button, matching: find.text('Preview')),
        findsOneWidget,
      );
      final face = tester.widget<FilledButton>(button);
      final tokens = AccountingTheme.light().extension<AccountingTokens>()!;
      expect(face.style!.backgroundColor!.resolve({}), tokens.primary);
      final eye = find.descendant(
        of: button,
        matching: find.byWidgetPredicate(
          (w) => w is AccountingIcon && w.icon == Icons.visibility_outlined,
        ),
      );
      expect(eye, findsOneWidget);
      expect(
        tester.getRect(eye).right,
        lessThan(tester.getRect(find.text('Preview')).left),
      );
      expect(tester.takeException(), isNull);
    });
  }
  for (final scenario in [
    (
      'Reminders & Approvals',
      'Transaction Approval',
      'Manual Review',
      'Above Threshold',
      ['Approval Threshold'],
    ),
    (
      'Backup & Export Preferences',
      'Date Range',
      'All Dates',
      'Custom',
      ['From Date', 'Through Date'],
    ),
  ]) {
    testWidgets('${scenario.$1} hides unrelated dependent inputs', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1224, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: FrontendFormDialog(
                form: settingsForms.firstWhere((f) => f.title == scenario.$1),
                embedded: true,
                contentWidth: 680,
                initial: {scenario.$2: scenario.$3},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final label in scenario.$5) {
        expect(find.byKey(ValueKey('design-field-$label')), findsNothing);
      }
      final selector = find.byKey(ValueKey('design-field-${scenario.$2}'));
      await tester.ensureVisible(selector);
      await tester.tap(selector);
      await tester.pumpAndSettle();
      await tester.tap(find.text(scenario.$4).last);
      await tester.pumpAndSettle();
      for (final label in scenario.$5) {
        expect(find.byKey(ValueKey('design-field-$label')), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'Settings user access routes to Users without duplicate permissions',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1224, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var visits = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => openAccountingSettings(
                  context,
                  onManageUsers: () => visits++,
                ),
                child: const Text('Settings'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      final section = find.text('Users & Accountant Access');
      await tester.ensureVisible(section);
      await tester.tap(section);
      await tester.pumpAndSettle();
      expect(find.text('Can Change Settings'), findsNothing);
      final manage = find.byKey(const ValueKey('settings-manage-users'));
      await tester.ensureVisible(manage);
      await tester.tap(manage);
      await tester.pumpAndSettle();
      expect(visits, 1);
      expect(find.byType(AlertDialog), findsNothing);
    },
  );
  for (final width in [720.0, 1224.0]) {
    testWidgets(
      'every folder picker uses white hover text, no path subtitle at $width',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 1100));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await fonts();
        final boundary = GlobalKey();
        for (final kind in SetupKind.values) {
          await tester.pumpWidget(
            RepaintBoundary(
              key: boundary,
              child: MaterialApp(
                theme: AccountingTheme.light(),
                home: Scaffold(
                  body: SingleChildScrollView(
                    child: NamingSetupDialog(
                      key: ValueKey(kind),
                      kind: kind,
                      demo: true,
                      embedded: true,
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final picker = find.byKey(const ValueKey('naming-folder-picker'));
          final text = find.descendant(of: picker, matching: find.byType(Text));
          final tokens = AccountingTheme.light().extension<AccountingTokens>()!;
          RenderParagraph paragraph() =>
              tester.renderObject<RenderParagraph>(text);
          expect(paragraph().text.style!.color, tokens.foreground);
          expect(
            find.byKey(const ValueKey('naming-folder-preview')),
            findsNothing,
          );
          final mouse = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          await mouse.addPointer(location: Offset.zero);
          await mouse.moveTo(tester.getCenter(picker));
          await tester.pumpAndSettle();
          expect(
            paragraph().text.style!.color,
            tokens.primaryForeground,
            reason: kind.label,
          );
          await capture(
            boundary,
            '${kind.id} Folder Hover ${width.toInt()}',
            tester,
          );
          await mouse.moveTo(Offset.zero);
          await mouse.removePointer();
          await tester.pumpAndSettle();
          expect(paragraph().text.style!.color, tokens.foreground);
          expect(tester.takeException(), isNull);
        }
      },
    );
  }
}
