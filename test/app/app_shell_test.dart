import 'dart:io';

import 'package:audyt/app/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders the complete accounting-only shell', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1200));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const AudytApp());

    for (final label in <String>[
      'Home',
      'Banking',
      'Sales',
      'Expenses',
      'Record Expense',
      'Accounting',
      'Taxes',
      'Reports',
      'Documents',
    ]) {
      expect(find.text(label), findsWidgets);
    }

    expect(find.text('Payroll'), findsNothing);
    expect(find.text('Project Management'), findsNothing);
    expect(find.text('Time Tracking'), findsNothing);
    expect(find.text('CRM'), findsNothing);
    expect(find.text('Warehouse'), findsNothing);
  });

  testWidgets('does not fall through from an excluded deep link', (
    tester,
  ) async {
    await tester.pumpWidget(const AudytApp(initialPath: '/payroll'));

    expect(find.text('Route Not Found'), findsOneWidget);
    expect(find.text('Accounting Home'), findsNothing);
  });

  testWidgets('mounts the real Record Expense route without the placeholder', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() async => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const AudytApp(initialPath: '/record-expense'));

    expect(
      find.byKey(const ValueKey('record-expense-form-card')),
      findsOneWidget,
    );
    for (final key in <String>[
      'expense-field-amount',
      'expense-field-date',
      'expense-field-payee',
      'expense-field-payment-account',
      'expense-field-category',
      'expense-field-tax',
      'expense-advanced-details',
      'expense-field-notes',
      'expense-receipt-dropzone',
      'record-expense-save',
      'record-expense-cancel',
    ]) {
      expect(
        find.byKey(ValueKey<String>(key)),
        findsOneWidget,
        reason: 'Missing mounted Record Expense control $key',
      );
    }
    expect(find.byKey(const ValueKey('expense-field-customer')), findsNothing);
    expect(find.byKey(const ValueKey('expense-field-billable')), findsNothing);
    expect(find.text('Accounting Core'), findsNothing);
    expect(find.text('Included workflow route: /record-expense'), findsNothing);
    expect(find.text('This route is not complete.'), findsNothing);
    expect(find.text('Not implemented in this P0 slice.'), findsNothing);

    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(materialApp.title, 'Audyt');
    expect(materialApp.themeMode, ThemeMode.light);
  });

  testWidgets(
    'wires shared currency and payment account config into vouchers',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 1200));
      addTearDown(() async => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const AudytApp(
          initialPath: '/payment-vouchers',
          accountCurrencyCode: 'EUR',
          paymentAccounts: <String>['EUR Current'],
        ),
      );
      expect(
        find.byKey(const ValueKey('page-title-payment-vouchers')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('payment-voucher-create')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('voucher-amount-prefix')), findsNothing);
      expect(find.text('Amount (€)'), findsOneWidget);
      expect(
        tester
            .widget<InputDecorator>(
              find.descendant(
                of: find.byKey(const ValueKey('voucher-amount')),
                matching: find.byType(InputDecorator),
              ),
            )
            .decoration
            .prefixIcon,
        isNull,
      );
      expect(find.text('€'), findsNothing);
      expect(find.byKey(const ValueKey('voucher-account')), findsOneWidget);
    },
  );

  test('keeps native product identity in Title Case', () {
    final macosBuildSettings = File('macos/Runner/Configs/AppInfo.xcconfig')
        .readAsStringSync();
    final macosInfo = File('macos/Runner/Info.plist').readAsStringSync();
    final iosInfo = File('ios/Runner/Info.plist').readAsStringSync();
    final androidManifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    final windowsResources = File('windows/runner/Runner.rc')
        .readAsStringSync();
    final windowsMain = File('windows/runner/main.cpp').readAsStringSync();

    expect(macosBuildSettings, contains('PRODUCT_NAME = Audyt'));
    expect(macosInfo, contains('<string>Audyt</string>'));
    expect(
      iosInfo,
      contains('<key>CFBundleDisplayName</key>\n\t<string>Audyt</string>'),
    );
    expect(
      iosInfo,
      contains('<key>CFBundleName</key>\n\t<string>Audyt</string>'),
    );
    expect(androidManifest, contains('android:label="Audyt"'));
    expect(windowsResources, contains('VALUE "ProductName", "Audyt"'));
    expect(windowsResources, contains('VALUE "FileDescription", "Audyt"'));
    expect(windowsMain, contains('window.Create(L"Audyt"'));
  });

  testWidgets('navigates through the side menu without replacing the shell', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1200));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const AudytApp());

    await tester.tap(find.text('Banking').first);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('page-title-banking')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('navigation-item-sales-customers')),
      findsOneWidget,
    );
  });

  testWidgets('opens interactive frontend routes before backend integration', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const AudytApp());

    await tester.tap(find.text('Banking').first);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('design-open-form')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('design-open-form')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('design-field-From Account')),
      findsOneWidget,
    );
  });

  testWidgets('keeps the icon rail available at narrow widths', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const AudytApp());

    expect(
      find.byKey(const ValueKey('accounting-navigation-compact-rail')),
      findsOneWidget,
    );
    expect(find.byTooltip('Open Accounting Navigation'), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey('navigation-item-sales-customers')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('page-title-sales-customers')),
      findsOneWidget,
    );
  });
}
