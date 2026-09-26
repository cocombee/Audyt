import 'dart:convert';
import 'dart:io';

import 'package:audyt/app/app.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/presentation/tax_overview_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _tables(AccountingWorkspace workspace) {
  final archive = jsonDecode(
    workspace.database.exportDataArchive(
      workspace.identity.businessId,
      DateTime.utc(2026, 9, 28),
    ),
  ) as Map<String, dynamic>;
  return (jsonDecode(archive['data'] as String)
          as Map<String, dynamic>)['tables']
      as Map<String, dynamic>;
}

void main() {
  testWidgets('preview-only page controls keep drafts out of company records', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1224, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final root = Directory.systemTemp.createTempSync('audyt-preview-pages-');
    addTearDown(() => root.deleteSync(recursive: true));
    final path = '${root.path}/company.sqlite';
    var workspace = await AccountingWorkspace.open(path);
    addTearDown(() => workspace.dispose());
    final before = _tables(workspace);

    await tester.pumpWidget(AudytApp(workspace: workspace));
    await tester.pumpAndSettle();

    Future<void> openArea(String id) async {
      await tester.tap(find.byKey(ValueKey('navigation-item-$id')));
      await tester.pumpAndSettle();
    }

    Future<void> keepPreview(String field, String value) async {
      await tester.tap(find.byKey(const ValueKey('design-open-form')));
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('design-field-$field')), findsOneWidget);
      await tester.enterText(find.byKey(ValueKey('design-field-$field')), value);
      await tester.ensureVisible(find.byKey(const ValueKey('design-review')));
      await tester.tap(find.byKey(const ValueKey('design-review')));
      await tester.pumpAndSettle();
      expect(find.text('Keep Preview'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('design-review')));
      await tester.pumpAndSettle();
      expect(find.text('Edit Preview'), findsOneWidget);
      expect(find.textContaining(value), findsWidgets);
      expect(_tables(workspace), before);
    }

    await openArea('taxes');
    expect(find.byType(TaxOverviewPage), findsOneWidget);
    expect(find.byKey(const ValueKey('design-open-form')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('preview-tab-taxes-2')));
    await tester.pumpAndSettle();
    await keepPreview('Submission Reference', 'PREVIEW-TAX-42');
    await openArea('documents');
    await keepPreview('Document Reference', 'PREVIEW-DOC-42');
    await openArea('taxes');
    expect(find.byType(TaxOverviewPage), findsOneWidget);
    expect(find.textContaining('PREVIEW-TAX-42'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    workspace.dispose();
    workspace = await AccountingWorkspace.open(path);
    expect(_tables(workspace), before);
  });
}
