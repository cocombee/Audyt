import 'dart:ui' show PointerDeviceKind;

import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/features/accounting/presentation/record_expense_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Payee menu opens without assigning a hover background', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(960, 1200));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: const RecordExpensePage(),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('expense-field-payee')));
    await tester.pumpAndSettle();

    for (final id in <String>[
      'demo-payee-aina-rahman',
      'demo-payee-daniel-lim',
      'demo-payee-acme-office-supplies',
    ]) {
      final option = find.byKey(ValueKey<String>('expense-payee-option-$id'));
      expect(option, findsOneWidget);
      final rowMaterial = tester.widget<Material>(
        find.ancestor(of: option, matching: find.byType(Material)).first,
      );
      expect(
        rowMaterial.color,
        Colors.transparent,
        reason: 'Menu opening must not hover $id by default.',
      );
    }
  });

  testWidgets('Payee hover background follows pointer by payee identity', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(960, 1200));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: const RecordExpensePage(),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('expense-field-payee')));
    await tester.pumpAndSettle();
    final aina = find.byKey(
      const ValueKey('expense-payee-option-demo-payee-aina-rahman'),
    );
    final acme = find.byKey(
      const ValueKey('expense-payee-option-demo-payee-acme-office-supplies'),
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(aina));
    await tester.pump();
    expect(
      _payeeRowMaterial(tester, aina).color,
      AccountingTokens.light.accent,
    );
    expect(_payeeRowMaterial(tester, acme).color, Colors.transparent);

    await mouse.moveTo(tester.getCenter(acme));
    await tester.pump();
    expect(_payeeRowMaterial(tester, aina).color, Colors.transparent);
    expect(
      _payeeRowMaterial(tester, acme).color,
      AccountingTokens.light.accent,
    );
  });

  testWidgets('Payee hover state clears when the menu is reopened', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(960, 1200));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: const RecordExpensePage(),
      ),
    );

    final payeeField = find.byKey(const ValueKey('expense-field-payee'));
    final aina = find.byKey(
      const ValueKey('expense-payee-option-demo-payee-aina-rahman'),
    );
    await tester.tap(payeeField);
    await tester.pumpAndSettle();

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(aina));
    await tester.pump();
    expect(
      _payeeRowMaterial(tester, aina).color,
      AccountingTokens.light.accent,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('expense-payee-menu')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('expense-field-date')));
    await tester.pumpAndSettle();
    await mouse.moveTo(const Offset(10, 10));
    await tester.pump();
    await tester.tap(payeeField);
    await tester.pumpAndSettle();

    for (final id in <String>[
      'demo-payee-aina-rahman',
      'demo-payee-daniel-lim',
      'demo-payee-acme-office-supplies',
    ]) {
      final option = find.byKey(ValueKey<String>('expense-payee-option-$id'));
      expect(option, findsOneWidget);
      expect(
        _payeeRowMaterial(tester, option).color,
        Colors.transparent,
        reason: 'Reopened menu must not retain hover for $id.',
      );
    }
  });

  testWidgets('Payee rows center names and badges in a symmetric 44px row', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(960, 1200));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: const RecordExpensePage(),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('expense-field-payee')));
    await tester.pumpAndSettle();
    final option = find.byKey(
      const ValueKey('expense-payee-option-demo-payee-aina-rahman'),
    );
    final name = find.descendant(
      of: option,
      matching: find.text('Aina Rahman'),
    );
    final badge = find.descendant(of: option, matching: find.text('Employee'));
    expect(option, findsOneWidget);
    expect(name, findsOneWidget);
    expect(badge, findsOneWidget);

    final rowRect = tester.getRect(option);
    final nameRect = tester.getRect(name);
    final badgeRect = tester.getRect(badge);
    expect(rowRect.height, greaterThanOrEqualTo(44));
    expect(nameRect.center.dy, closeTo(rowRect.center.dy, 0.5));
    expect(badgeRect.center.dy, closeTo(rowRect.center.dy, 0.5));
    expect(
      nameRect.top - rowRect.top,
      closeTo(rowRect.bottom - nameRect.bottom, 0.5),
    );
    expect(
      badgeRect.top - rowRect.top,
      closeTo(rowRect.bottom - badgeRect.bottom, 0.5),
    );
  });
}

Material _payeeRowMaterial(WidgetTester tester, Finder option) {
  return tester.widget<Material>(
    find.ancestor(of: option, matching: find.byType(Material)).first,
  );
}
