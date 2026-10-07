import 'dart:async';

import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/field_guidance.dart';
import 'package:audyt/app/workspace_backup_controls.dart';
import 'package:audyt/features/accounting/application/workspace_backup.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'claim_receipts_proposal_test.dart' show capture, tap;
import 'sales_email_settings_dialog_test.dart' show host, keyed;
import 'restored_page_routes_test.dart' show tables;

void main() {
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(WorkspaceBackup.channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('audyt/naming-settings'),
          null,
        );
  });
  for (final width in [720.0, 1162.0]) {
    testWidgets(
      'actual Backup field run fits and preserves commands at $width',
      (t) async {
        var folder = '';
        final calls = <MethodCall>[];
        final folderChoice = Completer<String?>();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(WorkspaceBackup.channel, (call) async {
              calls.add(call);
              return switch (call.method) {
                'info' => <String, Object?>{
                  'folder': folder.isEmpty ? null : folder,
                },
                'chooseFolder' => folderChoice.future,
                'export' => null,
                _ => throw StateError(
                  'Unexpected backup mutation: ${call.method}',
                ),
              };
            });
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('audyt/naming-settings'),
              (_) async => null,
            );
        final w = await host(t, width);
        final before = tables(w);
        await tap(t, keyed('settings-editor-Backup & Export Preferences'));
        await t.ensureVisible(keyed('design-field-Backup Frequency'));
        await t.pumpAndSettle();
        final frequency = t.getRect(keyed('design-field-Backup Frequency'));
        final format = t.getRect(keyed('design-field-Export Format'));
        final destination = t.getRect(keyed('backup-destination'));
        expect(frequency.top, closeTo(format.top, 0.01));
        expect(destination.top, closeTo(frequency.top, 0.01));
        expect(frequency.right, lessThan(format.left));
        expect(format.right, lessThan(destination.left));
        expect(
          destination.width,
          closeTo(
            AccountingButton.normalIconLabelWidth(
              t.element(keyed('backup-destination')),
              'Choose Folder',
              icon: Icons.folder_open_outlined,
            ),
            1,
          ),
        );
        expect(
          destination.width,
          lessThan(t.getSize(keyed('backup-destination-slot')).width),
        );
        expect(destination.height, closeTo(frequency.height, 0.01));
        expect(find.byType(WorkspaceBackupControls), findsOneWidget);
        await t.ensureVisible(find.text('Backup & Export Preferences'));
        await t.pumpAndSettle();
        await capture(t, 'Backup Three Controls Inline ${width.toInt()}');
        for (final label in [
          'Backup Frequency',
          'Export Format',
          'Backup Destination',
        ]) {
          final message = accountingFieldGuidance(label)!;
          expect(find.text(message), findsNothing);
          final help = find.byWidgetPredicate(
            (widget) => widget is AccountingFieldHelp && widget.label == label,
          );
          await t.ensureVisible(help);
          await t.tap(help);
          await t.pumpAndSettle();
          expect(find.text(message), findsOneWidget);
          await capture(t, 'Backup $label Helper ${width.toInt()}');
          Tooltip.dismissAllToolTips();
          await t.pumpAndSettle();
          expect(find.text(message), findsNothing);
        }
        expect(
          find.textContaining('Scheduled backups run while Audyt is open'),
          findsNothing,
        );
        final button = t.widget<ButtonStyleButton>(keyed('backup-destination'));
        button.onPressed!();
        await t.pump();
        expect(
          t.widget<ButtonStyleButton>(keyed('export-data')).onPressed,
          isNull,
        );
        expect(
          t.widget<ButtonStyleButton>(keyed('backup-now')).onPressed,
          isNull,
        );
        folder = '/A long existing backup destination/With several descriptive folder names/For this company';
        folderChoice.complete(folder);
        await t.pumpAndSettle();
        expect(
          calls.where((call) => call.method == 'chooseFolder'),
          hasLength(1),
        );
        final args = Map<String, Object?>.from(
          calls.singleWhere((call) => call.method == 'chooseFolder').arguments
              as Map,
        );
        expect(args['businessId'], w.identity.businessId.value);
        final retained = t.getRect(keyed('backup-destination'));
        expect(
          retained.top,
          greaterThan(t.getRect(keyed('design-field-Backup Frequency')).bottom),
        );
        expect(
          retained.width,
          lessThanOrEqualTo(
            t.getSize(find.byType(WorkspaceBackupControls)).width,
          ),
        );
        await t.ensureVisible(find.text('Backup & Export Preferences'));
        await t.pumpAndSettle();
        await capture(t, 'Backup Existing Long Destination ${width.toInt()}');
        await tap(t, keyed('export-data'));
        expect(calls.where((call) => call.method == 'export'), hasLength(1));
        expect(tables(w), before);
        expect(
          t.widget<ButtonStyleButton>(keyed('backup-destination')).onPressed,
          isNotNull,
        );
        expect(t.takeException(), isNull);
      },
    );
  }
}
