import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audyt/app/app.dart';
import 'package:audyt/app/workspace_bootstrap.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';

void main() {
  testWidgets('startup previews Demo while preserving the saved workspace', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('audyt-live-startup-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/ledger.sqlite';
    final saved = await AccountingWorkspace.open(path);
    final businessId = saved.identity.businessId;
    saved.dispose();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      AccountingWorkspace.storageChannel,
      (call) async => path,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        AccountingWorkspace.storageChannel,
        null,
      ),
    );

    await tester.pumpWidget(const WorkspaceBootstrap());
    await tester.pumpAndSettle();
    final app = tester.widget<AudytApp>(find.byType(AudytApp));
    expect(app.workspace!.identity.businessId, businessId);
    expect(app.startInDemoCompany, isTrue);
    expect(find.byType(DemoCompany), findsOneWidget);
    expect(DemoCompany.active(tester.element(find.byType(AudytApp))), isFalse);
    expect(await app.workspace!.expenses(), isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('production account form persists through workspace restart', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1224, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final dir = Directory.systemTemp.createTempSync('audyt-workspace-ui-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/ledger.sqlite';
    var workspace = await AccountingWorkspace.open(path);
    final business = workspace.identity.businessId;
    final owner = workspace.identity.ownerId;
    await tester.pumpWidget(
      AudytApp(initialPath: '/accounting', workspace: workspace),
    );
    await tester.pumpAndSettle();
    expect(find.text('No Accounts Yet'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('new-ledger-account')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('ledger-account-code')),
      '1000',
    );
    await tester.enterText(
      find.byKey(const ValueKey('ledger-account-name')),
      'Cash At Bank',
    );
    await tester.tap(find.byKey(const ValueKey('ledger-account-type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cash And Cash Equivalents').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-ledger-account')));
    await tester.pumpAndSettle();
    expect(find.text('Cash At Bank'), findsOneWidget);
    expect(await workspace.accounts(), hasLength(1));
    await tester.pumpWidget(const SizedBox());
    workspace.dispose();
    workspace = await AccountingWorkspace.open(path);
    addTearDown(workspace.dispose);
    expect(workspace.identity.businessId, business);
    expect(workspace.identity.ownerId, owner);
    await tester.pumpWidget(
      AudytApp(initialPath: '/accounting', workspace: workspace),
    );
    await tester.pumpAndSettle();
    expect(find.text('Cash At Bank'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'bootstrap failure remains visible and retry opens original workspace',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync('audyt-bootstrap-ui-');
      addTearDown(() => dir.deleteSync(recursive: true));
      var attempts = 0;
      await tester.pumpWidget(
        WorkspaceBootstrap(
          openWorkspace: () async {
            attempts++;
            if (attempts == 1) throw const FileSystemException('Access denied');
            return AccountingWorkspace.open('${dir.path}/ledger.sqlite');
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Accounting Data Could Not Be Opened'), findsOneWidget);
      expect(find.byType(AudytApp), findsNothing);
      await tester.tap(find.byKey(const ValueKey('retry-workspace')));
      await tester.pumpAndSettle();
      expect(attempts, 2);
      expect(find.byType(AudytApp), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final width in [390.0, 900.0, 1224.0]) {
    testWidgets('persisted account page and dialog fit at $width', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final dir = Directory.systemTemp.createTempSync('audyt-accounts-layout-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final workspace = await AccountingWorkspace.open(
        '${dir.path}/ledger.sqlite',
      );
      addTearDown(workspace.dispose);
      await tester.pumpWidget(
        AudytApp(initialPath: '/accounting', workspace: workspace),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final settings = tester.getRect(
        find.byKey(const ValueKey('accounting-settings')),
      );
      final footer = tester.getRect(
        find.byKey(const ValueKey('accounting-settings-footer')),
      );
      expect(footer.left, 0);
      expect(settings.center.dx, footer.center.dx);
      await tester.tap(find.byKey(const ValueKey('new-ledger-account')));
      await tester.pumpAndSettle();
      final field = tester.getRect(
        find.byKey(const ValueKey('ledger-account-name')),
      );
      expect(field.left, greaterThanOrEqualTo(0));
      expect(field.right, lessThanOrEqualTo(width));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
