import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/features/purchases/domain/claim_store.dart';
import 'package:audyt/features/purchases/presentation/claims_page.dart';
import 'package:audyt/features/accounting/presentation/widgets/accounting_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('warning surface and its gap disappear at ten seconds', (
    tester,
  ) async {
    var validationBlocked = true;
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                const SizedBox(height: 100),
                AccountingAlert.build(
                  context,
                  title: 'Check balances',
                  description: 'Exact decimals required',
                  tone: AccountingAlertTone.warning,
                  topGap: 20,
                  bottomGap: 20,
                ),
                ElevatedButton(
                  onPressed: validationBlocked ? null : () {},
                  child: const Text('Approve'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final before = tester.getTopLeft(find.byType(ElevatedButton)).dy;
    await tester.pump(const Duration(seconds: 9));
    expect(find.text('Exact decimals required'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Exact decimals required'), findsNothing);
    expect(tester.getTopLeft(find.byType(ElevatedButton)).dy, 100);
    expect(before, greaterThan(140));
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNull,
    );
    validationBlocked = false;
  });

  for (final width in [960.0, 390.0]) {
    testWidgets('Claims alert removes its entire extra gap at $width', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(
            body: ClaimsPage(store: ClaimStore(claims: const [])),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final header = tester.getRect(find.byType(AccountingPageHeader));
      // Empty record collections intentionally hide their filter toolbar.
      // The surviving empty-state card must reclaim the alert's entire gap.
      final survivingContent = find.byKey(const ValueKey('claims-empty-state'));
      final before = tester.getRect(survivingContent).top;
      expect(find.text('Offline Workspace'), findsOneWidget);
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      expect(find.text('Offline Workspace'), findsNothing);
      final after = tester.getRect(survivingContent).top;
      expect(after - header.bottom, accountingPageTitleOuterGap);
      expect(after, lessThan(before - 20));
      await tester.pump(const Duration(seconds: 1));
      expect(tester.getRect(survivingContent).top, after);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('shared and custom dialogs clip rounded footer paint', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => AccountingDialog.alert(
              context,
              title: 'Account',
              content: const Text('Choose bank'),
              formFooter: true,
              actions: [
                TextButton(onPressed: () {}, child: const Text('Create')),
              ],
            ),
          ),
        ),
      ),
    );
    final dialog = tester.widget<Dialog>(find.byType(Dialog));
    expect(dialog.clipBehavior, Clip.antiAlias);
    expect(
      tester.widget<AlertDialog>(find.byType(AlertDialog)).clipBehavior,
      Clip.antiAlias,
    );
    expect(
      Theme.of(tester.element(find.byType(Dialog))).dialogTheme.clipBehavior,
      Clip.antiAlias,
    );
    expect(
      find.byKey(const ValueKey('accounting-form-dialog-footer')),
      findsOneWidget,
    );
  });
}
