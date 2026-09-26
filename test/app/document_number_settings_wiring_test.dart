import 'dart:io';
import 'dart:convert';

import 'package:audyt/app/demo_company.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/naming_setup.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/sales/invoice_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixed_popout_host.dart';

void main() {
  testWidgets(
    'saved Settings numbering supplies invoice field and survives reopen',
    (tester) async {
      installFixedPopoutHost(tester);
      tester.view.physicalSize = const Size(1224, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await (FontLoader(
        'Inter',
      )..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2'))).load();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        namingSettingsChannel,
        (call) async => null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          namingSettingsChannel,
          null,
        ),
      );
      final root = Directory.systemTemp.createTempSync(
        'audyt-numbering-proof-',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      var workspace = await createDemoWorkspace(
        databasePath: '${root.path}/books.sqlite',
      );
      addTearDown(() => workspace.dispose());
      final oldId = EntityId.random();
      String allocate(EntityId id) => workspace.database.allocateDocumentNumber(
        businessId: workspace.identity.businessId,
        actorId: workspace.identity.ownerId,
        recordId: id,
        documentType: 'invoice',
        allocatedAt: DateTime.utc(2026, 9, 30),
      );
      final originalNumber = allocate(oldId);
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () =>
                    openAccountingSettings(context, workspace: workspace),
                child: const Text('Settings'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Numbering & Document Appearance'));
      await tester.tap(find.text('Numbering & Document Appearance'));
      await tester.pumpAndSettle();
      final prefix = find.byKey(const ValueKey('design-field-Number Prefix'));
      await tester.ensureVisible(prefix);
      await tester.enterText(prefix, 'AUD');
      final padding = find.byKey(const ValueKey('design-field-Number Padding'));
      await tester.ensureVisible(padding);
      await tester.tap(padding);
      await tester.pumpAndSettle();
      await tester.tap(find.text('4 Digits').last);
      await tester.pumpAndSettle();
      final save = find.byKey(const ValueKey('design-save-settings'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(
        workspace.preferences.text(
          'Numbering & Document Appearance',
          'Number Prefix',
        ),
        'AUD',
      );
      expect(
        workspace.preferences.text(
          'Numbering & Document Appearance',
          'Number Padding',
        ),
        '4 Digits',
      );
      final newId = EntityId.random();
      final savedFormatNumber = allocate(newId);
      expect(savedFormatNumber, 'AUD-0002');
      expect(allocate(oldId), originalNumber);
      await tester.pumpWidget(const SizedBox());
      workspace.dispose();
      workspace = await AccountingWorkspace.open('${root.path}/books.sqlite');
      expect(allocate(oldId), originalNumber);
      expect(allocate(newId), savedFormatNumber);
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(body: InvoicePage(workspace: workspace)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('new-invoice')));
      await tester.pumpAndSettle();
      final number = tester.widget<TextFormField>(
        find.byKey(const ValueKey('design-field-Document Number')),
      );
      expect(number.controller!.text, 'AUD-0003');
      final output = Platform.environment['AUDYT_DESIGN_CAPTURE'];
      if (output != null) {
        File('$output/Document Number Wiring Verification.json')
            .writeAsStringSync(
              jsonEncode({
                'source': 'Real Settings UI > Numbering & Document Appearance > Save; actual SQLite allocator and InvoicePage',
                'originalNumber': originalNumber,
                'savedPrefix': 'AUD',
                'savedPadding': '4 Digits',
                'newNumber': savedFormatNumber,
                'invoiceFormNumberAfterReopen': number.controller!.text,
                'oldNumberRetained': allocate(oldId),
                'isolatedWorkspace': true,
              }),
            );
      }
      await tester.tap(find.byKey(const ValueKey('design-close')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('design-discard-changes')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('design-field-Document Number')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
