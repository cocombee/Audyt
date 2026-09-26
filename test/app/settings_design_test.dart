import 'package:audyt/features/accounting/application/accounting_workspace.dart';

import 'dart:io';
import 'dart:ui' show PointerDeviceKind;

import 'package:audyt/app/access_design.dart';
import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_icons.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/field_guidance.dart';
import 'package:audyt/app/frontend_review.dart';
import 'package:audyt/app/naming_setup.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'journal_workspace_integration_test.dart' show captureUi;

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
    if (Platform.environment['AUDYT_UI_CAPTURE_DIR'] == null) return;
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2'))).load();
    await (FontLoader('Arial')..addFont(
          Future.value(
            ByteData.sublistView(
              File('/System/Library/Fonts/Supplemental/Arial.ttf')
                  .readAsBytesSync(),
            ),
          ),
        ))
        .load();
  }

  test('all catalog fields have brief guidance', () {
    final missing = <String>[];
    for (final form in [
      ...settingsForms,
      ...frontendAreas.values.expand((x) => x),
    ]) {
      for (final field in form.fields) {
        if (accountingFieldGuidance(field.label)?.trim().isNotEmpty != true) {
          missing.add('${form.title}: ${field.label}');
        }
      }
    }
    expect(
      missing,
      isEmpty,
      reason: 'Every catalog field must retain brief guidance.',
    );
  });
  testWidgets('section tabs show selected surface and change the panel', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1224, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await fonts();
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('workspace-capture'),
        child: MaterialApp(
          theme: AccountingTheme.light(),
          home: const Scaffold(
            body: FrontendAreaPage(
              area: 'sales-customers',
              title: 'Sales & Customers',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('preview-tab-sales-customers-1')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Add Customer'), findsOneWidget);
    final tabs = tester.widget<TabBar>(find.byType(TabBar));
    expect(tabs.controller!.index, 1);
    expect(
      (tabs.indicator as BoxDecoration).color,
      AccountingTheme.light().extension<AccountingTokens>()!.card,
    );
    expect(tabs.indicatorPadding, EdgeInsets.zero);
    await captureUi(tester, 'Selected Sales Tab');
  });
  for (final width in [1224.0, 720.0]) {
    testWidgets(
      'Settings expands inline, retains inputs and uses compact arrows at $width',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await fonts();
        final workspace = await AccountingWorkspace.open(':memory:');
        addTearDown(workspace.dispose);
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: MaterialApp(
              theme: AccountingTheme.light().copyWith(
                platform: TargetPlatform.macOS,
              ),
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () =>
                        openAccountingSettings(context, workspace: workspace),
                    child: const Text('Open Settings'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open Settings'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        await captureUi(tester, 'Settings Cards ${width.toInt()}');
        final header = find.text('Business Profile');
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(tester.getCenter(header));
        await tester.pumpAndSettle();
        await captureUi(tester, 'Settings Inner Row Hover ${width.toInt()}');
        await mouse.moveTo(tester.getCenter(find.text('Default Accounts')));
        await tester.pumpAndSettle();
        await captureUi(tester, 'Settings Card End Hover ${width.toInt()}');
        await mouse.removePointer();
        await tester.tap(header);
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        final name = find.byKey(const ValueKey('design-field-Business Name'));
        await tester.ensureVisible(name);
        await tester.enterText(name, 'Example Business');
        await tester.ensureVisible(header);
        await tester.tap(header);
        await tester.pumpAndSettle();
        await tester.tap(header);
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextFormField>(name).controller!.text,
          'Example Business',
        );
        await tester.ensureVisible(
          find.descendant(
            of: find.byWidgetPredicate(
              (w) =>
                  w is AccountingFieldHelp &&
                  w.label.startsWith('Business Name'),
            ),
            matching: find.byType(IconButton),
          ),
        );
        await tester.tap(
          find.descendant(
            of: find.byWidgetPredicate(
              (w) =>
                  w is AccountingFieldHelp &&
                  w.label.startsWith('Business Name'),
            ),
            matching: find.byType(IconButton),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('The business name customers see on your documents.'),
          findsOneWidget,
        );
        await captureUi(tester, 'Inline Settings Help ${width.toInt()}');
        Tooltip.dismissAllToolTips();
        await tester.ensureVisible(header);
        await tester.tap(header);
        await tester.pumpAndSettle();
        final numbering = find.text('Numbering & Document Appearance');
        await tester.ensureVisible(numbering);
        await tester.tap(numbering);
        await tester.pumpAndSettle();
        final showLogo = find.byKey(const ValueKey('design-field-Show Logo'));
        await tester.ensureVisible(showLogo);
        await tester.pumpAndSettle();
        final toggle = find.descendant(
          of: showLogo,
          matching: find.byType(Switch),
        );
        final initial = tester.widget<Switch>(toggle).value;
        final showLogoLabel = find.descendant(
          of: showLogo,
          matching: find.text('Show Logo'),
        );
        await tester.ensureVisible(showLogoLabel);
        await tester.tap(showLogoLabel);
        await tester.pumpAndSettle();
        expect(tester.widget<Switch>(toggle).value, !initial);
        await captureUi(
          tester,
          'Settings Switch ${!initial ? 'On' : 'Off'} ${width.toInt()}',
        );
        await tester.ensureVisible(toggle);
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(tester.widget<Switch>(toggle).value, initial);
        await captureUi(
          tester,
          'Settings Switch ${initial ? 'On' : 'Off'} ${width.toInt()}',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('render the complete settings-only small icon family', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(720, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await fonts();
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('workspace-capture'),
        child: MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const Text(
                    'Existing small controls / Settings reuse or new variant',
                  ),
                  for (final icon in const [
                    Icons.business_outlined,
                    Icons.account_tree_outlined,
                    Icons.account_balance_outlined,
                    Icons.receipt_outlined,
                    Icons.shopping_bag_outlined,
                    Icons.description_outlined,
                    Icons.file_upload_outlined,
                    Icons.notifications_none,
                    Icons.percent_outlined,
                    Icons.badge_outlined,
                    Icons.note_add_outlined,
                    Icons.download_outlined,
                    Icons.person_outline,
                    Icons.history_outlined,
                    Icons.receipt_long,
                    Icons.assignment_turned_in_outlined,
                    Icons.checklist_outlined,
                    Icons.chevron_right,
                  ])
                    SizedBox(
                      height: 50,
                      child: Row(
                        children: [
                          SizedBox(
                            width: 240,
                            child: Text(AccountingIcon.assets[icon]!),
                          ),
                          const SizedBox(width: 20),
                          AccountingIcon.smallAction(icon),
                          const SizedBox(width: 40),
                          AccountingSettingsIcon(icon),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await captureUi(tester, 'Settings Small Icon Family');
    expect(tester.takeException(), isNull);
  });
  testWidgets('sign-in walkthrough changes only preview states', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: const Scaffold(
          body: SingleChildScrollView(child: AccessDesignPanel()),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('access-next')));
    await tester.pumpAndSettle();
    expect(find.text('Continue In Your Browser'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('access-next')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('access-example-business')));
    await tester.pumpAndSettle();
    expect(find.text('Your Session'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('access-next')));
    await tester.pumpAndSettle();
    expect(find.text('Sign In To Audyt'), findsOneWidget);
  });
}
